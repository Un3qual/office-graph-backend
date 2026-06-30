defmodule OfficeGraphWeb.OperatorWorkflowApiTest do
  use OfficeGraphWeb.ConnCase, async: false

  alias OfficeGraph.Foundation
  alias OfficeGraph.Operations
  alias OfficeGraph.Runs
  alias OfficeGraph.Verification
  alias OfficeGraph.WorkGraph
  alias OfficeGraph.WorkPackets

  test "JSON API exposes the complete operator workflow from intake to verified run", %{
    conn: conn
  } do
    intake =
      conn
      |> post(~p"/api/manual-intake", %{
        source_identity: "manual:api-e2e",
        replay_identity: "paste:api-e2e",
        body: "Investigate API e2e state and prove it with accepted evidence."
      })
      |> json_response(200)

    inbox =
      conn
      |> get(~p"/api/operator-workflow/inbox")
      |> json_response(200)

    assert hd(inbox["rows"])["status"] == "pending_triage"

    ids = Enum.map(intake["proposed_changes"], & &1["id"])

    _applied =
      conn
      |> post(~p"/api/proposed-changes/apply", %{ids: ids})
      |> json_response(200)

    event_id = intake["normalized_event"]["id"]

    item =
      conn
      |> get(~p"/api/operator-workflow/items/#{event_id}")
      |> json_response(200)

    assert item["status"] == "ready_for_packet"
    verification_link = Enum.find(item["graph_links"], &(&1["type"] == "verification_check"))

    readiness =
      conn
      |> post(~p"/api/operator-workflow/packet-readiness", %{
        title: "Verify API e2e workflow",
        objective: "Resolve the API e2e verification check.",
        context_summary: "Manual intake has been triaged into graph work.",
        requirements: "Use the linked verification check as the required check.",
        success_criteria: "The required check has accepted passing evidence.",
        autonomy_posture: "human_supervised",
        source_graph_item_ids: [verification_link["graph_item_id"]],
        verification_check_ids: [verification_link["id"]]
      })
      |> json_response(200)

    assert readiness["status"] == "packet_ready"

    summary =
      conn
      |> post(
        ~p"/api/packet-run-verification/execute",
        flow_attrs("api-e2e", verification_link["id"], verification_link["graph_item_id"])
      )
      |> json_response(200)

    assert summary["run"]["verification_state"] == "verified"

    run_state =
      conn
      |> get(~p"/api/operator-workflow/runs/#{summary["run"]["id"]}")
      |> json_response(200)

    assert run_state["status"] == "verified"
    assert run_state["allowed_next_actions"] == []
    assert run_state["missing_evidence"] == []

    assert %{
             "result" => "passed",
             "evidence_item_id" => evidence_item_id,
             "operation_id" => operation_id,
             "actor_principal_id" => actor_principal_id,
             "policy_basis" => "owner_acceptance",
             "target_graph_item_id" => target_graph_item_id
           } = hd(run_state["verification_results"])

    assert is_binary(evidence_item_id)
    assert is_binary(operation_id)
    assert is_binary(actor_principal_id)
    assert target_graph_item_id == verification_link["graph_item_id"]

    run_id = summary["run"]["id"]

    completed_json_item =
      conn
      |> get(~p"/api/operator-workflow/items/#{event_id}")
      |> json_response(200)

    completed_graphql_item =
      graphql(
        conn,
        """
        query Item($id: ID!) {
          operatorWorkflowItem(id: $id) {
            status
            allowedNextActions
            graphLinks { type id state }
          }
        }
        """,
        %{id: event_id}
      )

    assert completed_json_item["status"] == "verified"
    assert completed_graphql_item["status"] == "verified"
    assert completed_json_item["allowed_next_actions"] == []
    assert completed_graphql_item["allowedNextActions"] == []

    assert %{"id" => ^run_id, "state" => "verified"} =
             Enum.find(completed_json_item["graph_links"], &(&1["type"] == "work_run"))

    assert %{"id" => ^run_id, "state" => "verified"} =
             Enum.find(completed_graphql_item["graphLinks"], &(&1["type"] == "work_run"))

    completed_json_inbox =
      conn
      |> get(~p"/api/operator-workflow/inbox")
      |> json_response(200)

    completed_graphql_inbox =
      graphql(
        conn,
        """
        query Inbox {
          operatorInbox {
            rows {
              normalizedEventId
              status
              allowedNextActions
            }
          }
        }
        """,
        %{}
      )

    assert completed_json_row =
             Enum.find(completed_json_inbox["rows"], &(&1["normalized_event_id"] == event_id))

    assert completed_graphql_row =
             Enum.find(completed_graphql_inbox["rows"], &(&1["normalizedEventId"] == event_id))

    assert completed_json_row["status"] == "verified"
    assert completed_graphql_row["status"] == "verified"
    assert completed_json_row["allowed_next_actions"] == []
    assert completed_graphql_row["allowedNextActions"] == []

    json_outcome =
      conn
      |> get(~p"/api/operator-workflow/runs/#{summary["run"]["id"]}/verification-outcome")
      |> json_response(200)

    graphql_outcome =
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
        %{id: summary["run"]["id"]}
      )

    assert json_outcome["status"] == graphql_outcome["status"]
    assert json_outcome["run"]["id"] == graphql_outcome["run"]["id"]
    assert [json_result] = json_outcome["verification_results"]
    assert [graphql_result] = graphql_outcome["verificationResults"]
    assert json_result["id"] == graphql_result["id"]
    assert json_result["result"] == graphql_result["result"]
    assert json_result["evidence_item_id"] == graphql_result["evidenceItemId"]
    assert json_result["operation_id"] == graphql_result["operationId"]
    assert json_result["actor_principal_id"] == graphql_result["actorPrincipalId"]
    assert json_result["policy_basis"] == graphql_result["policyBasis"]
    assert json_result["target_graph_item_id"] == graphql_result["targetGraphItemId"]
  end

  test "GraphQL and JSON expose equivalent operator inbox and item detail", %{conn: conn} do
    intake =
      conn
      |> post(~p"/api/manual-intake", %{
        source_identity: "manual:api-inbox",
        replay_identity: "paste:api-inbox",
        body: "Investigate API inbox state and prove it with accepted evidence."
      })
      |> json_response(200)

    json_inbox =
      conn
      |> get(~p"/api/operator-workflow/inbox")
      |> json_response(200)

    graphql_inbox =
      graphql(
        conn,
        """
        query Inbox {
          operatorInbox {
            empty
            sourceWatermark
            rows {
              status
              allowedNextActions
              blockerReasons
              operationWatermark
              auditTrace { resourceCount resources { type id } }
              revisionTrace { resourceCount resources { type id } }
              source { identity replayIdentity outcome }
              proposedChangeStatus { pending applied rejected total }
            }
          }
        }
        """,
        %{}
      )

    assert json_inbox["empty"] == false
    assert graphql_inbox["empty"] == false
    assert [json_row] = json_inbox["rows"]
    assert [graphql_row] = graphql_inbox["rows"]
    assert json_row["status"] == graphql_row["status"]
    assert json_row["allowed_next_actions"] == graphql_row["allowedNextActions"]
    assert json_row["blocker_reasons"] == graphql_row["blockerReasons"]
    assert json_row["operation_watermark"] == graphql_row["operationWatermark"]
    assert json_row["audit_trace"]["resource_count"] == 0
    assert json_row["audit_trace"]["resources"] == []
    assert graphql_row["auditTrace"]["resourceCount"] == 0
    assert graphql_row["auditTrace"]["resources"] == []
    assert json_row["revision_trace"]["resource_count"] == 0
    assert json_row["revision_trace"]["resources"] == []
    assert graphql_row["revisionTrace"]["resourceCount"] == 0
    assert graphql_row["revisionTrace"]["resources"] == []
    assert json_row["source"]["identity"] == graphql_row["source"]["identity"]
    assert json_row["proposed_change_status"]["pending"] == 4
    assert graphql_row["proposedChangeStatus"]["pending"] == 4

    ids = Enum.map(intake["proposed_changes"], & &1["id"])

    _applied =
      conn
      |> post(~p"/api/proposed-changes/apply", %{ids: ids})
      |> json_response(200)

    event_id = intake["normalized_event"]["id"]

    json_item =
      conn
      |> get(~p"/api/operator-workflow/items/#{event_id}")
      |> json_response(200)

    graphql_item =
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
        %{id: event_id}
      )

    assert json_item["status"] == "ready_for_packet"
    assert graphql_item["status"] == "ready_for_packet"
    assert json_item["allowed_next_actions"] == graphql_item["allowedNextActions"]

    assert Enum.map(json_item["graph_links"], & &1["type"]) ==
             Enum.map(graphql_item["graphLinks"], & &1["type"])

    assert Enum.map(json_item["graph_relationships"], & &1["relationship_type"]) ==
             Enum.map(graphql_item["graphRelationships"], & &1["relationshipType"])

    assert json_item["audit_trace"]["resource_count"] ==
             graphql_item["auditTrace"]["resourceCount"]

    assert json_item["revision_trace"]["resource_count"] ==
             graphql_item["revisionTrace"]["resourceCount"]
  end

  test "GraphQL and JSON expose equivalent packet readiness and run state", %{conn: conn} do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    readiness_input = %{
      title: "Ready API packet",
      objective: "Resolve the selected verification check.",
      context_summary: "A triaged item is ready for API execution.",
      requirements: "Use the linked graph item.",
      success_criteria: "Accepted passing evidence exists.",
      autonomy_posture: "human_supervised",
      source_graph_item_ids: [verification_check.graph_item_id],
      verification_check_ids: [verification_check.id]
    }

    json_readiness =
      conn
      |> post(~p"/api/operator-workflow/packet-readiness", readiness_input)
      |> json_response(200)

    graphql_readiness =
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
        %{input: camelize_keys(readiness_input)}
      )

    assert json_readiness["status"] == graphql_readiness["status"]
    assert json_readiness["ready"] == graphql_readiness["ready"]
    assert json_readiness["allowed_next_actions"] == graphql_readiness["allowedNextActions"]
    assert json_readiness["blocker_reasons"] == graphql_readiness["blockerReasons"]

    assert hd(json_readiness["required_checks"])["id"] ==
             hd(graphql_readiness["requiredChecks"])["id"]

    {:ok, observation_result} =
      record_observation(bootstrap.session, run_result.run, verification_check,
        key: "operator-api-run"
      )

    {:ok, _candidate} =
      create_evidence_candidate(
        bootstrap.session,
        run_result.run,
        verification_check,
        observation_result.observation,
        key: "operator-api-run"
      )

    json_run_state =
      conn
      |> get(~p"/api/operator-workflow/runs/#{run_result.run.id}")
      |> json_response(200)

    graphql_run_state =
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
        %{id: run_result.run.id}
      )

    assert json_run_state["status"] == "awaiting_evidence_acceptance"
    assert graphql_run_state["status"] == "awaiting_evidence_acceptance"
    assert json_run_state["allowed_next_actions"] == graphql_run_state["allowedNextActions"]
    assert json_run_state["run"]["id"] == graphql_run_state["run"]["id"]

    assert hd(json_run_state["missing_evidence"])["reason"] ==
             hd(graphql_run_state["missingEvidence"])["reason"]

    assert hd(json_run_state["evidence_candidates"])["id"] ==
             hd(graphql_run_state["evidenceCandidates"])["id"]

    assert hd(json_run_state["evidence_candidates"])["execution_observation_id"] ==
             hd(graphql_run_state["evidenceCandidates"])["executionObservationId"]
  end

  test "GraphQL operator run state permits evidence candidates without observations", %{
    conn: conn
  } do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    {:ok, candidate} =
      create_evidence_candidate(
        bootstrap.session,
        run_result.run,
        verification_check,
        nil,
        key: "operator-api-manual-candidate"
      )

    json_run_state =
      conn
      |> get(~p"/api/operator-workflow/runs/#{run_result.run.id}")
      |> json_response(200)

    candidate_id = candidate.id

    graphql_run_state =
      graphql(
        conn,
        """
        query RunState($id: ID!) {
          operatorRunState(id: $id) {
            evidenceCandidates { id executionObservationId }
          }
        }
        """,
        %{id: run_result.run.id}
      )

    assert [%{"id" => ^candidate_id, "execution_observation_id" => nil}] =
             json_run_state["evidence_candidates"]

    assert [%{"id" => ^candidate_id, "executionObservationId" => nil}] =
             graphql_run_state["evidenceCandidates"]
  end

  test "JSON operator workflow endpoints reject client-supplied session context maps", %{
    conn: conn
  } do
    response =
      conn
      |> get(~p"/api/operator-workflow/inbox", %{
        "session_context" => %{
          "organization_id" => Ecto.UUID.generate(),
          "workspace_id" => Ecto.UUID.generate()
        }
      })
      |> json_response(422)

    assert response["error"]["code"] == "validation_failed"
    assert response["error"]["field"] == "session_context"
  end

  test "JSON operator workflow mutations reject client-supplied session context maps", %{
    conn: conn
  } do
    response =
      conn
      |> post(~p"/api/operator-workflow/packet-readiness", %{
        "title" => "Malformed session packet",
        "objective" => "Reject forged session context.",
        "context_summary" => "Malformed client params.",
        "requirements" => "Do not trust client session maps.",
        "success_criteria" => "Request is rejected before projection.",
        "autonomy_posture" => "human_supervised",
        "source_graph_item_ids" => [],
        "verification_check_ids" => [],
        "session_context" => %{
          "organization_id" => Ecto.UUID.generate(),
          "workspace_id" => Ecto.UUID.generate()
        }
      })
      |> json_response(422)

    assert response["error"]["code"] == "validation_failed"
    assert response["error"]["field"] == "session_context"
  end

  defp graphql(conn, query, variables) do
    response = raw_graphql(conn, query, variables)

    assert response["errors"] in [nil, []]
    response["data"] |> Map.values() |> hd()
  end

  defp raw_graphql(conn, query, variables) do
    conn
    |> post(~p"/graphql", %{query: query, variables: variables})
    |> json_response(200)
  end

  defp camelize_keys(map) do
    Map.new(map, fn {key, value} -> {camelize_key(key), value} end)
  end

  defp camelize_key(key) do
    key
    |> Atom.to_string()
    |> Phoenix.Naming.camelize(:lower)
  end

  defp flow_attrs(label, verification_check_id, source_graph_item_id) do
    %{
      flow_identity: "operator-workflow-#{label}-#{System.unique_integer([:positive])}",
      verification_check_id: verification_check_id,
      source_graph_item_id: source_graph_item_id,
      packet_title: "Verify #{label} readiness",
      objective: "Confirm #{label} work has passing evidence.",
      context_summary: "#{label} work came from the operator workflow.",
      requirements: "Review #{label} blockers and record evidence.",
      success_criteria: "The required verification check has accepted evidence.",
      autonomy_posture: "human_supervised",
      source_surface: "operator_workflow_api",
      reason: "Execute #{label} operator workflow.",
      authority_posture: "human_supervised",
      observation_source_kind: "human",
      observation_source_identity: "manual:#{label}",
      observation_idempotency_key: "observation:#{label}",
      observed_status: "passed",
      normalized_status: "succeeded",
      freshness_state: "fresh",
      trust_basis: "owner_attested",
      observation_rationale: "Human confirmed #{label}.",
      evidence_claim: "#{label} passed.",
      evidence_title: "#{label} evidence",
      evidence_body: "#{label} evidence body.",
      evidence_result: "passed",
      acceptance_policy_basis: "owner_acceptance"
    }
  end

  defp create_required_verification_check(session) do
    {:ok, operation} = Operations.start_operation(session, :proposed_change_apply)

    with {:ok, %{signal: signal}} <-
           WorkGraph.create_signal(session, operation, %{
             title: "Operator API signal",
             body: "Operator API signal body."
           }),
         {:ok, %{task: task}} <-
           WorkGraph.create_task(session, operation, signal, %{
             title: "Operator API task",
             body: "Operator API task body."
           }),
         {:ok, %{review_finding: review_finding}} <-
           WorkGraph.create_review_finding(session, operation, task, %{
             title: "Operator API finding",
             body: "Operator API finding body."
           }),
         {:ok, %{verification_check: verification_check}} <-
           WorkGraph.create_verification_check(session, operation, review_finding, %{
             title: "Operator API check",
             body: "Operator API check body."
           }) do
      {:ok, verification_check}
    end
  end

  defp create_ready_run(session, verification_check) do
    {:ok, packet_operation} = Operations.start_operation(session, :work_packet_create)

    {:ok, packet_result} =
      WorkPackets.create_packet(session, packet_operation, %{
        title: "Ready operator API packet",
        objective: "Run selected API work.",
        context_summary: "Ready API context.",
        requirements: "Complete selected API work.",
        success_criteria: "Required API checks pass.",
        autonomy_posture: "human_supervised",
        source_graph_item_ids: [verification_check.graph_item_id],
        verification_check_ids: [verification_check.id]
      })

    {:ok, run_operation} = Operations.start_operation(session, :work_run_start)

    with {:ok, run_result} <-
           Runs.start_run(session, run_operation, packet_result.version, %{
             source_surface: "test",
             reason: "Execute ready API packet.",
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
      execution_observation_id: observation && observation.id,
      claim: "Evidence candidate #{key}.",
      source_kind: "human",
      source_identity: "manual:#{key}",
      freshness_state: "fresh",
      trust_basis: "owner_attested",
      sensitivity: "internal"
    })
  end
end
