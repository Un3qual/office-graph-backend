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
    attribute :step_key, :string, public?: true
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
        :step_key,
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
      validate present(:author_principal_id), where: [attribute_equals(:source, "human")]
      validate absent(:execution_id), where: [attribute_equals(:source, "human")]

      validate present([:author_principal_id, :execution_id, :context_package_id]),
        where: [attribute_equals(:source, "agent")]

      validate absent(:execution_id), where: [attribute_equals(:source, "system")]
    end
  end

  identities do
    identity :unique_operation, [:operation_id]
  end

  relationships do
    belongs_to :conversation, OfficeGraph.NodeConversations.Conversation do
      source_attribute :conversation_id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :author_principal, OfficeGraph.Identity.Principal do
      source_attribute :author_principal_id
      attribute_public? true
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :domain_action_operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :domain_action_operation_id
      attribute_public? true
    end

    belongs_to :context_package, OfficeGraph.AgentRuntime.ContextPackage do
      source_attribute :context_package_id
      destination_attribute :id
      attribute_public? true
    end

    belongs_to :execution, OfficeGraph.AgentRuntime.AgentExecution do
      source_attribute :execution_id
      destination_attribute :id
      attribute_public? true
    end

    belongs_to :proposed_graph_change, OfficeGraph.ProposedChanges.ProposedGraphChange do
      source_attribute :proposed_graph_change_id
      destination_attribute :id
      attribute_public? true
    end
  end
end
