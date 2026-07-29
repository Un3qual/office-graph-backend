defmodule OfficeGraph.NodeConversations.ConversationCommands do
  @moduledoc false

  @behaviour Ash.Resource.Actions.Implementation

  alias OfficeGraph.{Authorization, CommandSupport, Operations}

  alias OfficeGraph.NodeConversations.{
    ActionSupport,
    Conversation
  }

  alias OfficeGraph.Runs.Run
  alias OfficeGraph.WorkPackets.WorkPacketSourceReference

  require Ash.Query

  @conversation_action "conversation.start"
  @purpose "agent_runtime"
  @visibility "run_participants"

  @impl true
  def run(input, [mode: :start], %{actor: session_context}) when is_map(session_context) do
    case persist_start(session_context, input.arguments) do
      {:ok, conversation} -> {:ok, conversation}
      {:error, error} -> ActionSupport.rollback(Conversation, error)
    end
  end

  def run(_input, _opts, _context), do: {:error, :forbidden}

  def ensure_agent_conversation(operation, execution) do
    with {:ok, _run} <- lock_valid_run_scope(execution),
         {:ok, conversation} <- locked_conversation(execution) do
      case conversation do
        nil ->
          create_conversation(%{
            organization_id: execution.organization_id,
            workspace_id: execution.workspace_id,
            graph_item_id: execution.graph_item_id,
            run_id: execution.run_id,
            created_by_principal_id: execution.agent_principal_id,
            operation_id: operation.id
          })

        conversation ->
          {:ok, conversation}
      end
    end
  end

  defp persist_start(session_context, attrs) do
    with {:ok, operation} <- Operations.lock_operation(attrs.operation_id),
         :ok <-
           Operations.validate_operation_context(
             session_context,
             operation
           ),
         :ok <- Operations.validate_operation_action(operation, @conversation_action),
         :ok <-
           Operations.validate_command_replay(operation, %{
             run_id: attrs.run_id,
             graph_item_id: attrs.graph_item_id
           }),
         :ok <-
           Authorization.authorize_operation(
             session_context,
             operation,
             :conversation_write,
             organization_id: session_context.organization_id
           ),
         scope = %{
           organization_id: session_context.organization_id,
           workspace_id: session_context.workspace_id,
           run_id: attrs.run_id,
           graph_item_id: attrs.graph_item_id
         },
         {:ok, _run} <- lock_valid_run_scope(scope),
         {:ok, conversation} <- locked_conversation(scope) do
      case conversation do
        nil ->
          create_conversation(%{
            organization_id: scope.organization_id,
            workspace_id: scope.workspace_id,
            graph_item_id: scope.graph_item_id,
            run_id: scope.run_id,
            created_by_principal_id: session_context.principal_id,
            operation_id: operation.id
          })

        conversation ->
          {:ok, conversation}
      end
    end
  end

  defp lock_valid_run_scope(scope) do
    Run
    |> Ash.Query.filter(
      id == ^scope.run_id and organization_id == ^scope.organization_id and
        workspace_id == ^scope.workspace_id
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} ->
        {:error, :forbidden}

      {:ok, run} ->
        validate_graph_item_membership(run, scope.graph_item_id)

      {:error, _storage_error} ->
        {:error, :integration_storage_unavailable}
    end
  end

  defp validate_graph_item_membership(run, graph_item_id) do
    WorkPacketSourceReference
    |> Ash.Query.filter(
      work_packet_version_id == ^run.work_packet_version_id and
        graph_item_id == ^graph_item_id and organization_id == ^run.organization_id and
        workspace_id == ^run.workspace_id
    )
    |> Ash.exists(authorize?: false)
    |> case do
      {:ok, true} -> {:ok, run}
      {:ok, false} -> {:error, :forbidden}
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  defp locked_conversation(scope) do
    Conversation
    |> Ash.Query.filter(
      organization_id == ^scope.organization_id and workspace_id == ^scope.workspace_id and
        run_id == ^scope.run_id and graph_item_id == ^scope.graph_item_id and
        purpose == @purpose
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, conversation} -> {:ok, conversation}
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  defp create_conversation(attrs) do
    Conversation
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(attrs, %{
        purpose: @purpose,
        visibility: @visibility,
        state: "active",
        state_version: 1
      })
    )
    |> Ash.create(authorize?: false, return_notifications?: true)
    |> CommandSupport.normalize_ash_write()
    |> case do
      {:ok, conversation} -> {:ok, conversation}
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end
end
