defmodule OfficeGraphWeb.PacketRunVerificationApiTest do
  use OfficeGraphWeb.ConnCase, async: false

  alias OfficeGraph.Foundation
  alias OfficeGraph.Operations
  alias OfficeGraph.WorkGraph

  test "GraphQL executes the packet-run-verification command", %{conn: conn} do
    {:ok, verification_check} = create_required_verification_check("graphql")

    summary =
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
            verificationResults {
              id
              result
              evidenceItemId
              operationId
              workRunId
              workPacketVersionId
              actorPrincipalId
              policyBasis
              targetGraphItemId
            }
            missingEvidence { verificationCheckId reason }
          }
        }
        """,
        %{input: graphql_attrs("graphql", verification_check)}
      )

    assert_summary_verified(summary, verification_check.id)
    assert_summary_result_audit_fields(summary, verification_check.graph_item_id)
  end

  test "GraphQL reports idempotency conflicts with stable extensions", %{conn: conn} do
    {:ok, first_check} = create_required_verification_check("graphql-conflicting-flow")

    {:ok, second_check} =
      create_required_verification_check("graphql-conflicting-flow-other")

    input = graphql_attrs("graphql-conflicting-flow", first_check)

    _first =
      graphql(
        conn,
        """
        mutation Execute($input: ExecutePacketRunVerificationInput!) {
          executePacketRunVerification(input: $input) {
            run { id }
          }
        }
        """,
        %{input: input}
      )

    conflict =
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
            input
            |> Map.put(:verificationCheckId, second_check.id)
            |> Map.put(:sourceGraphItemId, second_check.graph_item_id)
        }
      )

    assert [%{"extensions" => extensions}] = conflict["errors"]
    assert extensions["code"] == "idempotency_conflict"
    assert extensions["flow_identity"] == input.flowIdentity
  end

  test "GraphQL reports validation errors without creating durable flow writes", %{conn: conn} do
    {:ok, verification_check} = create_required_verification_check("graphql-invalid-ref")

    response =
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
            graphql_attrs("graphql-invalid-ref", verification_check)
            |> Map.put(:sourceGraphItemId, Ecto.UUID.generate())
        }
      )

    assert [%{"extensions" => %{"code" => "validation_failed"}}] = response["errors"]
  end

  defp assert_summary_verified(summary, verification_check_id) do
    assert summary["packet"]["state"] == "ready"
    assert summary["packetVersion"]["lifecycleState"] == "ready"
    assert summary["run"]["aggregateState"] == "verified"
    assert summary["run"]["executionState"] == "completed"
    assert summary["run"]["verificationState"] == "verified"

    assert [%{"verificationCheckId" => ^verification_check_id, "state" => "satisfied"}] =
             summary["requiredChecks"]

    assert [%{"normalizedStatus" => "succeeded"}] = summary["observations"]
    assert [%{"state" => "accepted"}] = summary["evidenceItems"]
    assert [%{"result" => "passed"}] = summary["verificationResults"]
    assert summary["missingEvidence"] == []
  end

  defp assert_summary_result_audit_fields(summary, target_graph_item_id) do
    assert [verification_result] = summary["verificationResults"]
    assert is_binary(verification_result["evidenceItemId"])
    assert is_binary(verification_result["operationId"])
    assert is_binary(verification_result["actorPrincipalId"])
    assert verification_result["policyBasis"] == "owner_acceptance"
    assert verification_result["targetGraphItemId"] == target_graph_item_id
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

  defp graphql_attrs(label, verification_check) do
    %{
      flowIdentity: "packet-run-#{label}-#{System.unique_integer([:positive])}",
      verificationCheckId: verification_check.id,
      sourceGraphItemId: verification_check.graph_item_id,
      packetTitle: "Verify #{label} launch readiness",
      objective: "Confirm #{label} launch checklist has passing evidence.",
      contextSummary: "#{label} launch work collected from the current graph.",
      requirements: "Review #{label} launch blockers.",
      successCriteria: "The required verification check has accepted evidence.",
      autonomyPosture: "human_supervised",
      sourceSurface: "packet_run_verification_graphql_test",
      reason: "Execute #{label} packet.",
      authorityPosture: "human_supervised",
      observationSourceKind: "human",
      observationSourceIdentity: "manual:#{label}",
      observationIdempotencyKey: "observation:#{label}",
      observedStatus: "passed",
      normalizedStatus: "succeeded",
      freshnessState: "fresh",
      trustBasis: "owner_attested",
      observationRationale: "Human confirmed #{label} passed.",
      evidenceClaim: "#{label} launch checklist passed.",
      evidenceTitle: "#{label} launch check passed",
      evidenceBody: "The #{label} launch checklist passed.",
      evidenceResult: "passed",
      acceptancePolicyBasis: "owner_acceptance"
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
