defmodule OfficeGraph.NodeConversations.Conversation do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.NodeConversations.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "conversations"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names unique_run_graph_item: "conversations_run_graph_item_index"
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :graph_item_id, :uuid, allow_nil?: false, public?: true
    attribute :run_id, :uuid, allow_nil?: false, public?: true
    attribute :created_by_principal_id, :uuid, allow_nil?: false, public?: true
    attribute :operation_id, :uuid, allow_nil?: false, public?: true
    attribute :purpose, :string, allow_nil?: false, public?: true
    attribute :visibility, :string, allow_nil?: false, public?: true
    attribute :state, :string, allow_nil?: false, public?: true
    attribute :state_version, :integer, allow_nil?: false, default: 1, public?: true
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
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
        :organization_id,
        :workspace_id,
        :graph_item_id,
        :run_id,
        :created_by_principal_id,
        :operation_id,
        :purpose,
        :visibility,
        :state,
        :state_version
      ]

      validate one_of(:visibility, ~w(run_participants workspace))
      validate one_of(:state, ~w(active closed archived))
    end

    update :set_lifecycle_state do
      public? false
      accept [:state, :state_version]
      validate one_of(:state, ~w(active closed archived))
    end
  end

  identities do
    identity :unique_run_graph_item, [
      :organization_id,
      :workspace_id,
      :run_id,
      :graph_item_id,
      :purpose
    ]
  end

  relationships do
    belongs_to :graph_item, OfficeGraph.WorkGraph.GraphItem do
      source_attribute :graph_item_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :run, OfficeGraph.Runs.Run do
      source_attribute :run_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :created_by_principal, OfficeGraph.Identity.Principal do
      source_attribute :created_by_principal_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      define_attribute? false
      allow_nil? false
    end

    has_many :messages, OfficeGraph.NodeConversations.ConversationMessage do
      destination_attribute :conversation_id
    end
  end
end
