defmodule OfficeGraph.Verification.CommandResults.CreateEvidenceCandidate do
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
  end

  use AshGraphql.Type

  @impl true
  def graphql_type(_constraints), do: :create_evidence_candidate_payload

  def from_result(operation, candidate) do
    new(
      command: "create_evidence_candidate",
      operation_id: operation.id,
      affected_ids: [TypedId.new!(type: "evidence_candidate", id: candidate.id)],
      evidence_candidate: candidate
    )
  end
end

defimpl Jason.Encoder,
  for: OfficeGraph.Verification.CommandResults.CreateEvidenceCandidate do
  def encode(result, options) do
    Jason.Encode.map(
      %{
        command: result.command,
        operation_id: result.operation_id,
        affected_ids: result.affected_ids,
        evidence_candidate: %{
          id: result.evidence_candidate.id,
          candidate_state: result.evidence_candidate.candidate_state
        }
      },
      options
    )
  end
end
