defmodule OfficeGraphWeb.JsonApi.OperatorCommands.AgentsController do
  use OfficeGraphWeb, :controller

  alias OfficeGraph.Operations
  alias OfficeGraphWeb.GraphQL.OperatorCommands.Resolvers.Agents
  alias OfficeGraphWeb.JsonApi.Common.Errors
  alias OfficeGraphWeb.JsonApi.OperatorCommands.Serializer
  alias OfficeGraphWeb.OperatorCommands.Input
  alias OfficeGraphWeb.RequestSession

  def resolve_approval(conn, params) do
    resolve(
      conn,
      params,
      :resolve_agent_approval,
      :agent_approval_resolve,
      "agent_approval_request",
      &Agents.resolve_approval_decision/3
    )
  end

  def resolve_context_expansion(conn, params) do
    resolve(
      conn,
      params,
      :resolve_agent_context_expansion,
      :agent_context_expansion_resolve,
      "agent_context_expansion_request",
      &Agents.resolve_context_expansion_decision/3
    )
  end

  defp resolve(conn, params, command, action, request_type, resolver) do
    command_name = Atom.to_string(command)

    with {:ok, parsed} <- Input.parse(command, params),
         {:ok, session_context} <- request_session(conn),
         {idempotency_key, command_input} <- Map.pop!(parsed, :idempotency_key),
         {:ok, operation} <-
           Operations.start_command(session_context, action, idempotency_key, command_input),
         {:ok, result} <- resolver.(session_context, operation, command_input) do
      payload = Agents.payload(command_name, operation, result, request_type)

      Serializer.render(conn, command_name, operation.id, payload.affected_ids, %{
        request: request_result(result.request),
        execution: execution_result(result.execution),
        context_package_id: Map.get(result, :context_package) && result.context_package.id
      })
    else
      error -> Errors.render(conn, error, command: command_name)
    end
  end

  defp request_result(request) do
    %{
      id: request.id,
      state: request.state,
      version: request.version,
      resolution_operation_id: request.resolution_operation_id
    }
  end

  defp execution_result(execution) do
    %{
      id: execution.id,
      state: execution.state,
      state_version: execution.state_version,
      current_step_key: execution.current_step_key
    }
  end

  defp request_session(conn) do
    conn |> Ash.PlugHelpers.get_actor() |> RequestSession.resolve()
  end
end
