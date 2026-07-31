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

    mutations do
      action OfficeGraph.NodeConversations.Conversation,
             :start_run_conversation,
             :start_run_conversation do
        relay_id_translations(input: [run_id: :work_run, graph_item_id: :graph_item])
      end

      action OfficeGraph.NodeConversations.ConversationMessage,
             :append_conversation_message,
             :append_conversation_message do
        relay_id_translations(
          input: [
            conversation_id: :conversation,
            proposed_graph_change_id: :proposed_graph_change
          ]
        )
      end
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

      route(
        OfficeGraph.NodeConversations.Conversation,
        :post,
        "/commands/start-run-conversation",
        :start_run_conversation
      )

      route(
        OfficeGraph.NodeConversations.ConversationMessage,
        :post,
        "/commands/append-conversation-message",
        :append_conversation_message
      )
    end
  end

  resources do
    resource OfficeGraph.NodeConversations.Conversation
    resource OfficeGraph.NodeConversations.ConversationMessage
  end
end
