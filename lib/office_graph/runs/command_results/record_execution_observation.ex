defmodule OfficeGraph.Runs.CommandResults.RecordExecutionObservation do
  @moduledoc false

  alias OfficeGraph.CommandSupport.TypedId

  use Ash.TypedStruct

  typed_struct do
    field :command, :string, allow_nil?: false
    field :operation_id, :uuid, allow_nil?: false
    field :affected_ids, {:array, TypedId}, allow_nil?: false

    field :observation, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.Runs.ExecutionObservation]

    field :run, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.Runs.Run]
  end

  use AshGraphql.Type

  @impl true
  def graphql_type(_constraints), do: :record_execution_observation_payload

  def from_result(operation, result) do
    new(
      command: "record_execution_observation",
      operation_id: operation.id,
      affected_ids: [
        TypedId.new!(type: "execution_observation", id: result.observation.id),
        TypedId.new!(type: "work_run", id: result.run.id)
      ],
      observation: result.observation,
      run: result.run
    )
  end
end

defimpl Jason.Encoder, for: OfficeGraph.Runs.CommandResults.RecordExecutionObservation do
  def encode(result, options) do
    Jason.Encode.map(
      %{
        command: result.command,
        operation_id: result.operation_id,
        affected_ids: result.affected_ids,
        observation: %{
          id: result.observation.id,
          normalized_status: result.observation.normalized_status
        },
        run: %{
          id: result.run.id,
          work_packet_version_id: result.run.work_packet_version_id,
          execution_state: result.run.execution_state,
          verification_state: result.run.verification_state,
          aggregate_state: result.run.aggregate_state
        }
      },
      options
    )
  end
end
