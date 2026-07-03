defmodule OfficeGraph.Projections.RunState do
  @moduledoc false

  alias OfficeGraph.Runs
  alias OfficeGraph.Verification
  alias OfficeGraph.WorkGraph.EvidenceCandidate

  require Ash.Query

  def operator_run_state(session_context, run_id) do
    with {:ok, summary} <- Runs.get_summary(session_context, run_id),
         {:ok, evidence_candidates} <- read_evidence_candidates(session_context, summary.run.id) do
      {:ok, build_run_state(summary, evidence_candidates)}
    end
  end

  def verification_outcome(session_context, run_id) do
    with {:ok, run_state} <- operator_run_state(session_context, run_id) do
      {:ok,
       %{
         type: "verification_outcome",
         status: run_state.status,
         run: run_state.run,
         verification_results: run_state.verification_results,
         missing_evidence: run_state.missing_evidence,
         source_watermark: run_state.source_watermark
       }}
    end
  end

  defp read_evidence_candidates(session_context, run_id) do
    EvidenceCandidate
    |> Ash.Query.filter(
      work_run_id == ^run_id and organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read(authorize?: false)
  end

  defp build_run_state(summary, evidence_candidates) do
    status = run_status(summary, evidence_candidates)

    %{
      type: "operator_run_state",
      status: status,
      allowed_next_actions: run_next_actions(status),
      source_watermark: summary.run.id,
      packet: %{
        id: summary.packet.id,
        title: summary.packet.title,
        state: summary.packet.state
      },
      packet_version: %{
        id: summary.packet_version.id,
        version_number: summary.packet_version.version_number,
        lifecycle_state: summary.packet_version.lifecycle_state,
        objective: summary.packet_version.objective
      },
      run: %{
        id: summary.run.id,
        aggregate_state: summary.run.aggregate_state,
        execution_state: summary.run.execution_state,
        verification_state: summary.run.verification_state
      },
      required_checks:
        Enum.map(summary.required_checks, fn required_check ->
          %{
            id: required_check.id,
            verification_check_id: required_check.verification_check_id,
            state: required_check.state
          }
        end),
      observations:
        Enum.map(summary.observations, fn observation ->
          %{
            id: observation.id,
            verification_check_id: observation.verification_check_id,
            graph_item_id: observation.graph_item_id,
            normalized_status: observation.normalized_status,
            freshness_state: observation.freshness_state,
            trust_basis: observation.trust_basis,
            source_kind: observation.source_kind,
            source_identity: observation.source_identity
          }
        end),
      evidence_candidates: Enum.map(evidence_candidates, &evidence_candidate_projection/1),
      evidence_items:
        Enum.map(summary.evidence_items, fn evidence_item ->
          %{
            id: evidence_item.id,
            state: evidence_item.state,
            candidate_id: evidence_item.candidate_id,
            work_run_id: evidence_item.work_run_id
          }
        end),
      verification_results:
        Enum.map(summary.verification_results, fn result ->
          %{
            id: result.id,
            result: result.result,
            verification_check_id: result.verification_check_id,
            evidence_item_id: result.evidence_item_id,
            operation_id: result.operation_id,
            actor_principal_id: result.actor_principal_id,
            policy_basis: result.policy_basis,
            target_graph_item_id: result.target_graph_item_id,
            work_run_id: result.work_run_id,
            work_packet_version_id: result.work_packet_version_id
          }
        end),
      missing_evidence: Enum.map(summary.missing_evidence, &missing_evidence_projection/1)
    }
  end

  defp run_status(summary, _evidence_candidates)
       when summary.run.verification_state == "verified" or
              summary.run.aggregate_state == "verified" do
    "verified"
  end

  defp run_status(summary, _evidence_candidates)
       when summary.run.aggregate_state == "failed" or summary.run.verification_state == "failed" do
    "failed"
  end

  defp run_status(summary, evidence_candidates) do
    cond do
      pending_candidate_for_missing_check?(summary, evidence_candidates) ->
        "awaiting_evidence_acceptance"

      summary.observations != [] and summary.missing_evidence != [] ->
        "awaiting_evidence"

      summary.observations == [] ->
        "awaiting_execution"

      true ->
        "awaiting_evidence"
    end
  end

  defp run_next_actions("awaiting_execution"), do: ["record_observation"]
  defp run_next_actions("awaiting_evidence"), do: ["create_evidence_candidate"]
  defp run_next_actions("awaiting_evidence_acceptance"), do: ["accept_evidence"]
  defp run_next_actions(_status), do: []

  defp pending_candidate_for_missing_check?(summary, evidence_candidates) do
    missing_check_ids = MapSet.new(summary.missing_evidence, & &1.verification_check_id)

    Enum.any?(evidence_candidates, fn candidate ->
      candidate.candidate_state == "candidate" and
        MapSet.member?(missing_check_ids, candidate.verification_check_id) and
        Verification.acceptable_evidence_source?(candidate)
    end)
  end

  defp evidence_candidate_projection(candidate) do
    %{
      id: candidate.id,
      verification_check_id: candidate.verification_check_id,
      execution_observation_id: candidate.execution_observation_id,
      claim: candidate.claim,
      state: candidate.candidate_state,
      freshness_state: candidate.freshness_state,
      trust_basis: candidate.trust_basis,
      source_kind: candidate.source_kind,
      source_identity: candidate.source_identity
    }
  end

  defp missing_evidence_projection(%{
         verification_check_id: verification_check_id,
         reason: reason
       }) do
    %{verification_check_id: verification_check_id, reason: reason}
  end
end
