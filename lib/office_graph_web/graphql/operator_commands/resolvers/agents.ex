defmodule OfficeGraphWeb.GraphQL.OperatorCommands.Resolvers.Agents do
  @moduledoc false

  alias OfficeGraph.{AgentRuntime, NodeConversations, Operations}
  alias OfficeGraphWeb.GraphQL.Common.Errors
  alias OfficeGraphWeb.OperatorCommands.Input
  alias OfficeGraphWeb.RequestSession

  def invoke_agent(%{input: input}, resolution) do
    with {:ok, parsed} <- Input.parse(:invoke_agent, input),
         {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
         {:ok, operation, result} <- invoke(session_context, parsed) do
      {:ok, invocation_payload(operation, result)}
    else
      error -> Errors.to_absinthe(error)
    end
  end

  def cancel_agent_execution(%{input: input}, resolution) do
    with {:ok, parsed} <- Input.parse(:cancel_agent_execution, input),
         {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
         {:ok, operation, result} <- cancel_execution(session_context, parsed) do
      {:ok, cancellation_payload(operation, result)}
    else
      error -> Errors.to_absinthe(error)
    end
  end

  def invoke(session_context, parsed) do
    with {:ok, result} <- AgentRuntime.invoke_human(session_context, parsed) do
      {:ok, result.operation, result}
    end
  end

  def cancel_execution(session_context, parsed) do
    {idempotency_key, command_input} = Map.pop!(parsed, :idempotency_key)

    with {:ok, operation} <-
           Operations.start_command(
             session_context,
             :agent_cancel,
             idempotency_key,
             command_input
           ),
         {:ok, result} <-
           AgentRuntime.cancel_execution(session_context, operation, command_input) do
      {:ok, operation, result}
    end
  end

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

  def start_conversation(%{input: input}, resolution) do
    with {:ok, parsed} <- Input.parse(:start_run_conversation, input),
         {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
         {idempotency_key, command_input} <- Map.pop!(parsed, :idempotency_key),
         {:ok, operation} <-
           Operations.start_command(
             session_context,
             :conversation_start,
             idempotency_key,
             command_input
           ),
         {:ok, conversation} <-
           NodeConversations.start(session_context, operation, command_input) do
      {:ok, conversation_payload("start_run_conversation", operation, conversation)}
    else
      error -> Errors.to_absinthe(error)
    end
  end

  def append_conversation_message(%{input: input}, resolution) do
    with {:ok, parsed} <- Input.parse(:append_conversation_message, input),
         {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
         {idempotency_key, command_input} <- Map.pop!(parsed, :idempotency_key),
         {:ok, operation} <-
           Operations.start_command(
             session_context,
             :conversation_message_create,
             idempotency_key,
             command_input
           ),
         {:ok, message} <-
           NodeConversations.append_human_message(session_context, operation, command_input) do
      {:ok, message_payload("append_conversation_message", operation, message)}
    else
      error -> Errors.to_absinthe(error)
    end
  end

  def resolve_approval_decision(session_context, operation, attrs) do
    case attrs.decision do
      "approved" ->
        AgentRuntime.approve(
          session_context,
          operation,
          attrs.approval_request_id,
          attrs.expected_version,
          attrs.resolution_reason
        )

      "denied" ->
        AgentRuntime.deny_approval(
          session_context,
          operation,
          attrs.approval_request_id,
          attrs.expected_version,
          attrs.resolution_reason
        )

      "cancelled" ->
        AgentRuntime.cancel_approval(
          session_context,
          operation,
          attrs.approval_request_id,
          attrs.expected_version,
          attrs.resolution_reason
        )

      _invalid ->
        {:error, {:invalid_field, :decision}}
    end
  end

  def resolve_context_expansion_decision(session_context, operation, attrs) do
    case attrs.decision do
      "approved" ->
        AgentRuntime.approve_context_expansion(
          session_context,
          operation,
          attrs.context_expansion_request_id,
          attrs.expected_version,
          attrs.resolution_reason
        )

      "denied" ->
        AgentRuntime.deny_context_expansion(
          session_context,
          operation,
          attrs.context_expansion_request_id,
          attrs.expected_version,
          attrs.resolution_reason
        )

      "cancelled" ->
        AgentRuntime.cancel_context_expansion(
          session_context,
          operation,
          attrs.context_expansion_request_id,
          attrs.expected_version,
          attrs.resolution_reason
        )

      _invalid ->
        {:error, {:invalid_field, :decision}}
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

  def conversation_payload(command, operation, conversation) do
    %{
      command: command,
      operation_id: operation.id,
      affected_ids: [%{type: "conversation", id: conversation.id}],
      conversation: conversation
    }
  end

  def message_payload(command, operation, message) do
    %{
      command: command,
      operation_id: operation.id,
      affected_ids: [
        %{type: "conversation", id: message.conversation_id},
        %{type: "conversation_message", id: message.id}
      ],
      message: message
    }
  end

  def invocation_payload(operation, result) do
    %{
      command: "invoke_agent",
      operation_id: operation.id,
      affected_ids: [%{type: "agent_execution", id: result.execution.id}],
      execution: result.execution,
      context_package_id: result.context_package.id
    }
  end

  def cancellation_payload(operation, result) do
    %{
      command: "cancel_agent_execution",
      operation_id: operation.id,
      affected_ids: [%{type: "agent_execution", id: result.execution.id}],
      execution: result.execution
    }
  end
end
