defmodule OfficeGraph.NodeConversations.MessageCommands do
  @moduledoc false

  @behaviour Ash.Resource.Actions.Implementation

  alias OfficeGraph.{Authorization, CommandSupport, Operations, ProposedChanges}

  alias OfficeGraph.NodeConversations.{
    ActionSupport,
    Conversation,
    ConversationCommands,
    ConversationMessage
  }

  require Ash.Query

  @message_action "conversation.message.create"
  @purpose "agent_runtime"
  @visibility "run_participants"

  @impl true
  def run(input, [mode: :human], %{actor: session_context}) when is_map(session_context) do
    case persist_human_message(session_context, input.arguments) do
      {:ok, message} -> {:ok, message}
      {:error, error} -> ActionSupport.rollback(ConversationMessage, error)
    end
  end

  def run(input, [mode: :agent], _context) do
    case persist_agent_message(input.arguments) do
      {:ok, message} -> {:ok, message}
      {:error, error} -> ActionSupport.rollback(ConversationMessage, error)
    end
  end

  def run(_input, _opts, _context), do: {:error, :forbidden}

  defp persist_human_message(session_context, attrs) do
    with {:ok, operation} <- Operations.lock_operation(attrs.operation_id),
         :ok <- Operations.validate_operation_context(session_context, operation),
         :ok <- Operations.validate_operation_action(operation, @message_action),
         :ok <-
           Authorization.authorize_operation(
             session_context,
             operation,
             :conversation_write,
             organization_id: session_context.organization_id
           ),
         {:ok, conversation} <-
           locked_active_conversation(session_context, attrs.conversation_id),
         :ok <- validate_message_linkage(session_context, attrs),
         {:ok, existing} <- message_for_operation(operation.id) do
      case existing do
        nil -> create_human_message(session_context, operation, conversation, attrs)
        message -> validate_human_message_replay(message, session_context, conversation, attrs)
      end
    end
  end

  defp persist_agent_message(attrs) do
    with {:ok, operation} <- Operations.lock_operation(attrs.operation_id),
         :ok <-
           Operations.validate_agent_output_operation(
             operation,
             attrs.execution,
             attrs.context_package,
             attrs.step_key
           ),
         {:ok, conversation} <-
           ConversationCommands.ensure_agent_conversation(operation, attrs.execution),
         {:ok, existing} <- agent_message(attrs.execution.id, attrs.step_key) do
      case existing do
        nil ->
          create_agent_message(
            operation,
            attrs.execution,
            attrs.context_package,
            conversation,
            attrs
          )

        message ->
          validate_agent_message_replay(
            message,
            operation,
            attrs.context_package,
            conversation,
            attrs
          )
      end
    end
  end

  defp locked_active_conversation(session_context, conversation_id) do
    Conversation
    |> Ash.Query.filter(
      id == ^conversation_id and organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id and purpose == @purpose
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %Conversation{state: "active"} = conversation} ->
        {:ok, conversation}

      {:ok, %Conversation{id: id, state: state}} ->
        {:error, {:conversation_not_active, id, state}}

      {:ok, nil} ->
        {:error, :forbidden}

      {:error, _storage_error} ->
        {:error, :integration_storage_unavailable}
    end
  end

  defp validate_message_linkage(session_context, attrs) do
    case attrs do
      %{
        contribution_kind: "comment",
        proposed_graph_change_id: nil,
        domain_action_operation_id: nil
      } ->
        :ok

      %{
        contribution_kind: "proposal",
        proposed_graph_change_id: proposal_id,
        domain_action_operation_id: nil
      }
      when is_binary(proposal_id) ->
        validate_proposal_scope(session_context, proposal_id)

      %{
        contribution_kind: "domain_action",
        proposed_graph_change_id: nil,
        domain_action_operation_id: operation_id
      }
      when is_binary(operation_id) ->
        validate_domain_operation_scope(session_context, operation_id)

      %{contribution_kind: kind} ->
        {:error, {:invalid_conversation_message_linkage, kind}}
    end
  end

  defp validate_proposal_scope(session_context, proposal_id) do
    ProposedChanges.validate_reference_scope(session_context, proposal_id)
  end

  defp validate_domain_operation_scope(session_context, operation_id) do
    case Operations.read_operation(operation_id) do
      {:ok, operation}
      when operation.organization_id == session_context.organization_id and
             operation.workspace_id == session_context.workspace_id and
             operation.action not in ["conversation.start", @message_action] ->
        :ok

      {:ok, _operation} ->
        {:error, :forbidden}

      {:error, {:not_found, _resource, _id}} ->
        {:error, :forbidden}

      {:error, _storage_error} ->
        {:error, :integration_storage_unavailable}
    end
  end

  defp message_for_operation(operation_id) do
    ConversationMessage
    |> Ash.Query.filter(operation_id == ^operation_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, message} -> {:ok, message}
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  defp create_human_message(session_context, operation, conversation, attrs) do
    create_message(%{
      conversation_id: conversation.id,
      author_principal_id: session_context.principal_id,
      operation_id: operation.id,
      proposed_graph_change_id: attrs.proposed_graph_change_id,
      domain_action_operation_id: attrs.domain_action_operation_id,
      source: "human",
      visibility: @visibility,
      body: attrs.body,
      body_hash: digest(attrs.body)
    })
  end

  defp validate_human_message_replay(message, session_context, conversation, attrs) do
    if message.conversation_id == conversation.id and
         message.source == "human" and
         message.author_principal_id == session_context.principal_id and
         message.body_hash == digest(attrs.body) and
         message.proposed_graph_change_id == attrs.proposed_graph_change_id and
         message.domain_action_operation_id == attrs.domain_action_operation_id do
      {:ok, message}
    else
      {:error, {:conversation_message_replay_conflict, message.id}}
    end
  end

  defp agent_message(execution_id, step_key) do
    ConversationMessage
    |> Ash.Query.filter(execution_id == ^execution_id and step_key == ^step_key)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, message} -> {:ok, message}
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  defp create_agent_message(operation, execution, context_package, conversation, attrs) do
    create_message(%{
      conversation_id: conversation.id,
      execution_id: execution.id,
      author_principal_id: execution.agent_principal_id,
      context_package_id: context_package.id,
      step_key: attrs.step_key,
      operation_id: operation.id,
      source: "agent",
      visibility: @visibility,
      body: attrs.body,
      body_hash: digest(attrs.body)
    })
  end

  defp validate_agent_message_replay(message, operation, context_package, conversation, attrs) do
    if message.conversation_id == conversation.id and
         message.operation_id == operation.id and
         message.context_package_id == context_package.id and
         message.body_hash == digest(attrs.body) do
      {:ok, message}
    else
      {:error, :agent_message_replay_conflict}
    end
  end

  defp create_message(attrs) do
    ConversationMessage
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create(authorize?: false, return_notifications?: true)
    |> CommandSupport.normalize_ash_write()
    |> case do
      {:ok, message} -> {:ok, message}
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  defp digest(value) do
    :sha256
    |> :crypto.hash(value)
    |> Base.encode16(case: :lower)
  end
end
