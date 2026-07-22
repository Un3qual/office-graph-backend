defmodule OfficeGraph.NodeConversations do
  @moduledoc """
  Public boundary for run-aware graph conversations and message provenance.
  """

  use Boundary,
    deps: [
      OfficeGraph.Identity,
      OfficeGraph.Operations,
      OfficeGraph.Repo,
      OfficeGraph.Runs,
      OfficeGraph.WorkGraph
    ],
    exports: []

  alias OfficeGraph.{Operations, Repo}
  alias OfficeGraph.NodeConversations.{Conversation, ConversationMessage}

  require Ash.Query

  def append_agent_message(operation, execution, context_package, step_key, body)
      when is_map(operation) and is_map(execution) and is_map(context_package) and
             is_binary(step_key) and is_binary(body) do
    with :ok <- validate_agent_operation(operation, execution, context_package, step_key) do
      conversation = get_or_create_conversation!(operation, execution)

      case existing_agent_message(execution.id, step_key) do
        nil ->
          Repo.ash_create!(ConversationMessage, %{
            id: Ecto.UUID.generate(),
            conversation_id: conversation.id,
            execution_id: execution.id,
            author_principal_id: execution.agent_principal_id,
            context_package_id: context_package.id,
            step_key: step_key,
            operation_id: operation.id,
            source: "agent",
            visibility: "run_participants",
            body: body,
            body_hash: digest(body)
          })

        message ->
          if message.operation_id == operation.id and
               message.context_package_id == context_package.id and
               message.body_hash == digest(body),
             do: message,
             else: Repo.rollback(:agent_message_replay_conflict)
      end
    end
  end

  defp get_or_create_conversation!(operation, execution) do
    Conversation
    |> Ash.Query.filter(
      organization_id == ^execution.organization_id and workspace_id == ^execution.workspace_id and
        run_id == ^execution.run_id and graph_item_id == ^execution.graph_item_id and
        purpose == "agent_runtime"
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
    |> case do
      nil ->
        Repo.ash_create!(Conversation, %{
          id: Ecto.UUID.generate(),
          organization_id: execution.organization_id,
          workspace_id: execution.workspace_id,
          graph_item_id: execution.graph_item_id,
          run_id: execution.run_id,
          created_by_principal_id: execution.agent_principal_id,
          operation_id: operation.id,
          purpose: "agent_runtime",
          visibility: "run_participants",
          state: "active",
          state_version: 1
        })

      conversation ->
        conversation
    end
  end

  defp existing_agent_message(execution_id, step_key) do
    ConversationMessage
    |> Ash.Query.filter(execution_id == ^execution_id and step_key == ^step_key)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
  end

  defp validate_agent_operation(operation, execution, context_package, step_key) do
    Operations.validate_agent_output_operation(operation, execution, context_package, step_key)
  end

  defp digest(value) do
    :sha256
    |> :crypto.hash(value)
    |> Base.encode16(case: :lower)
  end
end
