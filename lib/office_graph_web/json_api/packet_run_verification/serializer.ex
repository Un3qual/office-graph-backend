defmodule OfficeGraphWeb.JsonApi.PacketRunVerification.Serializer do
  @moduledoc false

  def summary(summary) do
    %{
      packet: packet(summary.packet),
      packet_version: packet_version(summary.packet_version),
      run: run(summary.run),
      required_checks: Enum.map(summary.required_checks, &required_check/1),
      observations: Enum.map(summary.observations, &observation/1),
      evidence_items: Enum.map(summary.evidence_items, &evidence_item/1),
      verification_results: Enum.map(summary.verification_results, &verification_result/1),
      missing_evidence: Enum.map(summary.missing_evidence, &missing_evidence/1)
    }
  end

  defp packet(packet) do
    %{
      id: packet.id,
      title: packet.title,
      state: packet.state
    }
  end

  defp packet_version(version) do
    %{
      id: version.id,
      version_number: version.version_number,
      lifecycle_state: version.lifecycle_state,
      objective: version.objective
    }
  end

  defp run(run) do
    %{
      id: run.id,
      aggregate_state: run.aggregate_state,
      execution_state: run.execution_state,
      verification_state: run.verification_state
    }
  end

  defp required_check(required_check) do
    %{
      id: required_check.id,
      verification_check_id: required_check.verification_check_id,
      state: required_check.state
    }
  end

  defp observation(observation) do
    %{
      id: observation.id,
      normalized_status: observation.normalized_status,
      source_kind: observation.source_kind,
      source_identity: observation.source_identity
    }
  end

  defp evidence_item(evidence_item) do
    %{
      id: evidence_item.id,
      state: evidence_item.state,
      candidate_id: evidence_item.candidate_id,
      work_run_id: evidence_item.work_run_id
    }
  end

  defp verification_result(result) do
    %{
      id: result.id,
      result: result.result,
      evidence_item_id: result.evidence_item_id,
      operation_id: result.operation_id,
      work_run_id: result.work_run_id,
      work_packet_version_id: result.work_packet_version_id,
      actor_principal_id: result.actor_principal_id,
      policy_basis: result.policy_basis,
      target_graph_item_id: result.target_graph_item_id
    }
  end

  defp missing_evidence(reason) do
    %{
      verification_check_id: reason.verification_check_id,
      reason: reason.reason
    }
  end
end
