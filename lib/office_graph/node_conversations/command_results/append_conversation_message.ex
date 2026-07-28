defmodule OfficeGraph.NodeConversations.CommandResults.AppendConversationMessage do
  @moduledoc false

  alias OfficeGraph.CommandSupport.TypedId

  use Ash.TypedStruct

  typed_struct do
    field :command, :string, allow_nil?: false
    field :operation_id, :uuid, allow_nil?: false
    field :affected_ids, {:array, TypedId}, allow_nil?: false

    field :message, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.NodeConversations.ConversationMessage]
  end

  use AshGraphql.Type

  @impl true
  def graphql_type(_constraints), do: :append_conversation_message_payload

  def from_result(operation, message) do
    new(
      command: "append_conversation_message",
      operation_id: operation.id,
      affected_ids: [
        TypedId.new!(type: "conversation", id: message.conversation_id),
        TypedId.new!(type: "conversation_message", id: message.id)
      ],
      message: message
    )
  end
end

defimpl Jason.Encoder,
  for: OfficeGraph.NodeConversations.CommandResults.AppendConversationMessage do
  def encode(result, options) do
    Jason.Encode.map(
      %{
        command: result.command,
        operation_id: result.operation_id,
        affected_ids: result.affected_ids,
        message:
          Map.take(result.message, [
            :id,
            :conversation_id,
            :source,
            :body,
            :visibility,
            :author_principal_id,
            :execution_id,
            :context_package_id,
            :operation_id,
            :proposed_graph_change_id,
            :domain_action_operation_id,
            :inserted_at
          ])
      },
      options
    )
  end
end
