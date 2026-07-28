defmodule OfficeGraph.NodeConversations.Domain do
  @moduledoc false

  use Ash.Domain,
    extensions: [AshGraphql.Domain, AshJsonApi.Domain],
    otp_app: :office_graph

  graphql do
    queries do
      get OfficeGraph.NodeConversations.Conversation, :get_conversation, :read
      list OfficeGraph.NodeConversations.Conversation, :list_conversations, :read, relay?: true

      read_one OfficeGraph.NodeConversations.Conversation,
               :conversation_for_run_graph_item,
               :read_for_run_graph_item do
        relay_id_translations(run_id: :work_run, graph_item_id: :graph_item)
      end

      get OfficeGraph.NodeConversations.ConversationMessage, :get_conversation_message, :read

      list OfficeGraph.NodeConversations.ConversationMessage,
           :list_conversation_messages,
           :read,
           relay?: true
    end
  end

  json_api do
    routes do
      base_route "/conversations", OfficeGraph.NodeConversations.Conversation do
        get(:read, primary?: true)
        index :read
        related(:graph_item, :read)
        related(:run, :read)
        related(:messages, :read)
        related(:agent_executions, :read)
      end

      base_route "/conversation-messages", OfficeGraph.NodeConversations.ConversationMessage do
        get(:read, primary?: true)
        index :read
        related(:conversation, :read)
        related(:execution, :read)
      end
    end
  end

  resources do
    resource OfficeGraph.NodeConversations.Conversation
    resource OfficeGraph.NodeConversations.ConversationMessage
  end
end
