defmodule OfficeGraphWeb.OperatorWorkflowApiTest do
  use OfficeGraphWeb.ConnCase, async: false

  alias OfficeGraph.ApiSupport
  alias OfficeGraph.Foundation
  alias OfficeGraph.Integrations
  alias OfficeGraph.Operations
  alias OfficeGraph.ProposedChanges
  alias OfficeGraph.Runs
  alias OfficeGraph.Verification
  alias OfficeGraph.WorkGraph
  alias OfficeGraph.WorkPackets

  @inbox_query """
  query Inbox($limit: Int, $afterCursor: String) {
    operatorInbox(limit: $limit, afterCursor: $afterCursor) {
      empty
      hasMore
      limit
      nextCursor
      afterCursor
      sourceWatermark
      rows {
        normalizedEventId
        status
        allowedNextActions
        blockerReasons
        source { identity replayIdentity outcome }
        proposedChangeStatus { pending applied rejected total }
      }
    }
  }
  """

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
          status
          allowedNextActions
        }
      }
    }
  }
  """

  test "GraphQL exposes operator inbox and item detail", %{conn: conn} do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, intake} = submit_manual_intake(bootstrap.session, "graphql-inbox")
    {:ok, _newer_intake} = submit_manual_intake(bootstrap.session, "graphql-inbox-newer")

    inbox = graphql(conn, @inbox_query, %{limit: 1}, "operatorInbox")

    assert inbox["empty"] == false
    assert inbox["hasMore"] == true
    assert inbox["limit"] == 1
    assert is_binary(inbox["nextCursor"])
    assert inbox["afterCursor"] == nil

    next_inbox =
      graphql(conn, @inbox_query, %{limit: 1, afterCursor: inbox["nextCursor"]}, "operatorInbox")

    assert next_inbox["empty"] == false
    assert next_inbox["hasMore"] == false
    assert next_inbox["limit"] == 1
    assert next_inbox["nextCursor"] == nil
    assert next_inbox["afterCursor"] == inbox["nextCursor"]
    assert [row] = next_inbox["rows"]
    assert row["normalizedEventId"] == intake.normalized_event.id
    assert row["status"] == "pending_triage"
    assert row["allowedNextActions"] == ["apply_proposed_changes"]
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
    assert item["allowedNextActions"] == ["prepare_packet"]
    assert item["blockerReasons"] == []

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

    assert Enum.map(item["graphRelationships"], & &1["relationshipType"]) == [
             "produced_task",
             "has_review_finding",
             "requires_verification"
           ]

    assert item["auditTrace"]["resourceCount"] == 4
    assert item["revisionTrace"]["resourceCount"] == 4
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
            allowedNextActions
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
    assert readiness["allowedNextActions"] == ["create_work_packet"]

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
            allowedNextActions
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
    assert run_state["allowedNextActions"] == ["accept_evidence"]
    assert run_state["run"]["id"] == run_result.run.id
    assert hd(run_state["missingEvidence"])["reason"] == "missing_accepted_evidence"
    assert hd(run_state["evidenceCandidates"])["id"] == candidate.id

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
            operatorInbox {
              rows { normalizedEventId }
            }
          }
          """,
          %{},
          "operatorInbox"
        )

      assert [%{"normalizedEventId" => ^event_id}] = response["rows"]
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

  defp submit_manual_intake(session, key) do
    {:ok, operation} =
      Operations.start_operation(session, :manual_intake_submit,
        idempotency_key: "manual-intake-api:#{key}:#{System.unique_integer([:positive])}"
      )

    Integrations.submit_manual_intake(session, operation, %{
      source_identity: "manual:#{key}",
      replay_identity: "paste:#{key}",
      body: "Investigate #{key} through the operator workflow GraphQL API."
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
    {:ok, packet_operation} = Operations.start_operation(session, :work_packet_create)

    {:ok, packet_result} =
      WorkPackets.create_packet(session, packet_operation, %{
        title: "Ready operator GraphQL packet",
        objective: "Run selected GraphQL work.",
        context_summary: "Ready GraphQL context.",
        requirements: "Complete selected GraphQL work.",
        success_criteria: "Required GraphQL checks pass.",
        autonomy_posture: "human_supervised",
        source_graph_item_ids: [verification_check.graph_item_id],
        verification_check_ids: [verification_check.id]
      })

    {:ok, run_operation} = Operations.start_operation(session, :work_run_start)

    with {:ok, run_result} <-
           Runs.start_run(session, run_operation, packet_result.version, %{
             source_surface: "operator_workflow_graphql_test",
             reason: "Execute ready GraphQL packet.",
             authority_posture: "human_supervised"
           }) do
      {:ok, Map.put(run_result, :packet_version, packet_result.version)}
    end
  end

  defp record_observation(session, run, verification_check, opts) do
    key = Keyword.fetch!(opts, :key)

    {:ok, operation} =
      Operations.start_operation(session, :execution_observation_record,
        idempotency_key: "observation-operation:#{key}"
      )

    Runs.record_observation(session, operation, run, %{
      source_kind: "human",
      source_identity: "manual:#{key}",
      idempotency_key: "observation:#{key}",
      observed_status: "passed",
      normalized_status: "succeeded",
      freshness_state: "fresh",
      trust_basis: "owner_attested",
      verification_check_id: verification_check.id,
      graph_item_id: verification_check.graph_item_id,
      rationale: "Human confirmed #{key}."
    })
  end

  defp create_evidence_candidate(session, run, verification_check, observation, opts) do
    key = Keyword.fetch!(opts, :key)

    {:ok, operation} =
      Operations.start_operation(session, :evidence_candidate_create,
        idempotency_key: "candidate-operation:#{key}"
      )

    Verification.create_evidence_candidate(session, operation, %{
      work_run_id: run.id,
      verification_check_id: verification_check.id,
      execution_observation_id: observation.id,
      claim: "Evidence candidate #{key}.",
      source_kind: "human",
      source_identity: "manual:#{key}",
      freshness_state: "fresh",
      trust_basis: "owner_attested",
      sensitivity: "internal"
    })
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
