defmodule OfficeGraph.PacketRunVerificationTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.Foundation
  alias OfficeGraph.Operations
  alias OfficeGraph.PacketRunVerification
  alias OfficeGraph.WorkGraph

  test "domain command executes and replays a packet-run-verification flow" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session, "domain")
    attrs = flow_attrs("domain", verification_check)

    assert {:ok, first_summary} = PacketRunVerification.execute(bootstrap.session, attrs)
    assert_summary_verified(first_summary, verification_check.id)

    assert {:ok, replay_summary} = PacketRunVerification.execute(bootstrap.session, attrs)

    assert replay_summary.packet.id == first_summary.packet.id
    assert replay_summary.packet_version.id == first_summary.packet_version.id
    assert replay_summary.run.id == first_summary.run.id
    assert hd(replay_summary.observations).id == hd(first_summary.observations).id
    assert hd(replay_summary.evidence_items).id == hd(first_summary.evidence_items).id
    assert hd(replay_summary.verification_results).id == hd(first_summary.verification_results).id
  end

  test "domain command rejects mismatched source and check before durable flow writes" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session, "mismatch")
    {:ok, other_check} = create_required_verification_check(bootstrap.session, "mismatch-other")

    attrs =
      "mismatch"
      |> flow_attrs(verification_check)
      |> Map.put(:source_graph_item_id, other_check.graph_item_id)

    assert {:error,
            {:source_graph_item_check_mismatch, source_graph_item_id, verification_check_id,
             expected_graph_item_id}} =
             PacketRunVerification.execute(bootstrap.session, attrs)

    assert source_graph_item_id == other_check.graph_item_id
    assert verification_check_id == verification_check.id
    assert expected_graph_item_id == verification_check.graph_item_id

    assert {:ok, summary} =
             PacketRunVerification.execute(bootstrap.session, %{
               attrs
               | source_graph_item_id: verification_check.graph_item_id
             })

    assert_summary_verified(summary, verification_check.id)
  end

  test "domain command rejects missing context and requirements before durable flow writes" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session, "readiness")

    for field <- [:context_summary, :requirements] do
      attrs =
        "readiness-#{field}"
        |> flow_attrs(verification_check)
        |> Map.put(field, " ")

      assert {:error, {:invalid_packet_run_input, :packet_readiness}} =
               PacketRunVerification.execute(bootstrap.session, attrs)
    end
  end

  defp assert_summary_verified(summary, verification_check_id) do
    assert summary.packet.state == "ready"
    assert summary.packet_version.lifecycle_state == "ready"
    assert summary.run.aggregate_state == "verified"
    assert summary.run.execution_state == "completed"
    assert summary.run.verification_state == "verified"

    assert [required_check] = summary.required_checks
    assert required_check.verification_check_id == verification_check_id
    assert required_check.state == "satisfied"

    assert [observation] = summary.observations
    assert observation.normalized_status == "succeeded"

    assert [evidence_item] = summary.evidence_items
    assert evidence_item.state == "accepted"

    assert [verification_result] = summary.verification_results
    assert verification_result.result == "passed"
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
      source_surface: "domain_test",
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

  defp create_required_verification_check(session, label) do
    {:ok, operation} = Operations.start_operation(session, :proposed_change_apply)

    with {:ok, %{signal: signal}} <-
           WorkGraph.create_signal(session, operation, %{
             title: "#{label} launch signal",
             body: "#{label} launch signal body."
           }),
         {:ok, %{task: task}} <-
           WorkGraph.create_task(session, operation, signal, %{
             title: "#{label} launch task",
             body: "#{label} launch task body."
           }),
         {:ok, %{review_finding: review_finding}} <-
           WorkGraph.create_review_finding(session, operation, task, %{
             title: "#{label} launch finding",
             body: "#{label} launch finding body."
           }),
         {:ok, %{verification_check: verification_check}} <-
           WorkGraph.create_verification_check(session, operation, review_finding, %{
             title: "#{label} launch check",
             body: "#{label} launch check body."
           }) do
      {:ok, verification_check}
    end
  end
end
