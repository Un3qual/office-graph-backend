defmodule OfficeGraph.NodeConversations.Domain do
  @moduledoc false

  use Ash.Domain, otp_app: :office_graph

  resources do
    resource OfficeGraph.NodeConversations.Conversation
    resource OfficeGraph.NodeConversations.ConversationMessage
  end
end
