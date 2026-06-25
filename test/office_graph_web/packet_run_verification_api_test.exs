defmodule OfficeGraphWeb.PacketRunVerificationApiTest do
  use OfficeGraphWeb.ConnCase, async: false

  alias OfficeGraph.Foundation
  alias OfficeGraph.Operations
  alias OfficeGraph.WorkGraph

  test "GraphQL and JSON APIs execute equivalent packet-run-verification flows", %{conn: conn} do
    {:ok, json_check} = create_required_verification_check("json")
    {:ok, graphql_check} = create_required_verification_check("graphql")

    json_summary =
      conn
      |> post(~p"/api/packet-run-verification/execute", flow_attrs("json", json_check))
      |> json_response(200)

    graphql_summary =
      graphql(
        conn,
        """
        mutation Execute($input: ExecutePacketRunVerificationInput!) {
          executePacketRunVerification(input: $input) {
            packet { id title state }
            packetVersion { id versionNumber lifecycleState objective }
            run { id aggregateState executionState verificationState }
            requiredChecks { verificationCheckId state }
            observations { normalizedStatus sourceKind sourceIdentity }
            evidenceItems { id state candidateId workRunId }
            verificationResults { id result workRunId workPacketVersionId }
            missingEvidence { verificationCheckId reason }
          }
        }
        """,
        %{input: graphql_attrs("graphql", graphql_check)}
      )

    assert_summary_verified(json_summary, json_check.id)
    assert_summary_verified(graphql_summary, graphql_check.id)

    assert json_summary["packet"]["state"] == graphql_summary["packet"]["state"]
    assert json_summary["run"]["aggregate_state"] == graphql_summary["run"]["aggregateState"]

    assert json_summary["run"]["verification_state"] ==
             graphql_summary["run"]["verificationState"]

    assert json_summary["missing_evidence"] == []
    assert graphql_summary["missingEvidence"] == []
  end

  test "JSON API replays the same packet-run-verification flow idempotently", %{conn: conn} do
    {:ok, verification_check} = create_required_verification_check("idempotent")
    attrs = flow_attrs("idempotent", verification_check)

    first_summary =
      conn
      |> post(~p"/api/packet-run-verification/execute", attrs)
      |> json_response(200)

    second_summary =
      conn
      |> post(~p"/api/packet-run-verification/execute", attrs)
      |> json_response(200)

    assert second_summary["packet"]["id"] == first_summary["packet"]["id"]
    assert second_summary["packet_version"]["id"] == first_summary["packet_version"]["id"]
    assert second_summary["run"]["id"] == first_summary["run"]["id"]
    assert hd(second_summary["observations"])["id"] == hd(first_summary["observations"])["id"]
    assert hd(second_summary["evidence_items"])["id"] == hd(first_summary["evidence_items"])["id"]

    assert hd(second_summary["verification_results"])["id"] ==
             hd(first_summary["verification_results"])["id"]
  end

  test "APIs reject conflicting packet-run-verification flow replays", %{conn: conn} do
    {:ok, first_check} = create_required_verification_check("json-conflicting-flow")
    {:ok, second_check} = create_required_verification_check("json-conflicting-flow-other")

    attrs = flow_attrs("json-conflicting-flow", first_check)

    first_summary =
      conn
      |> post(~p"/api/packet-run-verification/execute", attrs)
      |> json_response(200)

    conflict =
      conn
      |> post(
        ~p"/api/packet-run-verification/execute",
        attrs
        |> Map.put(:verification_check_id, second_check.id)
        |> Map.put(:source_graph_item_id, second_check.graph_item_id)
      )
      |> json_response(422)

    assert conflict["error"]["code"] == "idempotency_conflict"
    assert conflict["error"]["flow_identity"] == attrs.flow_identity

    replay =
      conn
      |> post(~p"/api/packet-run-verification/execute", attrs)
      |> json_response(200)

    assert replay["run"]["id"] == first_summary["run"]["id"]

    {:ok, graphql_first_check} = create_required_verification_check("graphql-conflicting-flow")

    {:ok, graphql_second_check} =
      create_required_verification_check("graphql-conflicting-flow-other")

    graphql_input = graphql_attrs("graphql-conflicting-flow", graphql_first_check)

    _graphql_first =
      graphql(
        conn,
        """
        mutation Execute($input: ExecutePacketRunVerificationInput!) {
          executePacketRunVerification(input: $input) {
            run { id }
          }
        }
        """,
        %{input: graphql_input}
      )

    graphql_conflict =
      raw_graphql(
        conn,
        """
        mutation Execute($input: ExecutePacketRunVerificationInput!) {
          executePacketRunVerification(input: $input) {
            run { id }
          }
        }
        """,
        %{
          input:
            graphql_input
            |> Map.put(:verificationCheckId, graphql_second_check.id)
            |> Map.put(:sourceGraphItemId, graphql_second_check.graph_item_id)
        }
      )

    assert [%{"extensions" => extensions}] = graphql_conflict["errors"]
    assert extensions["code"] == "idempotency_conflict"
    assert extensions["flow_identity"] == graphql_input.flowIdentity
  end

  test "APIs report missing packet-run-verification checks with stable codes", %{conn: conn} do
    {:ok, json_check} = create_required_verification_check("json-missing-check")
    missing_json_check_id = Ecto.UUID.generate()

    json_response =
      conn
      |> post(
        ~p"/api/packet-run-verification/execute",
        flow_attrs("json-missing-check", json_check)
        |> Map.put(:verification_check_id, missing_json_check_id)
      )
      |> json_response(422)

    assert json_response["error"]["code"] == "missing_verification_check"
    assert json_response["error"]["verification_check_id"] == missing_json_check_id

    {:ok, graphql_check} = create_required_verification_check("graphql-missing-check")
    missing_graphql_check_id = Ecto.UUID.generate()

    graphql_response =
      raw_graphql(
        conn,
        """
        mutation Execute($input: ExecutePacketRunVerificationInput!) {
          executePacketRunVerification(input: $input) {
            run { id }
          }
        }
        """,
        %{
          input:
            graphql_attrs("graphql-missing-check", graphql_check)
            |> Map.put(:verificationCheckId, missing_graphql_check_id)
        }
      )

    assert [%{"extensions" => %{"code" => "missing_verification_check"} = extensions}] =
             graphql_response["errors"]

    assert extensions["verification_check_id"] == missing_graphql_check_id
  end

  test "APIs return structured validation errors for invalid packet references", %{conn: conn} do
    {:ok, json_check} = create_required_verification_check("json-invalid-ref")

    json_response =
      conn
      |> post(
        ~p"/api/packet-run-verification/execute",
        flow_attrs("json-invalid-ref", json_check)
        |> Map.put(:source_graph_item_id, Ecto.UUID.generate())
      )
      |> json_response(422)

    assert json_response["error"]["code"] == "validation_failed"

    {:ok, graphql_check} = create_required_verification_check("graphql-invalid-ref")

    graphql_response =
      raw_graphql(
        conn,
        """
        mutation Execute($input: ExecutePacketRunVerificationInput!) {
          executePacketRunVerification(input: $input) {
            run { id }
          }
        }
        """,
        %{
          input:
            graphql_attrs("graphql-invalid-ref", graphql_check)
            |> Map.put(:sourceGraphItemId, Ecto.UUID.generate())
        }
      )

    assert [%{"extensions" => %{"code" => "validation_failed"}}] = graphql_response["errors"]
  end

  test "JSON API rejects mismatched source and check before durable flow writes", %{conn: conn} do
    {:ok, verification_check} = create_required_verification_check("json-mismatched-source")
    {:ok, other_check} = create_required_verification_check("json-mismatched-source-other")

    attrs =
      flow_attrs("json-mismatched-source", verification_check)
      |> Map.put(:source_graph_item_id, other_check.graph_item_id)

    json_response =
      conn
      |> post(~p"/api/packet-run-verification/execute", attrs)
      |> json_response(422)

    assert json_response["error"]["code"] == "validation_failed"

    corrected_summary =
      conn
      |> post(
        ~p"/api/packet-run-verification/execute",
        Map.put(attrs, :source_graph_item_id, verification_check.graph_item_id)
      )
      |> json_response(200)

    assert_summary_verified(corrected_summary, verification_check.id)
  end

  test "JSON API rejects passed evidence for failed observations", %{conn: conn} do
    {:ok, verification_check} = create_required_verification_check("json-failed-observation")

    json_response =
      conn
      |> post(
        ~p"/api/packet-run-verification/execute",
        flow_attrs("json-failed-observation", verification_check)
        |> Map.put(:observed_status, "failed")
        |> Map.put(:normalized_status, "failed")
        |> Map.put(:evidence_result, "passed")
      )
      |> json_response(422)

    assert json_response["error"]["code"] == "validation_failed"
  end

  test "JSON API rejects not-ready packet input before durable flow writes", %{conn: conn} do
    {:ok, verification_check} = create_required_verification_check("json-invalid-posture")

    attrs =
      flow_attrs("json-invalid-posture", verification_check)
      |> Map.put(:autonomy_posture, "fully_autonomous")

    json_response =
      conn
      |> post(~p"/api/packet-run-verification/execute", attrs)
      |> json_response(422)

    assert json_response["error"]["code"] == "validation_failed"

    corrected_summary =
      conn
      |> post(
        ~p"/api/packet-run-verification/execute",
        Map.put(attrs, :autonomy_posture, "human_supervised")
      )
      |> json_response(200)

    assert_summary_verified(corrected_summary, verification_check.id)
  end

  test "JSON API rejects passed evidence input before durable flow writes", %{conn: conn} do
    cases = [
      {"json-failed-before-write", %{observed_status: "failed", normalized_status: "failed"}},
      {"json-stale-before-write", %{freshness_state: "stale"}},
      {"json-unauthenticated-before-write", %{trust_basis: "unauthenticated"}}
    ]

    for {label, invalid_attrs} <- cases do
      {:ok, verification_check} = create_required_verification_check(label)

      attrs =
        label
        |> flow_attrs(verification_check)
        |> Map.merge(invalid_attrs)

      json_response =
        conn
        |> post(~p"/api/packet-run-verification/execute", attrs)
        |> json_response(422)

      assert json_response["error"]["code"] == "validation_failed"

      corrected_summary =
        conn
        |> post(
          ~p"/api/packet-run-verification/execute",
          attrs
          |> Map.put(:observed_status, "passed")
          |> Map.put(:normalized_status, "succeeded")
          |> Map.put(:freshness_state, "fresh")
          |> Map.put(:trust_basis, "owner_attested")
        )
        |> json_response(200)

      assert_summary_verified(corrected_summary, verification_check.id)
    end
  end

  defp assert_summary_verified(summary, verification_check_id) do
    packet = summary["packet"]
    packet_version = value(summary, "packet_version", "packetVersion")
    run = summary["run"]

    assert packet["state"] == "ready"
    assert value(packet_version, "lifecycle_state", "lifecycleState") == "ready"
    assert value(run, "aggregate_state", "aggregateState") == "verified"
    assert value(run, "execution_state", "executionState") == "completed"
    assert value(run, "verification_state", "verificationState") == "verified"

    assert [required_check] = value(summary, "required_checks", "requiredChecks")

    assert value(required_check, "verification_check_id", "verificationCheckId") ==
             verification_check_id

    assert required_check["state"] == "satisfied"

    assert [observation] = summary["observations"]
    assert value(observation, "normalized_status", "normalizedStatus") == "succeeded"

    assert [evidence_item] = value(summary, "evidence_items", "evidenceItems")
    assert evidence_item["state"] == "accepted"

    assert [verification_result] = value(summary, "verification_results", "verificationResults")
    assert verification_result["result"] == "passed"
  end

  defp value(map, snake_key, camel_key), do: Map.get(map, snake_key) || Map.fetch!(map, camel_key)

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

  defp flow_attrs(label, verification_check) do
    %{
      flow_identity: "packet-run-#{label}-#{System.unique_integer([:positive])}",
      verification_check_id: verification_check.id,
      source_graph_item_id: verification_check.graph_item_id,
      packet_title: "Verify #{label} launch readiness",
      objective: "Confirm #{label} launch checklist has passing evidence.",
      context_summary: "#{label} launch work collected from the current graph.",
      requirements: "Review #{label} launch blockers.",
      success_criteria: "The required verification check has accepted evidence.",
      autonomy_posture: "human_supervised",
      source_surface: "api_test",
      reason: "Execute #{label} packet.",
      authority_posture: "human_supervised",
      observation_source_kind: "human",
      observation_source_identity: "manual:#{label}",
      observation_idempotency_key: "observation:#{label}",
      observed_status: "passed",
      normalized_status: "succeeded",
      freshness_state: "fresh",
      trust_basis: "owner_attested",
      observation_rationale: "Human confirmed #{label} passed.",
      evidence_claim: "#{label} launch checklist passed.",
      evidence_title: "#{label} launch check passed",
      evidence_body: "The #{label} launch checklist passed.",
      evidence_result: "passed",
      acceptance_policy_basis: "owner_acceptance"
    }
  end

  defp graphql_attrs(label, verification_check) do
    attrs = flow_attrs(label, verification_check)

    %{
      flowIdentity: attrs.flow_identity,
      verificationCheckId: attrs.verification_check_id,
      sourceGraphItemId: attrs.source_graph_item_id,
      packetTitle: attrs.packet_title,
      objective: attrs.objective,
      contextSummary: attrs.context_summary,
      requirements: attrs.requirements,
      successCriteria: attrs.success_criteria,
      autonomyPosture: attrs.autonomy_posture,
      sourceSurface: attrs.source_surface,
      reason: attrs.reason,
      authorityPosture: attrs.authority_posture,
      observationSourceKind: attrs.observation_source_kind,
      observationSourceIdentity: attrs.observation_source_identity,
      observationIdempotencyKey: attrs.observation_idempotency_key,
      observedStatus: attrs.observed_status,
      normalizedStatus: attrs.normalized_status,
      freshnessState: attrs.freshness_state,
      trustBasis: attrs.trust_basis,
      observationRationale: attrs.observation_rationale,
      evidenceClaim: attrs.evidence_claim,
      evidenceTitle: attrs.evidence_title,
      evidenceBody: attrs.evidence_body,
      evidenceResult: attrs.evidence_result,
      acceptancePolicyBasis: attrs.acceptance_policy_basis
    }
  end

  defp create_required_verification_check(label) do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, operation} = Operations.start_operation(bootstrap.session, :proposed_change_apply)

    with {:ok, %{signal: signal}} <-
           WorkGraph.create_signal(bootstrap.session, operation, %{
             title: "#{label} launch signal",
             body: "#{label} launch signal body."
           }),
         {:ok, %{task: task}} <-
           WorkGraph.create_task(bootstrap.session, operation, signal, %{
             title: "#{label} launch task",
             body: "#{label} launch task body."
           }),
         {:ok, %{review_finding: review_finding}} <-
           WorkGraph.create_review_finding(bootstrap.session, operation, task, %{
             title: "#{label} launch finding",
             body: "#{label} launch finding body."
           }),
         {:ok, %{verification_check: verification_check}} <-
           WorkGraph.create_verification_check(bootstrap.session, operation, review_finding, %{
             title: "#{label} launch check",
             body: "#{label} launch check body."
           }) do
      {:ok, verification_check}
    end
  end
end
