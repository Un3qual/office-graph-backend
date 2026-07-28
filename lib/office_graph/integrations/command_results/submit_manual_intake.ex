defmodule OfficeGraph.Integrations.CommandResults.SubmitManualIntake do
  @moduledoc false

  use Ash.TypedStruct

  typed_struct do
    field :command, :string, allow_nil?: false
    field :operation_id, :uuid, allow_nil?: false
    field :affected_ids, {:array, OfficeGraph.CommandSupport.TypedId}, allow_nil?: false

    field :normalized_event, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.Integrations.NormalizedIntakeEvent]

    field :proposed_changes, {:array, :struct},
      allow_nil?: false,
      constraints: [items: [instance_of: OfficeGraph.ProposedChanges.ProposedGraphChange]]
  end

  use AshGraphql.Type

  @impl true
  def graphql_type(_constraints), do: :submit_manual_intake_payload
end

defimpl Jason.Encoder, for: OfficeGraph.Integrations.CommandResults.SubmitManualIntake do
  def encode(result, options) do
    Jason.Encode.map(
      %{
        command: result.command,
        operation_id: result.operation_id,
        affected_ids: result.affected_ids,
        normalized_event: %{id: result.normalized_event.id},
        proposed_changes: Enum.map(result.proposed_changes, &%{id: &1.id})
      },
      options
    )
  end
end
