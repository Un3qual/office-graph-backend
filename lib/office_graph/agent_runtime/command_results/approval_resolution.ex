defmodule OfficeGraph.AgentRuntime.CommandResults.ApprovalResolution do
  @moduledoc false

  alias OfficeGraph.CommandSupport.TypedId

  use Ash.TypedStruct

  typed_struct do
    field :command, :string, allow_nil?: false
    field :operation_id, :uuid, allow_nil?: false
    field :affected_ids, {:array, TypedId}, allow_nil?: false

    field :request, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.AgentRuntime.ApprovalRequest]

    field :execution, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.AgentRuntime.AgentExecution]
  end

  use AshGraphql.Type

  @impl true
  def graphql_type(_constraints), do: :resolve_agent_approval_payload

  def from_result(operation, result) do
    new(
      command: "resolve_agent_approval",
      operation_id: operation.id,
      affected_ids: [
        TypedId.new!(type: "agent_approval_request", id: result.request.id),
        TypedId.new!(type: "agent_execution", id: result.execution.id)
      ],
      request: result.request,
      execution: result.execution
    )
  end
end

defimpl Jason.Encoder,
  for: OfficeGraph.AgentRuntime.CommandResults.ApprovalResolution do
  def encode(result, options) do
    Jason.Encode.map(
      %{
        command: result.command,
        operation_id: result.operation_id,
        affected_ids: result.affected_ids,
        request: %{
          id: result.request.id,
          state: result.request.state,
          version: result.request.version,
          resolution_operation_id: result.request.resolution_operation_id
        },
        execution: %{
          id: result.execution.id,
          state: result.execution.state,
          state_version: result.execution.state_version,
          current_step_key: result.execution.current_step_key
        }
      },
      options
    )
  end
end
