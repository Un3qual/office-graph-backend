defmodule OfficeGraph.NodeConversations.CommandResults.StartRunConversation do
  @moduledoc false

  alias OfficeGraph.CommandSupport.TypedId

  use Ash.TypedStruct

  typed_struct do
    field :command, :string, allow_nil?: false
    field :operation_id, :uuid, allow_nil?: false
    field :affected_ids, {:array, TypedId}, allow_nil?: false

    field :conversation, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.NodeConversations.Conversation]
  end

  use AshGraphql.Type

  @impl true
  def graphql_type(_constraints), do: :start_run_conversation_payload

  def from_result(operation, conversation) do
    new(
      command: "start_run_conversation",
      operation_id: operation.id,
      affected_ids: [TypedId.new!(type: "conversation", id: conversation.id)],
      conversation: conversation
    )
  end
end

defimpl Jason.Encoder,
  for: OfficeGraph.NodeConversations.CommandResults.StartRunConversation do
  def encode(result, options) do
    Jason.Encode.map(
      %{
        command: result.command,
        operation_id: result.operation_id,
        affected_ids: result.affected_ids,
        conversation:
          Map.take(result.conversation, [
            :id,
            :run_id,
            :graph_item_id,
            :created_by_principal_id,
            :operation_id,
            :purpose,
            :visibility,
            :state,
            :state_version,
            :inserted_at,
            :updated_at
          ])
      },
      options
    )
  end
end
