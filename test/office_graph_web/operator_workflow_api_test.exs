defmodule OfficeGraphWeb.OperatorWorkflowApiTest do
  use OfficeGraphWeb.ConnCase, async: false

  alias OfficeGraph.ApiSupport
  alias OfficeGraph.Foundation
  alias OfficeGraph.Integrations
  alias OfficeGraph.Operations
  alias OfficeGraph.OperatorCommandFixtures
  alias OfficeGraph.ProposedChanges
  alias OfficeGraph.SessionCaseHelpers
  alias OfficeGraph.Verification
  alias OfficeGraph.WorkGraph
  alias OfficeGraph.WorkPackets

  @relay_inbox_query """
  query RelayInbox($first: Int!, $after: String) {
    operatorWorkflowItems(first: $first, after: $after) {
      pageInfo {
        hasNextPage
        hasPreviousPage
        startCursor
        endCursor
      }
      edges {
        cursor
        node {
          id
          normalizedEventId
          title
          sourceSummary
          proposedActionPreviews { action title status }
          status
          blockerReasons
          source { identity replayIdentity outcome }
          proposedChangeStatus { pending applied rejected total }
          allowedNextActions
          commandAffordances {
            identity
            state
            reasonCodes
            blockerReasons
            safeExplanation
            requiredFields
            inputDefaults { field value values }
            targetIds { type id }
            traceLinks { type id }
            decisionLinks { type id }
          }
        }
      }
    }
  }
  """

  test "GraphQL exposes operator inbox and item detail", %{conn: conn} do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, intake} = submit_manual_intake(bootstrap.session, "graphql-inbox")
    {:ok, _newer_intake} = submit_manual_intake(bootstrap.session, "graphql-inbox-newer")

    inbox = graphql(conn, @relay_inbox_query, %{first: 1}, "operatorWorkflowItems")
    assert inbox["pageInfo"]["hasNextPage"] == true

    next_inbox =
      graphql(
        conn,
        @relay_inbox_query,
        %{first: 1, after: inbox["pageInfo"]["endCursor"]},
        "operatorWorkflowItems"
      )

    assert next_inbox["pageInfo"]["hasNextPage"] == false
    assert [%{"node" => row}] = next_inbox["edges"]
    assert row["normalizedEventId"] == intake.normalized_event.id
    assert row["status"] == "pending_triage"
    assert row["allowedNextActions"] == ["apply_proposed_changes"]
    normalized_event_id = intake.normalized_event.id
    proposed_change_ids = Enum.map(intake.proposed_changes, & &1.id)

    assert [
             %{
               "identity" => "apply_proposed_changes",
               "state" => "enabled",
               "reasonCodes" => [],
               "blockerReasons" => [],
               "safeExplanation" => "Apply pending proposed changes for this intake.",
               "requiredFields" => ["normalized_event_id", "proposed_change_ids"],
               "inputDefaults" => [
                 %{
                   "field" => "normalized_event_id",
                   "value" => ^normalized_event_id,
                   "values" => []
                 },
                 %{
                   "field" => "proposed_change_ids",
                   "value" => nil,
                   "values" => ^proposed_change_ids
                 }
               ],
               "targetIds" => [
                 %{
                   "type" => "normalized_intake_event",
                   "id" => ^normalized_event_id
                 }
               ],
               "traceLinks" => [],
               "decisionLinks" => []
             }
           ] = row["commandAffordances"]

    assert normalized_event_id == intake.normalized_event.id
    assert row["source"]["replayIdentity"] == "paste:graphql-inbox"
    assert row["proposedChangeStatus"]["pending"] == 4

    {:ok, applied} = apply_changes(bootstrap.session, intake.proposed_changes)

    item =
      graphql(
        conn,
        """
        query Item($id: ID!) {
          operatorWorkflowItem(id: $id) {
            status
            allowedNextActions
            commandAffordances {
              identity
              state
              reasonCodes
              blockerReasons
              safeExplanation
              requiredFields
              inputDefaults { field value values }
              targetIds { type id }
              traceLinks { type id }
              decisionLinks { type id }
            }
            blockerReasons
            graphLinks { type id graphItemId state }
            graphRelationships { relationshipType }
            auditTrace { resourceCount }
            revisionTrace { resourceCount }
          }
        }
        """,
        %{id: intake.normalized_event.id},
        "operatorWorkflowItem"
      )

    assert item["status"] == "ready_for_packet"
    assert item["allowedNextActions"] == ["create_work_packet"]
    assert item["blockerReasons"] == []
    assert [prepare_command] = item["commandAffordances"]
    assert prepare_command["identity"] == "create_work_packet"
    assert prepare_command["state"] == "enabled"
    assert prepare_command["reasonCodes"] == []
    assert prepare_command["blockerReasons"] == []
    assert prepare_command["safeExplanation"] == "Prepare a work packet from the applied intake."

    assert prepare_command["requiredFields"] == [
             "title",
             "objective",
             "context_summary",
             "requirements",
             "success_criteria",
             "autonomy_posture",
             "source_graph_item_ids",
             "verification_check_ids"
           ]

    assert %{"field" => "title", "value" => applied.verification_check.title, "values" => []} in prepare_command[
             "inputDefaults"
           ]

    assert %{"field" => "source_graph_item_ids", "value" => nil, "values" => source_ids} =
             Enum.find(
               prepare_command["inputDefaults"],
               &(&1["field"] == "source_graph_item_ids")
             )

    assert applied.verification_check.graph_item_id in source_ids

    assert %{
             "field" => "verification_check_ids",
             "value" => nil,
             "values" => [applied.verification_check.id]
           } in prepare_command["inputDefaults"]

    assert %{"type" => "operation"} = hd(prepare_command["traceLinks"])
    assert prepare_command["decisionLinks"] == []

    assert Enum.map(item["graphLinks"], & &1["type"]) == [
             "signal",
             "task",
             "review_finding",
             "verification_check"
           ]

    assert Enum.find(item["graphLinks"], &(&1["type"] == "signal"))["id"] == applied.signal.id
    assert Enum.find(item["graphLinks"], &(&1["type"] == "task"))["id"] == applied.task.id

    assert Enum.find(item["graphLinks"], &(&1["type"] == "review_finding"))["id"] ==
             applied.review_finding.id

    assert Enum.find(item["graphLinks"], &(&1["type"] == "verification_check"))["id"] ==
             applied.verification_check.id

    prepare_targets = prepare_command["targetIds"]

    assert %{"type" => "verification_check", "id" => applied.verification_check.id} in prepare_targets

    assert Enum.map(item["graphRelationships"], & &1["relationshipType"]) == [
             "produced_task",
             "has_review_finding",
             "requires_verification"
           ]

    assert item["auditTrace"]["resourceCount"] == 4
    assert item["revisionTrace"]["resourceCount"] == 4

    first_related =
      graphql(
        conn,
        """
        query Related($id: ID!, $first: Int!, $after: String) {
          operatorRelationshipDetails(id: $id, first: $first, after: $after) {
            edges { cursor node { kind stableId title relationshipType } }
            pageInfo { hasNextPage hasPreviousPage startCursor endCursor }
          }
        }
        """,
        %{id: intake.normalized_event.id, first: 2},
        "operatorRelationshipDetails"
      )

    assert length(first_related["edges"]) == 2
    assert first_related["pageInfo"]["hasNextPage"] == true

    second_related =
      graphql(
        conn,
        """
        query RelatedPage($id: ID!, $first: Int!, $after: String) {
          operatorRelationshipDetails(id: $id, first: $first, after: $after) {
            edges { cursor node { kind stableId title relationshipType } }
            pageInfo { hasNextPage hasPreviousPage startCursor endCursor }
          }
        }
        """,
        %{
          id: intake.normalized_event.id,
          first: 2,
          after: first_related["pageInfo"]["endCursor"]
        },
        "operatorRelationshipDetails"
      )

    assert length(second_related["edges"]) == 2
    assert second_related["pageInfo"]["hasPreviousPage"] == true
  end

  test "GraphQL exposes Relay node ids and connection pagination for operator workflow items",
       %{conn: conn} do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, older_intake} = submit_manual_intake(bootstrap.session, "relay-inbox-older")
    {:ok, _newer_intake} = submit_manual_intake(bootstrap.session, "relay-inbox-newer")

    first_page = graphql(conn, @relay_inbox_query, %{first: 1}, "operatorWorkflowItems")

    assert first_page["pageInfo"]["hasNextPage"] == true
    assert first_page["pageInfo"]["hasPreviousPage"] == false
    assert is_binary(first_page["pageInfo"]["endCursor"])
    assert [%{"cursor" => first_cursor, "node" => first_node}] = first_page["edges"]
    assert is_binary(first_cursor)
    assert is_binary(first_node["id"])
    assert first_node["id"] != first_node["normalizedEventId"]

    second_page =
      graphql(
        conn,
        @relay_inbox_query,
        %{first: 1, after: first_page["pageInfo"]["endCursor"]},
        "operatorWorkflowItems"
      )

    assert second_page["pageInfo"]["hasNextPage"] == false
    assert second_page["pageInfo"]["hasPreviousPage"] == true
    assert [%{"node" => second_node}] = second_page["edges"]
    assert second_node["normalizedEventId"] == older_intake.normalized_event.id

    node =
      graphql(
        conn,
        """
        query Node($id: ID!) {
          node(id: $id) {
            id
            ... on OperatorWorkflowItem {
              normalizedEventId
              status
            }
          }
        }
        """,
        %{id: second_node["id"]},
        "node"
      )

    assert node["id"] == second_node["id"]
    assert node["normalizedEventId"] == older_intake.normalized_event.id
    assert node["status"] == "pending_triage"
  end

  test "Relay pagination preserves zero edges and rejects negative first", %{conn: conn} do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, _intake} = submit_manual_intake(bootstrap.session, "relay-edge-semantics")

    zero_page = graphql(conn, @relay_inbox_query, %{first: 0}, "operatorWorkflowItems")
    assert zero_page["edges"] == []
    assert zero_page["pageInfo"]["hasNextPage"] == true
    assert zero_page["pageInfo"]["hasPreviousPage"] == false
    assert zero_page["pageInfo"]["startCursor"] == nil
    assert zero_page["pageInfo"]["endCursor"] == nil

    response =
      conn
      |> post(~p"/graphql", %{query: @relay_inbox_query, variables: %{first: -1}})
      |> json_response(200)

    assert [%{"message" => "A field has an invalid value."}] = response["errors"]
    refute get_in(response, ["data", "operatorWorkflowItems"])
  end

  test "schema omits retired operator fields and exposes root command option paging", %{
    conn: conn
  } do
    root_response =
      conn
      |> post(~p"/graphql", %{
        query: "{ __type(name: \"RootQueryType\") { fields { name } } }"
      })
      |> json_response(200)

    assert root_response["errors"] in [nil, []]
    root_fields = get_in(root_response, ["data", "__type", "fields"])
    refute Enum.any?(root_fields, &(&1["name"] == "operatorInbox"))
    assert Enum.any?(root_fields, &(&1["name"] == "operatorRunCommandOptionPage"))

    run_state_response =
      conn
      |> post(~p"/graphql", %{
        query: "{ __type(name: \"OperatorRunState\") { fields { name } } }"
      })
      |> json_response(200)

    assert run_state_response["errors"] in [nil, []]
    run_state_fields = get_in(run_state_response, ["data", "__type", "fields"])
    refute Enum.any?(run_state_fields, &(&1["name"] == "commandOptionPage"))
  end

  test "pending rows from one source expose distinct safe summaries and proposal previews", %{
    conn: conn
  } do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    {:ok, first} =
      submit_manual_intake(bootstrap.session, "safe-summary-first",
        source_identity: "SECRET_SOURCE=must-not-leak",
        body: "SECRET_TOKEN=must-not-leak. Investigate failed invoice export."
      )

    {:ok, second} =
      submit_manual_intake(bootstrap.session, "safe-summary-second",
        source_identity: "PRIVATE_SOURCE=must-not-leak",
        body: "PRIVATE_ARCHIVE=must-not-leak. Review delayed payroll import."
      )

    {:ok, sensitive_only} =
      submit_manual_intake(bootstrap.session, "safe-summary-sensitive-only",
        source_identity: "manual:sensitive-only",
        body: "AWS access key AKIAIOSFODNN7EXAMPLE"
      )

    shared_inserted_at = first.normalized_event.inserted_at
    force_intake_inserted_at!(second.normalized_event.id, shared_inserted_at)

    page = graphql(conn, @relay_inbox_query, %{first: 10}, "operatorWorkflowItems")
    rows = Enum.map(page["edges"], & &1["node"])

    first_row = Enum.find(rows, &(&1["normalizedEventId"] == first.normalized_event.id))
    second_row = Enum.find(rows, &(&1["normalizedEventId"] == second.normalized_event.id))

    sensitive_only_row =
      Enum.find(rows, &(&1["normalizedEventId"] == sensitive_only.normalized_event.id))

    first_title = intake_title(first.normalized_event.id, shared_inserted_at)
    second_title = intake_title(second.normalized_event.id, shared_inserted_at)

    sensitive_only_title =
      intake_title(
        sensitive_only.normalized_event.id,
        sensitive_only.normalized_event.inserted_at
      )

    assert first_row["title"] == first_title
    assert second_row["title"] == second_title
    assert sensitive_only_row["title"] == sensitive_only_title
    assert first_title != second_title

    assert first_row["sourceSummary"] ==
             "#{first_title} · 4 proposed changes"

    assert second_row["sourceSummary"] ==
             "#{second_title} · 4 proposed changes"

    assert sensitive_only_row["sourceSummary"] ==
             "#{sensitive_only_title} · 4 proposed changes"

    assert Enum.all?(first_row["proposedActionPreviews"], fn preview ->
             preview["title"] =~ first_title
           end)

    assert Enum.all?(second_row["proposedActionPreviews"], fn preview ->
             preview["title"] =~ second_title
           end)

    assert Enum.map(first_row["proposedActionPreviews"], & &1["action"]) == [
             "create_signal",
             "create_task",
             "create_review_finding",
             "create_verification_check"
           ]

    encoded =
      rows
      |> Enum.map(&Map.take(&1, ["title", "sourceSummary", "proposedActionPreviews"]))
      |> Jason.encode!()

    refute encoded =~ "SECRET_TOKEN"
    refute encoded =~ "PRIVATE_ARCHIVE"
    refute encoded =~ "SECRET_SOURCE"
    refute encoded =~ "PRIVATE_SOURCE"
    refute encoded =~ "AKIAIOSFODNN7EXAMPLE"
    refute encoded =~ first.raw_archive.id
    refute encoded =~ second.raw_archive.id
    refute encoded =~ sensitive_only.raw_archive.id
    refute encoded =~ first.normalized_event.id
    refute encoded =~ second.normalized_event.id
    refute encoded =~ sensitive_only.normalized_event.id
  end

  test "GraphQL operator workflow Relay cursors remain stable when new intake arrives between pages",
       %{conn: conn} do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, older_intake} = submit_manual_intake(bootstrap.session, "relay-stable-older")
    {:ok, newer_intake} = submit_manual_intake(bootstrap.session, "relay-stable-newer")
    base_inserted_at = DateTime.utc_now() |> DateTime.add(-120, :second)

    force_intake_inserted_at!(
      older_intake.normalized_event.id,
      DateTime.add(base_inserted_at, -60, :second)
    )

    force_intake_inserted_at!(newer_intake.normalized_event.id, base_inserted_at)

    first_page = graphql(conn, @relay_inbox_query, %{first: 1}, "operatorWorkflowItems")

    assert [%{"node" => first_node}] = first_page["edges"]
    assert first_node["normalizedEventId"] == newer_intake.normalized_event.id

    {:ok, _newest_intake} = submit_manual_intake(bootstrap.session, "relay-stable-newest")

    second_page =
      graphql(
        conn,
        @relay_inbox_query,
        %{first: 1, after: first_page["pageInfo"]["endCursor"]},
        "operatorWorkflowItems"
      )

    assert [%{"node" => second_node}] = second_page["edges"]
    refute second_node["normalizedEventId"] == first_node["normalizedEventId"]
    assert second_node["normalizedEventId"] == older_intake.normalized_event.id
  end

  test "GraphQL exposes packet readiness, run state, and verification outcome", %{conn: conn} do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)

    readiness_input = %{
      title: "Ready GraphQL packet",
      objective: "Resolve the selected verification check.",
      context_summary: "A triaged item is ready for GraphQL execution.",
      requirements: "Use the linked graph item.",
      success_criteria: "Accepted passing evidence exists.",
      autonomy_posture: "human_supervised",
      source_graph_item_ids: [verification_check.graph_item_id],
      verification_check_ids: [verification_check.id]
    }

    readiness =
      graphql(
        conn,
        """
        query Readiness($input: OperatorPacketReadinessInput!) {
          operatorPacketReadiness(input: $input) {
            status
            ready
            sourceWatermark
            allowedNextActions
            commandAffordances {
              identity
              state
              reasonCodes
              blockerReasons
              safeExplanation
              requiredFields
              inputDefaults { field value values }
              targetIds { type id }
              traceLinks { type id }
              decisionLinks { type id }
            }
            blockerReasons
            requiredChecks { id graphItemId state }
          }
        }
        """,
        %{input: camelize_keys(readiness_input)},
        "operatorPacketReadiness"
      )

    assert readiness["status"] == "packet_ready"
    assert readiness["ready"] == true
    assert is_binary(readiness["sourceWatermark"])
    assert readiness["allowedNextActions"] == ["create_work_packet"]
    assert [create_packet] = readiness["commandAffordances"]
    assert create_packet["identity"] == "create_work_packet"
    assert create_packet["state"] == "enabled"
    assert create_packet["reasonCodes"] == []
    assert create_packet["blockerReasons"] == []

    assert create_packet["safeExplanation"] ==
             "Create a work packet from the selected sources and checks."

    assert %{"field" => "title", "value" => "Ready GraphQL packet", "values" => []} in create_packet[
             "inputDefaults"
           ]

    assert [%{"id" => check_id, "graphItemId" => graph_item_id, "state" => "required"}] =
             readiness["requiredChecks"]

    assert check_id == verification_check.id
    assert graph_item_id == verification_check.graph_item_id

    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    {:ok, observation_result} =
      record_observation(bootstrap.session, run_result.run, verification_check,
        key: "graphql-run"
      )

    {:ok, candidate} =
      create_evidence_candidate(
        bootstrap.session,
        run_result.run,
        verification_check,
        observation_result.observation,
        key: "graphql-run"
      )

    run_state =
      graphql(
        conn,
        """
        query RunState($id: ID!) {
          operatorRunState(id: $id) {
            status
            sourceWatermark
            allowedNextActions
            commandAffordances {
              identity
              state
              reasonCodes
              blockerReasons
              safeExplanation
              requiredFields
              inputDefaults { field value values }
              targetIds { type id }
              traceLinks { type id }
              decisionLinks { type id }
            }
            run { id aggregateState verificationState }
            missingEvidence { verificationCheckId reason }
            evidenceCandidates { id state verificationCheckId executionObservationId }
          }
        }
        """,
        %{id: run_result.run.id},
        "operatorRunState"
      )

    assert run_state["status"] == "awaiting_evidence_acceptance"
    assert is_binary(run_state["sourceWatermark"])
    assert run_state["allowedNextActions"] == ["accept_evidence", "waive_verification_check"]
    assert [accept_evidence, waive_check] = run_state["commandAffordances"]
    assert accept_evidence["identity"] == "accept_evidence"
    assert accept_evidence["state"] == "enabled"
    assert accept_evidence["reasonCodes"] == []
    assert accept_evidence["blockerReasons"] == []

    assert accept_evidence["safeExplanation"] ==
             "Accept a candidate as evidence for a missing check."

    assert accept_evidence["inputDefaults"] == []
    assert waive_check["identity"] == "waive_verification_check"
    assert waive_check["state"] == "enabled"

    assert run_state["run"]["id"] == run_result.run.id
    assert hd(run_state["missingEvidence"])["reason"] == "missing_accepted_evidence"
    assert hd(run_state["evidenceCandidates"])["id"] == candidate.id
    assert %{"type" => "evidence_candidate", "id" => candidate.id} in accept_evidence["targetIds"]

    assert hd(run_state["evidenceCandidates"])["executionObservationId"] ==
             observation_result.observation.id

    {:ok, accepted} =
      accept_candidate(bootstrap.session, candidate, key: "graphql-run", result: "passed")

    outcome =
      graphql(
        conn,
        """
        query Outcome($id: ID!) {
          operatorVerificationOutcome(id: $id) {
            status
            run { id }
            verificationResults {
              id
              result
              evidenceItemId
              operationId
              actorPrincipalId
              policyBasis
              targetGraphItemId
            }
            missingEvidence { verificationCheckId reason }
          }
        }
        """,
        %{id: accepted.work_run.id},
        "operatorVerificationOutcome"
      )

    assert outcome["status"] == "verified"
    assert outcome["run"]["id"] == accepted.work_run.id
    assert outcome["missingEvidence"] == []
    assert [result] = outcome["verificationResults"]
    assert result["id"] == accepted.verification_result.id
    assert result["result"] == "passed"
    assert result["evidenceItemId"] == accepted.evidence_item.id
    assert result["operationId"] == accepted.verification_result.operation_id
    assert result["actorPrincipalId"] == bootstrap.session.principal_id
    assert result["policyBasis"] == "owner_acceptance"
    assert result["targetGraphItemId"] == verification_check.graph_item_id
  end

  test "run state projects complete typed options for each stable command choice", %{conn: conn} do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, first_check} = create_required_verification_check(bootstrap.session)
    {:ok, second_check} = create_required_verification_check(bootstrap.session)

    {:ok, run_result} =
      OperatorCommandFixtures.create_ready_run(
        bootstrap.session,
        [first_check, second_check],
        %{
          title: "Multi-check option packet",
          objective: "Project complete command options.",
          context_summary: "Two checks prove option identity stays paired.",
          requirements: "Do not join command inputs in the browser.",
          success_criteria: "Every option is complete.",
          autonomy_posture: "human_supervised"
        },
        %{
          source_surface: "operator_option_projection_test",
          reason: "Exercise typed option projection.",
          authority_posture: "human_supervised"
        },
        attach_packet_version?: true
      )

    {:ok, observation_result} =
      record_observation(bootstrap.session, run_result.run, first_check, key: "graphql-options")

    {:ok, candidate} =
      create_evidence_candidate(
        bootstrap.session,
        run_result.run,
        first_check,
        observation_result.observation,
        key: "graphql-options"
      )

    options =
      graphql(
        conn,
        """
        query RunOptions($id: ID!) {
          operatorRunState(id: $id) {
            childSummary {
              requiredChecks observations evidenceCandidates evidenceItems
              verificationResults missingEvidence hasMore
            }
            activity(first: 2) {
              pageInfo { hasNextPage hasPreviousPage startCursor endCursor }
              edges { node { kind stableId title status } }
            }
            commandOptions {
              observation {
                key label runId verificationCheckId sourceGraphItemId
                observationSourceKind observationSourceIdentity freshnessState trustBasis
                defaultOutcomeKey
                outcomes { key label observedStatus normalizedStatus }
              }
              evidenceCandidate {
                key label workRunId verificationCheckId executionObservationId
                sourceKind sourceIdentity freshnessState trustBasis sensitivity
              }
              evidenceAcceptance {
                key label evidenceCandidateId result acceptancePolicyBasis
              }
              waiver {
                key label runId runRequiredCheckId expectedExecutionState
                expectedVerificationState policyBasis
              }
            }
          }
        }
        """,
        %{id: run_result.run.id},
        "operatorRunState"
      )

    child_summary = options["childSummary"]
    assert child_summary["requiredChecks"] == 2
    assert child_summary["observations"] == 1
    assert child_summary["evidenceCandidates"] == 1
    assert child_summary["hasMore"] == false

    first_activity = options["activity"]
    assert length(first_activity["edges"]) == 2
    assert first_activity["pageInfo"]["hasNextPage"] == true
    assert first_activity["pageInfo"]["hasPreviousPage"] == false

    {:ok, inserted_after_cursor} =
      record_observation(bootstrap.session, run_result.run, second_check,
        key: "graphql-options-after-cursor"
      )

    second_activity =
      graphql(
        conn,
        """
        query RunActivity($id: ID!, $after: String) {
          operatorRunState(id: $id) {
            activity(first: 10, after: $after) {
              pageInfo { hasNextPage hasPreviousPage startCursor endCursor }
              edges { node { kind stableId title status } }
            }
          }
        }
        """,
        %{id: run_result.run.id, after: first_activity["pageInfo"]["endCursor"]},
        "operatorRunState"
      )["activity"]

    second_activity_ids = Enum.map(second_activity["edges"], &get_in(&1, ["node", "stableId"]))
    assert observation_result.observation.id in second_activity_ids
    assert candidate.id in second_activity_ids
    assert inserted_after_cursor.observation.id in second_activity_ids
    assert second_activity["pageInfo"]["hasPreviousPage"] == true

    {:ok, _failed_acceptance} =
      accept_candidate(bootstrap.session, candidate,
        key: "graphql-options-failed-activity",
        result: "failed"
      )

    all_activity =
      graphql(
        conn,
        """
        query AllRunActivity($id: ID!) {
          operatorRunState(id: $id) {
            activity(first: 20) { edges { node { kind stableId status } } }
          }
        }
        """,
        %{id: run_result.run.id},
        "operatorRunState"
      )["activity"]

    assert Enum.any?(all_activity["edges"], fn edge ->
             edge["node"]["kind"] == "missing_evidence" and
               edge["node"]["status"] == "failed_check"
           end)

    forged_cursor =
      ["2026-07-12T00:00:00.000000", "required_check", "not-a-uuid"]
      |> Jason.encode!()
      |> Base.url_encode64(padding: false)

    forged_response =
      conn
      |> post(~p"/graphql", %{
        query: """
        query ForgedActivity($id: ID!, $after: String) {
          operatorRunState(id: $id) {
            activity(first: 2, after: $after) { edges { node { stableId } } }
          }
        }
        """,
        variables: %{id: run_result.run.id, after: forged_cursor}
      })
      |> json_response(200)

    assert [%{"message" => "A field has an invalid value."}] = forged_response["errors"]

    options = options["commandOptions"]

    assert Enum.map(options["observation"], & &1["verificationCheckId"]) == [second_check.id]
    assert [observation_option] = options["observation"]
    assert observation_option["sourceGraphItemId"] == second_check.graph_item_id
    assert observation_option["observationSourceKind"] == "human"
    assert observation_option["observationSourceIdentity"] == "operator-console"
    assert observation_option["freshnessState"] == "fresh"
    assert observation_option["trustBasis"] == "owner_attested"
    assert observation_option["defaultOutcomeKey"] == "succeeded"

    assert observation_option["outcomes"] == [
             %{
               "key" => "succeeded",
               "label" => "Succeeded",
               "observedStatus" => "succeeded",
               "normalizedStatus" => "succeeded"
             },
             %{
               "key" => "failed",
               "label" => "Failed",
               "observedStatus" => "failed",
               "normalizedStatus" => "failed"
             }
           ]

    assert [candidate_option] = options["evidenceCandidate"]
    assert candidate_option["verificationCheckId"] == first_check.id
    assert candidate_option["executionObservationId"] == observation_result.observation.id
    assert candidate_option["sourceIdentity"] == observation_result.observation.source_identity
    assert candidate_option["sensitivity"] == "internal"

    assert [%{"evidenceCandidateId" => candidate_id, "result" => "passed"} = accept_option] =
             options["evidenceAcceptance"]

    assert candidate_id == candidate.id
    assert accept_option["acceptancePolicyBasis"] == "owner_acceptance"
    assert Enum.all?(options["waiver"], &(&1["policyBasis"] == "owner_exception"))
  end

  test "run state rejects trim-blank and redaction sentinel command options", %{conn: conn} do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    OfficeGraph.Repo.query!(
      "UPDATE verification_checks SET title = '  [REDACTED]  ' WHERE id = $1",
      [Ecto.UUID.dump!(verification_check.id)]
    )

    state =
      graphql(
        conn,
        """
        query RedactedOptions($id: ID!) {
          operatorRunState(id: $id) {
            commandOptions {
              observation { key label sourceGraphItemId defaultOutcomeKey }
              evidenceCandidate { key label sourceIdentity }
              evidenceAcceptance { key label evidenceCandidateId }
              waiver { key label runRequiredCheckId policyBasis }
            }
          }
        }
        """,
        %{id: run_result.run.id},
        "operatorRunState"
      )

    assert state["commandOptions"]["observation"] == []
    assert state["commandOptions"]["waiver"] == []
  end

  @tag timeout: 120_000
  test "eligible command choices after the compact twenty-item summary remain reachable", %{
    conn: conn
  } do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    checks =
      Enum.map(1..25, fn _index ->
        {:ok, check} = create_required_verification_check(bootstrap.session)
        check
      end)

    {:ok, run_result} =
      OperatorCommandFixtures.create_ready_run(
        bootstrap.session,
        checks,
        %{
          title: "Paged command choices",
          objective: "Reach every valid command choice.",
          context_summary: "Twenty-five checks require bounded choice paging.",
          requirements: "No valid choice may be hidden.",
          success_criteria: "The final choice is reachable.",
          autonomy_posture: "human_supervised"
        },
        %{
          source_surface: "operator_option_pagination_test",
          reason: "Exercise command option keysets.",
          authority_posture: "human_supervised"
        },
        attach_packet_version?: true
      )

    query = """
    query PagedOptions($id: ID!, $first: Int!, $after: String) {
      state: operatorRunState(id: $id) {
        commandOptionsOverflow
        commandOptionSummary { observation evidenceCandidate evidenceAcceptance waiver }
        commandAffordances {
          identity
          inputDefaults { field value values }
          targetIds { type id }
        }
      }
      optionPage: operatorRunCommandOptionPage(
        id: $id, kind: "observation", first: $first, after: $after
      ) {
        edges { cursor node { key observation { key verificationCheckId } } }
        pageInfo { hasNextPage hasPreviousPage endCursor }
      }
    }
    """

    first_response =
      conn
      |> post(~p"/graphql", %{
        query: query,
        variables: %{id: run_result.run.id, first: 20}
      })
      |> json_response(200)

    assert first_response["errors"] in [nil, []]
    first = first_response["data"]
    assert first["state"]["commandOptionsOverflow"] == true
    assert first["state"]["commandOptionSummary"]["observation"] == 25
    assert length(first["optionPage"]["edges"]) == 20
    assert first["optionPage"]["pageInfo"]["hasNextPage"] == true

    second =
      conn
      |> post(~p"/graphql", %{
        query: query,
        variables: %{
          id: run_result.run.id,
          first: 20,
          after: first["optionPage"]["pageInfo"]["endCursor"]
        }
      })
      |> json_response(200)
      |> then(fn response ->
        assert response["errors"] in [nil, []]
        response["data"]
      end)

    assert length(second["optionPage"]["edges"]) == 5
    assert second["optionPage"]["pageInfo"]["hasNextPage"] == false

    assert List.last(second["optionPage"]["edges"])["node"]["observation"]["verificationCheckId"] ==
             List.last(checks).id

    assert second["optionPage"]["pageInfo"]["hasPreviousPage"] == true

    checks
    |> Enum.take(24)
    |> Enum.each(fn check ->
      OfficeGraph.Repo.query!(
        "UPDATE verification_checks SET title = '  [REDACTED]  ' WHERE id = $1",
        [Ecto.UUID.dump!(check.id)]
      )
    end)

    compact_invalid =
      graphql(
        conn,
        """
        query CompactInvalidOptions($id: ID!) {
          operatorRunState(id: $id) {
            allowedNextActions
            commandOptions { observation { key } }
            commandOptionSummary { observation }
            commandAffordances {
              identity
              inputDefaults { field value values }
              targetIds { type id }
            }
          }
        }
        """,
        %{id: run_result.run.id},
        "operatorRunState"
      )

    assert compact_invalid["commandOptions"]["observation"] == []
    assert compact_invalid["commandOptionSummary"]["observation"] == 1
    assert "record_execution_observation" in compact_invalid["allowedNextActions"]

    record_observation_affordance =
      Enum.find(
        compact_invalid["commandAffordances"],
        &(&1["identity"] == "record_execution_observation")
      )

    assert record_observation_affordance["inputDefaults"] == [
             %{"field" => "run_id", "value" => run_result.run.id, "values" => []}
           ]

    assert record_observation_affordance["targetIds"] == [
             %{"type" => "work_run", "id" => run_result.run.id},
             %{"type" => "verification_check", "id" => List.last(checks).id}
           ]

    only_valid =
      graphql(
        conn,
        """
        query OnlyValidOption($id: ID!) {
          operatorRunCommandOptionPage(id: $id, kind: "observation", first: 20) {
            edges { node { observation { verificationCheckId } } }
          }
        }
        """,
        %{id: run_result.run.id},
        "operatorRunCommandOptionPage"
      )

    assert [%{"node" => %{"observation" => %{"verificationCheckId" => only_valid_id}}}] =
             only_valid["edges"]

    assert only_valid_id == List.last(checks).id

    valid_waiver =
      graphql(
        conn,
        """
        query OnlyValidWaiver($id: ID!) {
          operatorRunCommandOptionPage(id: $id, kind: "waiver", first: 20) {
            edges { node { waiver { runRequiredCheckId } } }
            pageInfo { hasNextPage }
          }
        }
        """,
        %{id: run_result.run.id},
        "operatorRunCommandOptionPage"
      )

    assert [%{"node" => %{"waiver" => %{"runRequiredCheckId" => valid_waiver_id}}}] =
             valid_waiver["edges"]

    assert valid_waiver_id
    assert valid_waiver["pageInfo"]["hasNextPage"] == false

    OfficeGraph.Repo.query!(
      "UPDATE runs SET execution_state = '  [REDACTED]  ' WHERE id = $1",
      [Ecto.UUID.dump!(run_result.run.id)]
    )

    invalid_state_waiver =
      graphql(
        conn,
        """
        query InvalidStateWaiver($id: ID!) {
          operatorRunCommandOptionPage(id: $id, kind: "waiver", first: 20) {
            edges { node { waiver { key } } }
            pageInfo { hasNextPage }
          }
        }
        """,
        %{id: run_result.run.id},
        "operatorRunCommandOptionPage"
      )

    assert invalid_state_waiver["edges"] == []
    assert invalid_state_waiver["pageInfo"]["hasNextPage"] == false

    OfficeGraph.Repo.query!(
      "UPDATE runs SET execution_state = $1 WHERE id = $2",
      [run_result.run.execution_state, Ecto.UUID.dump!(run_result.run.id)]
    )

    checks
    |> Enum.with_index(1)
    |> Enum.each(fn {check, index} ->
      key = "untruncated-outcome-#{index}"
      {:ok, observed} = record_observation(bootstrap.session, run_result.run, check, key: key)

      {:ok, candidate} =
        create_evidence_candidate(
          bootstrap.session,
          run_result.run,
          check,
          observed.observation,
          key: key
        )

      {:ok, _accepted} = accept_candidate(bootstrap.session, candidate, key: key)
    end)

    outcome =
      graphql(
        conn,
        """
        query CompleteOutcome($id: ID!) {
          operatorVerificationOutcome(id: $id) {
            verificationResults { id verificationCheckId result }
            missingEvidence { verificationCheckId reason }
          }
        }
        """,
        %{id: run_result.run.id},
        "operatorVerificationOutcome"
      )

    assert length(outcome["verificationResults"]) == 25
    assert outcome["missingEvidence"] == []
  end

  test "GraphQL exposes packet workspace version history and run-start affordance", %{conn: conn} do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)

    packet_attrs = %{
      title: "Packet workspace version one",
      objective: "Execute the first immutable packet contract.",
      context_summary: "Packet workspace context one.",
      requirements: "Keep version one in history.",
      success_criteria: "The required check passes.",
      autonomy_posture: "human_supervised"
    }

    {:ok, packet_result} =
      OperatorCommandFixtures.create_ready_packet(
        bootstrap.session,
        [verification_check],
        packet_attrs
      )

    version_attrs =
      packet_attrs
      |> Map.merge(%{
        expected_current_version_id: packet_result.version.id,
        title: "Packet workspace version two",
        objective: "Execute the current immutable packet contract.",
        source_graph_item_ids: [verification_check.graph_item_id],
        verification_check_ids: [verification_check.id]
      })

    {:ok, operation} =
      Operations.start_command(
        bootstrap.session,
        :work_packet_version_create,
        "packet-workspace-version",
        Map.put(version_attrs, :packet_id, packet_result.packet.id)
      )

    {:ok, version_result} =
      WorkPackets.create_version(
        bootstrap.session,
        operation,
        packet_result.packet,
        version_attrs
      )

    third_attrs = %{
      version_attrs
      | expected_current_version_id: version_result.version.id,
        title: "Packet workspace version three"
    }

    {:ok, third_operation} =
      Operations.start_command(
        bootstrap.session,
        :work_packet_version_create,
        "packet-workspace-version-three",
        Map.put(third_attrs, :packet_id, packet_result.packet.id)
      )

    {:ok, third_version_result} =
      WorkPackets.create_version(
        bootstrap.session,
        third_operation,
        version_result.packet,
        third_attrs
      )

    relay_packet_id =
      Absinthe.Relay.Node.to_global_id(
        :work_packet,
        packet_result.packet.id,
        OfficeGraphWeb.GraphQL.Schema
      )

    workspace =
      graphql(
        conn,
        """
        query PacketWorkspace($id: ID!, $first: Int!, $after: String) {
          operatorPacketWorkspace(id: $id) {
            sourceWatermark
            ready
            status
            blockerReasons
            allowedNextActions
            packet { id title state currentVersionId operationId }
            currentVersion {
              id
              versionNumber
              lifecycleState
              title
              objective
              contextSummary
              requirements
              successCriteria
              autonomyPosture
              sourceGraphItemIds
              verificationCheckIds
              operationId
              insertedAt
            }
            versionHistory(first: $first, after: $after) {
              pageInfo { hasNextPage hasPreviousPage startCursor endCursor }
              edges {
                node {
                  id
                  versionNumber
                  title
                  sourceGraphItemIds
                  verificationCheckIds
                }
              }
            }
            commandAffordances {
              identity
              state
              safeExplanation
              blockerReasons
              requiredFields
              inputDefaults { field value values }
              targetIds { type id }
            }
          }
        }
        """,
        %{id: relay_packet_id, first: 2},
        "operatorPacketWorkspace"
      )

    assert workspace["sourceWatermark"]
    assert workspace["ready"] == true
    assert workspace["status"] == "ready_for_run"
    assert workspace["blockerReasons"] == []
    assert workspace["allowedNextActions"] == ["create_work_packet_version", "start_work_run"]
    assert workspace["packet"]["currentVersionId"] == third_version_result.version.id
    assert workspace["packet"]["title"] == "Packet workspace version three"
    assert workspace["currentVersion"]["id"] == third_version_result.version.id
    assert workspace["currentVersion"]["versionNumber"] == 3
    assert workspace["currentVersion"]["sourceGraphItemIds"] == [verification_check.graph_item_id]
    assert workspace["currentVersion"]["verificationCheckIds"] == [verification_check.id]

    assert workspace["versionHistory"]["pageInfo"]["hasNextPage"] == true
    assert workspace["versionHistory"]["pageInfo"]["hasPreviousPage"] == false
    first_versions = Enum.map(workspace["versionHistory"]["edges"], & &1["node"])

    assert Enum.map(first_versions, & &1["id"]) == [
             packet_result.version.id,
             version_result.version.id
           ]

    assert Enum.map(first_versions, & &1["title"]) == [
             "Packet workspace version one",
             "Packet workspace version two"
           ]

    second_workspace =
      graphql(
        conn,
        """
        query PacketWorkspacePage($id: ID!, $first: Int!, $after: String) {
          operatorPacketWorkspace(id: $id) {
            versionHistory(first: $first, after: $after) {
              pageInfo { hasNextPage hasPreviousPage startCursor endCursor }
              edges { node { id versionNumber title } }
            }
          }
        }
        """,
        %{
          id: relay_packet_id,
          first: 2,
          after: workspace["versionHistory"]["pageInfo"]["endCursor"]
        },
        "operatorPacketWorkspace"
      )

    assert second_workspace["versionHistory"]["pageInfo"]["hasNextPage"] == false
    assert second_workspace["versionHistory"]["pageInfo"]["hasPreviousPage"] == true

    assert [%{"node" => %{"id" => third_id, "versionNumber" => 3}}] =
             second_workspace["versionHistory"]["edges"]

    assert third_id == third_version_result.version.id

    assert [create_version, start_run] = workspace["commandAffordances"]
    assert create_version["identity"] == "create_work_packet_version"
    assert create_version["state"] == "enabled"
    assert start_run["identity"] == "start_work_run"
    assert start_run["state"] == "enabled"
    assert start_run["blockerReasons"] == []

    assert %{
             "field" => "packet_version_id",
             "value" => third_version_result.version.id,
             "values" => []
           } in start_run["inputDefaults"]

    assert %{"type" => "work_packet_version", "id" => third_version_result.version.id} in start_run[
             "targetIds"
           ]
  end

  test "GraphQL exposes workspace command affordances according to capabilities", %{conn: conn} do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    packet_query =
      "query PacketAffordance { operatorPacketCreateAffordance { identity state } }"

    intake_query =
      "query IntakeAffordance { operatorManualIntakeAffordance { identity state } }"

    assert graphql(conn, packet_query, %{}, "operatorPacketCreateAffordance") == %{
             "identity" => "create_work_packet",
             "state" => "enabled"
           }

    assert graphql(conn, intake_query, %{}, "operatorManualIntakeAffordance") == %{
             "identity" => "submit_manual_intake",
             "state" => "enabled"
           }

    read_only_session = create_session_with_capabilities!(bootstrap, ["skeleton.read"])

    with_local_api_owner_bootstrap(false, fn ->
      restricted_conn = Ash.PlugHelpers.set_actor(conn, read_only_session)

      assert graphql(
               restricted_conn,
               packet_query,
               %{},
               "operatorPacketCreateAffordance"
             )["state"] == "hidden"

      assert graphql(
               restricted_conn,
               intake_query,
               %{},
               "operatorManualIntakeAffordance"
             )["state"] == "hidden"
    end)
  end

  test "GraphQL packet readiness normalizes nullable id lists", %{conn: conn} do
    assert {:ok, _bootstrap} = Foundation.bootstrap_local_owner([])

    readiness =
      graphql(
        conn,
        """
        query Readiness($input: OperatorPacketReadinessInput!) {
          operatorPacketReadiness(input: $input) {
            status
            ready
            blockerReasons
          }
        }
        """,
        %{
          input: %{
            title: "Nullable list packet",
            objective: "Check nullable GraphQL lists.",
            contextSummary: "GraphQL callers may send null for optional ID lists.",
            requirements: "Return readiness blockers.",
            successCriteria: "No resolver crash.",
            autonomyPosture: "human_supervised",
            sourceGraphItemIds: nil,
            verificationCheckIds: nil
          }
        },
        "operatorPacketReadiness"
      )

    assert readiness["status"] == "blocked"
    assert readiness["ready"] == false

    assert readiness["blockerReasons"] == [
             "missing_source_graph_items",
             "missing_verification_checks"
           ]
  end

  test "GraphQL operator workflow Relay connection preserves forbidden errors" do
    with_local_api_owner_bootstrap(false, fn ->
      response =
        build_conn()
        |> post(~p"/graphql", %{
          query: """
          query RelayInbox {
            operatorWorkflowItems(first: 1) {
              edges { node { normalizedEventId } }
            }
          }
          """,
          variables: %{}
        })
        |> json_response(200)

      assert [%{"extensions" => %{"code" => "forbidden"}} | _rest] = response["errors"]
    end)
  end

  test "GraphQL operator workflow reads use a trusted request actor when bootstrap is disabled" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, intake} = submit_manual_intake(bootstrap.session, "graphql-trusted-context")
    event_id = intake.normalized_event.id

    with_local_api_owner_bootstrap(false, fn ->
      response =
        build_conn()
        |> Ash.PlugHelpers.set_actor(bootstrap.session)
        |> graphql(
          """
          query Inbox {
            operatorWorkflowItems(first: 10) {
              edges { node { normalizedEventId } }
            }
          }
          """,
          %{},
          "operatorWorkflowItems"
        )

      assert [%{"node" => %{"normalizedEventId" => ^event_id}}] = response["edges"]
    end)
  end

  test "GraphQL operator workflow command affordances are authorization-aware", %{conn: conn} do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, intake} = submit_manual_intake(bootstrap.session, "graphql-read-only-affordance")
    read_only_session = create_session_with_capabilities!(bootstrap, ["skeleton.read"])
    event_id = intake.normalized_event.id

    with_local_api_owner_bootstrap(false, fn ->
      inbox =
        conn
        |> Ash.PlugHelpers.set_actor(read_only_session)
        |> graphql(
          """
          query Inbox {
            operatorWorkflowItems(first: 10) {
              edges {
                node {
                  normalizedEventId
                  status
                  allowedNextActions
                  commandAffordances {
                    identity
                    state
                    reasonCodes
                    blockerReasons
                    safeExplanation
                    targetIds { type id }
                  }
                }
              }
            }
          }
          """,
          %{},
          "operatorWorkflowItems"
        )

      rows = Enum.map(inbox["edges"], & &1["node"])
      assert row = Enum.find(rows, &(&1["normalizedEventId"] == event_id))
      assert row["status"] == "pending_triage"
      assert row["allowedNextActions"] == []

      assert [
               %{
                 "identity" => "apply_proposed_changes",
                 "state" => "hidden",
                 "reasonCodes" => ["policy_restricted"],
                 "blockerReasons" => ["policy_restricted"],
                 "safeExplanation" => "This command is not available for the current operator.",
                 "targetIds" => []
               }
             ] = row["commandAffordances"]
    end)
  end

  test "local owner bootstrap stays request scoped instead of VM cached" do
    with_local_api_owner_bootstrap(true, fn ->
      assert {:ok, bootstrap} = ApiSupport.bootstrap_local_api_owner()

      updated_name = "Office Graph Owner #{System.unique_integer([:positive])}"
      rename_profile!(bootstrap.profile.id, updated_name)

      assert {:ok, refreshed_bootstrap} = ApiSupport.bootstrap_local_api_owner()
      assert refreshed_bootstrap.profile.id == bootstrap.profile.id
      assert refreshed_bootstrap.profile.display_name == updated_name
    end)
  end

  defp graphql(conn, query, variables, field) do
    response =
      conn
      |> post(~p"/graphql", %{query: query, variables: variables})
      |> json_response(200)

    assert response["errors"] in [nil, []]
    Map.fetch!(response["data"], field)
  end

  defp camelize_keys(map) do
    Map.new(map, fn {key, value} -> {camelize_key(key), value} end)
  end

  defp camelize_key(key) do
    key
    |> Atom.to_string()
    |> Phoenix.Naming.camelize(:lower)
  end

  defp intake_title(id, inserted_at) do
    "Manual intake received #{DateTime.to_iso8601(inserted_at)} · ref #{String.slice(id, -8, 8)}"
  end

  defp submit_manual_intake(session, key, opts \\ []) do
    {:ok, operation} =
      Operations.start_operation(session, :manual_intake_submit,
        idempotency_key: "manual-intake-api:#{key}:#{System.unique_integer([:positive])}"
      )

    Integrations.submit_manual_intake(session, operation, %{
      source_identity: Keyword.get(opts, :source_identity, "manual:#{key}"),
      replay_identity: "paste:#{key}",
      body:
        Keyword.get(
          opts,
          :body,
          "Investigate #{key} through the operator workflow GraphQL API."
        )
    })
  end

  defp apply_changes(session, proposed_changes) do
    {:ok, operation} = Operations.start_operation(session, :proposed_change_apply)
    ProposedChanges.apply_all(session, operation, proposed_changes)
  end

  defp with_local_api_owner_bootstrap(value, fun) do
    original = Application.get_env(:office_graph, :allow_local_api_owner_bootstrap)
    Application.put_env(:office_graph, :allow_local_api_owner_bootstrap, value)

    try do
      fun.()
    after
      Application.put_env(:office_graph, :allow_local_api_owner_bootstrap, original)
    end
  end

  defp rename_profile!(profile_id, display_name) do
    now = DateTime.utc_now()

    OfficeGraph.Repo.query!(
      "UPDATE principal_profiles SET display_name = $1, updated_at = $2 WHERE id = $3",
      [display_name, now, Ecto.UUID.dump!(profile_id)]
    )
  end

  defp create_session_with_capabilities!(bootstrap, capability_keys) do
    SessionCaseHelpers.create_session_with_capabilities!(bootstrap, capability_keys,
      prefix: "operator-api-read-only"
    )
  end

  defp force_intake_inserted_at!(normalized_event_id, inserted_at) do
    OfficeGraph.Repo.query!(
      "UPDATE normalized_intake_events SET inserted_at = $1, updated_at = $1 WHERE id = $2",
      [inserted_at, Ecto.UUID.dump!(normalized_event_id)]
    )
  end

  defp create_required_verification_check(session) do
    {:ok, operation} = Operations.start_operation(session, :proposed_change_apply)

    with {:ok, %{signal: signal}} <-
           WorkGraph.create_signal(session, operation, %{
             title: "Operator GraphQL signal",
             body: "Operator GraphQL signal body."
           }),
         {:ok, %{task: task}} <-
           WorkGraph.create_task(session, operation, signal, %{
             title: "Operator GraphQL task",
             body: "Operator GraphQL task body."
           }),
         {:ok, %{review_finding: review_finding}} <-
           WorkGraph.create_review_finding(session, operation, task, %{
             title: "Operator GraphQL finding",
             body: "Operator GraphQL finding body."
           }),
         {:ok, %{verification_check: verification_check}} <-
           WorkGraph.create_verification_check(session, operation, review_finding, %{
             title: "Operator GraphQL check",
             body: "Operator GraphQL check body."
           }) do
      {:ok, verification_check}
    end
  end

  defp create_ready_run(session, verification_check) do
    OperatorCommandFixtures.create_ready_run(
      session,
      verification_check,
      %{
        title: "Ready operator GraphQL packet",
        objective: "Run selected GraphQL work.",
        context_summary: "Ready GraphQL context.",
        requirements: "Complete selected GraphQL work.",
        success_criteria: "Required GraphQL checks pass.",
        autonomy_posture: "human_supervised"
      },
      %{
        source_surface: "operator_workflow_graphql_test",
        reason: "Execute ready GraphQL packet.",
        authority_posture: "human_supervised"
      },
      attach_packet_version?: true
    )
  end

  defp record_observation(session, run, verification_check, opts) do
    key = Keyword.fetch!(opts, :key)

    OperatorCommandFixtures.record_observation(
      session,
      run,
      verification_check,
      %{
        source_kind: "human",
        source_identity: "manual:#{key}",
        idempotency_key: "observation:#{key}",
        observed_status: "passed",
        normalized_status: "succeeded",
        freshness_state: "fresh",
        trust_basis: "owner_attested",
        rationale: "Human confirmed #{key}."
      },
      idempotency_key: "observation-operation:#{key}"
    )
  end

  defp create_evidence_candidate(session, run, verification_check, observation, opts) do
    key = Keyword.fetch!(opts, :key)

    OperatorCommandFixtures.create_evidence_candidate(
      session,
      run,
      verification_check,
      observation,
      %{
        claim: "Evidence candidate #{key}.",
        source_kind: "human",
        source_identity: "manual:#{key}",
        freshness_state: "fresh",
        trust_basis: "owner_attested",
        sensitivity: "internal"
      },
      idempotency_key: "candidate-operation:#{key}"
    )
  end

  defp accept_candidate(session, candidate, opts) do
    key = Keyword.fetch!(opts, :key)

    {:ok, operation} =
      Operations.start_operation(session, :evidence_accept,
        idempotency_key: "accept-operation:#{key}"
      )

    Verification.accept_evidence_candidate(session, operation, candidate, %{
      title: "Accepted evidence #{key}",
      body: "Accepted evidence body #{key}.",
      result: Keyword.get(opts, :result, "passed"),
      acceptance_policy_basis: "owner_acceptance"
    })
  end
end
