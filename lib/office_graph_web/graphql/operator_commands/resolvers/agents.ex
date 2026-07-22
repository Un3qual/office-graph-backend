defmodule OfficeGraphWeb.GraphQL.OperatorCommands.Resolvers.Agents do
  @moduledoc false

  alias OfficeGraph.{AgentRuntime, Operations}
  alias OfficeGraphWeb.GraphQL.Common.Errors
  alias OfficeGraphWeb.OperatorCommands.Input
  alias OfficeGraphWeb.RequestSession

  def resolve_approval(%{input: input}, resolution) do
    with {:ok, parsed} <- Input.parse(:resolve_agent_approval, input),
         {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
         {idempotency_key, command_input} <- Map.pop!(parsed, :idempotency_key),
         {:ok, operation} <-
           Operations.start_command(
             session_context,
             :agent_approval_resolve,
             idempotency_key,
             command_input
           ),
         {:ok, result} <- resolve_approval_decision(session_context, operation, command_input) do
      {:ok, payload("resolve_agent_approval", operation, result, "agent_approval_request")}
    else
      error -> Errors.to_absinthe(error)
    end
  end

  def resolve_context_expansion(%{input: input}, resolution) do
    with {:ok, parsed} <- Input.parse(:resolve_agent_context_expansion, input),
         {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
         {idempotency_key, command_input} <- Map.pop!(parsed, :idempotency_key),
         {:ok, operation} <-
           Operations.start_command(
             session_context,
             :agent_context_expansion_resolve,
             idempotency_key,
             command_input
           ),
         {:ok, result} <-
           resolve_context_expansion_decision(session_context, operation, command_input) do
      payload =
        payload(
          "resolve_agent_context_expansion",
          operation,
          result,
          "agent_context_expansion_request"
        )

      {:ok,
       Map.put(payload, :context_package_id, result.context_package && result.context_package.id)}
    else
      error -> Errors.to_absinthe(error)
    end
  end

  def resolve_approval_decision(session_context, operation, attrs) do
    args = [
      session_context,
      operation,
      attrs.approval_request_id,
      attrs.expected_version,
      attrs.resolution_reason
    ]

    case attrs.decision do
      "approved" -> apply(AgentRuntime, :approve, args)
      "denied" -> apply(AgentRuntime, :deny_approval, args)
      "cancelled" -> apply(AgentRuntime, :cancel_approval, args)
      _invalid -> {:error, {:invalid_field, :decision}}
    end
  end

  def resolve_context_expansion_decision(session_context, operation, attrs) do
    args = [
      session_context,
      operation,
      attrs.context_expansion_request_id,
      attrs.expected_version,
      attrs.resolution_reason
    ]

    case attrs.decision do
      "approved" -> apply(AgentRuntime, :approve_context_expansion, args)
      "denied" -> apply(AgentRuntime, :deny_context_expansion, args)
      "cancelled" -> apply(AgentRuntime, :cancel_context_expansion, args)
      _invalid -> {:error, {:invalid_field, :decision}}
    end
  end

  def payload(command, operation, result, request_type) do
    %{
      command: command,
      operation_id: operation.id,
      affected_ids: [
        %{type: request_type, id: result.request.id},
        %{type: "agent_execution", id: result.execution.id}
      ],
      request: result.request,
      execution: result.execution
    }
  end
end
