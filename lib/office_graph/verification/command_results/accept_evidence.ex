defmodule OfficeGraph.Verification.CommandResults.AcceptEvidence do
  @moduledoc false

  alias OfficeGraph.CommandSupport.TypedId

  use Ash.TypedStruct

  typed_struct do
    field :command, :string, allow_nil?: false
    field :operation_id, :uuid, allow_nil?: false
    field :affected_ids, {:array, TypedId}, allow_nil?: false

    field :evidence_candidate, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.WorkGraph.EvidenceCandidate]

    field :evidence_item, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.WorkGraph.EvidenceItem]

    field :verification_result, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.WorkGraph.VerificationResult]

    field :run, :struct, constraints: [instance_of: OfficeGraph.Runs.Run]
  end

  use AshGraphql.Type

  @impl true
  def graphql_type(_constraints), do: :accept_evidence_payload

  def from_result(operation, result) do
    new(
      command: "accept_evidence",
      operation_id: operation.id,
      affected_ids: affected_ids(result),
      evidence_candidate: result.candidate,
      evidence_item: result.evidence_item,
      verification_result: result.verification_result,
      run: result.work_run
    )
  end

  defp affected_ids(result) do
    [
      TypedId.new!(type: "evidence_candidate", id: result.candidate.id),
      TypedId.new!(type: "evidence_item", id: result.evidence_item.id),
      TypedId.new!(type: "verification_result", id: result.verification_result.id)
    ] ++
      optional_typed_id("verification_check", result.affected_verification_check_id) ++
      optional_typed_id("run_required_check", result.affected_run_required_check_id) ++
      optional_typed_id("review_finding", result.affected_review_finding_id) ++
      optional_typed_id("task", result.affected_task_id) ++
      optional_typed_id("work_run", result.work_run)
  end

  defp optional_typed_id(_type, nil), do: []

  defp optional_typed_id(type, id) when is_binary(id),
    do: [TypedId.new!(type: type, id: id)]

  defp optional_typed_id(type, resource),
    do: [TypedId.new!(type: type, id: resource.id)]
end

defimpl Jason.Encoder, for: OfficeGraph.Verification.CommandResults.AcceptEvidence do
  def encode(result, options) do
    Jason.Encode.map(
      %{
        command: result.command,
        operation_id: result.operation_id,
        affected_ids: result.affected_ids,
        evidence_candidate: %{
          id: result.evidence_candidate.id,
          candidate_state: result.evidence_candidate.candidate_state
        },
        evidence_item: %{id: result.evidence_item.id, state: result.evidence_item.state},
        verification_result: %{
          id: result.verification_result.id,
          result: result.verification_result.result
        },
        run: optional_run_result(result.run)
      },
      options
    )
  end

  defp optional_run_result(nil), do: nil
  defp optional_run_result(run), do: run_result(run)

  defp run_result(run) do
    %{
      id: run.id,
      work_packet_version_id: run.work_packet_version_id,
      execution_state: run.execution_state,
      verification_state: run.verification_state,
      aggregate_state: run.aggregate_state
    }
  end
end
