defmodule OfficeGraph.AgentRuntime.CommandResults.ExecutionMutation do
  @moduledoc false

  alias OfficeGraph.CommandSupport.TypedId

  use Ash.TypedStruct

  typed_struct do
    field :command, :string, allow_nil?: false
    field :operation_id, :uuid, allow_nil?: false
    field :affected_ids, {:array, TypedId}, allow_nil?: false

    field :execution, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.AgentRuntime.AgentExecution]

    field :context_package_id, :uuid
  end

  use AshGraphql.Type

  @impl true
  def graphql_type(_constraints), do: :agent_execution_mutation_payload

  def from_invocation(result) do
    new(
      command: "invoke_agent",
      operation_id: result.operation.id,
      affected_ids: [TypedId.new!(type: "agent_execution", id: result.execution.id)],
      execution: result.execution,
      context_package_id: result.context_package.id
    )
  end

  def from_cancellation(operation, result) do
    new(
      command: "cancel_agent_execution",
      operation_id: operation.id,
      affected_ids: [TypedId.new!(type: "agent_execution", id: result.execution.id)],
      execution: result.execution,
      context_package_id: nil
    )
  end
end

defimpl Jason.Encoder, for: OfficeGraph.AgentRuntime.CommandResults.ExecutionMutation do
  def encode(result, options) do
    Jason.Encode.map(
      %{
        command: result.command,
        operation_id: result.operation_id,
        affected_ids: result.affected_ids,
        execution: %{
          id: result.execution.id,
          state: result.execution.state,
          state_version: result.execution.state_version,
          current_step_key: result.execution.current_step_key
        },
        context_package_id: result.context_package_id
      },
      options
    )
  end
end
