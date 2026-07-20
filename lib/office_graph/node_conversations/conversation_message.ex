defmodule OfficeGraph.NodeConversations.ConversationMessage do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.NodeConversations.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "conversation_messages"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names unique_operation: "conversation_messages_operation_index"
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :conversation_id, :uuid, allow_nil?: false, public?: true
    attribute :execution_id, :uuid, public?: true
    attribute :author_principal_id, :uuid, public?: true
    attribute :context_package_id, :uuid, public?: true
    attribute :operation_id, :uuid, allow_nil?: false, public?: true
    attribute :proposed_graph_change_id, :uuid, public?: true
    attribute :domain_action_operation_id, :uuid, public?: true
    attribute :source, :string, allow_nil?: false, public?: true
    attribute :visibility, :string, allow_nil?: false, public?: true
    attribute :body, :string, allow_nil?: false, public?: true
    attribute :body_hash, :string, allow_nil?: false, public?: true
    create_timestamp :inserted_at, public?: true
  end

  actions do
    read :read do
      primary? true
      public? false
    end

    create :create do
      public? false

      accept [
        :id,
        :conversation_id,
        :execution_id,
        :author_principal_id,
        :context_package_id,
        :operation_id,
        :proposed_graph_change_id,
        :domain_action_operation_id,
        :source,
        :visibility,
        :body,
        :body_hash
      ]

      validate one_of(:source, ~w(human agent system))
      validate one_of(:visibility, ~w(run_participants workspace))
    end
  end

  identities do
    identity :unique_operation, [:operation_id]
  end

  relationships do
    belongs_to :conversation, OfficeGraph.NodeConversations.Conversation do
      source_attribute :conversation_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :author_principal, OfficeGraph.Identity.Principal do
      source_attribute :author_principal_id
      define_attribute? false
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :domain_action_operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :domain_action_operation_id
      define_attribute? false
    end
  end
end
