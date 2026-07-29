defmodule OfficeGraph.ProposedChanges.CommandResults.ApplyProposedChanges do
  @moduledoc false

  use Ash.TypedStruct

  typed_struct do
    field :command, :string, allow_nil?: false
    field :operation_id, :uuid, allow_nil?: false
    field :affected_ids, {:array, OfficeGraph.CommandSupport.TypedId}, allow_nil?: false

    field :signal, :struct,
      allow_nil?: false,
      constraints: [instance_of: Module.concat([OfficeGraph, WorkGraph, Signal])]

    field :task, :struct,
      allow_nil?: false,
      constraints: [instance_of: Module.concat([OfficeGraph, WorkGraph, Task])]

    field :review_finding, :struct,
      allow_nil?: false,
      constraints: [instance_of: Module.concat([OfficeGraph, WorkGraph, ReviewFinding])]

    field :verification_check, :struct,
      allow_nil?: false,
      constraints: [
        instance_of: Module.concat([OfficeGraph, WorkGraph, VerificationCheck])
      ]
  end

  use AshGraphql.Type

  @impl true
  def graphql_type(_constraints), do: :apply_proposed_changes_payload
end

defimpl Jason.Encoder, for: OfficeGraph.ProposedChanges.CommandResults.ApplyProposedChanges do
  def encode(result, options) do
    Jason.Encode.map(
      %{
        command: result.command,
        operation_id: result.operation_id,
        affected_ids: result.affected_ids,
        signal: %{id: result.signal.id},
        task: %{id: result.task.id},
        review_finding: %{id: result.review_finding.id},
        verification_check: %{
          id: result.verification_check.id,
          graph_item_id: result.verification_check.graph_item_id
        }
      },
      options
    )
  end
end
