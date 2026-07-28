defmodule OfficeGraph.AgentRuntime.ContextPackage do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.AgentRuntime.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "agent_context_packages"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names unique_execution_version:
                           "agent_context_packages_execution_version_index"
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :version, :integer, allow_nil?: false, public?: true
    attribute :package_hash, :string, allow_nil?: false, public?: true
    attribute :assembled_at, :utc_datetime_usec, allow_nil?: false, public?: true
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
        :execution_id,
        :authority_snapshot_id,
        :organization_id,
        :workspace_id,
        :selected_graph_item_id,
        :run_id,
        :previous_package_id,
        :expansion_request_id,
        :operation_id,
        :version,
        :package_hash,
        :assembled_at
      ]
    end
  end

  identities do
    identity :unique_execution_version, [:execution_id, :version]
  end

  relationships do
    belongs_to :execution, OfficeGraph.AgentRuntime.AgentExecution do
      source_attribute :execution_id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :authority_snapshot, OfficeGraph.AgentRuntime.AuthoritySnapshot do
      source_attribute :authority_snapshot_id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :selected_graph_item, OfficeGraph.WorkGraph.GraphItem do
      source_attribute :selected_graph_item_id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :run, OfficeGraph.Runs.Run do
      source_attribute :run_id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :previous_package, OfficeGraph.AgentRuntime.ContextPackage do
      source_attribute :previous_package_id
      attribute_public? true
    end

    belongs_to :expansion_request, OfficeGraph.AgentRuntime.ContextExpansionRequest do
      source_attribute :expansion_request_id
      attribute_public? true
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      allow_nil? false
      attribute_public? true
    end

    has_many :entries, OfficeGraph.AgentRuntime.ContextEntry do
      destination_attribute :context_package_id
    end

    belongs_to :organization, OfficeGraph.Tenancy.Organization do
      source_attribute :organization_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :workspace, OfficeGraph.Tenancy.Workspace do
      source_attribute :workspace_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    has_many :proposed_changes, OfficeGraph.ProposedChanges.ProposedGraphChange do
      source_attribute :id
      destination_attribute :context_package_id
    end

    has_many :evidence_candidates, OfficeGraph.WorkGraph.EvidenceCandidate do
      source_attribute :id
      destination_attribute :context_package_id
    end

    has_many :model_requests, OfficeGraph.AgentRuntime.ModelRequest do
      source_attribute :id
      destination_attribute :context_package_id
    end

    has_many :tool_requests, OfficeGraph.AgentRuntime.ToolRequest do
      source_attribute :id
      destination_attribute :context_package_id
    end

    has_many :execution_observations, OfficeGraph.Runs.ExecutionObservation do
      source_attribute :id
      destination_attribute :context_package_id
    end

    has_many :conversation_messages, OfficeGraph.NodeConversations.ConversationMessage do
      source_attribute :id
      destination_attribute :context_package_id
    end
  end
end
