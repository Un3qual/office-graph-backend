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
    uuid_primary_key :id, writable?: true
    attribute :execution_id, :uuid, allow_nil?: false, public?: true
    attribute :authority_snapshot_id, :uuid, allow_nil?: false, public?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :selected_graph_item_id, :uuid, allow_nil?: false, public?: true
    attribute :run_id, :uuid, allow_nil?: false, public?: true
    attribute :previous_package_id, :uuid, public?: true
    attribute :expansion_request_id, :uuid, public?: true
    attribute :operation_id, :uuid, allow_nil?: false, public?: true
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
      define_attribute? false
      allow_nil? false
    end

    belongs_to :authority_snapshot, OfficeGraph.AgentRuntime.AuthoritySnapshot do
      source_attribute :authority_snapshot_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :selected_graph_item, OfficeGraph.WorkGraph.GraphItem do
      source_attribute :selected_graph_item_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :run, OfficeGraph.Runs.Run do
      source_attribute :run_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :previous_package, OfficeGraph.AgentRuntime.ContextPackage do
      source_attribute :previous_package_id
      define_attribute? false
    end

    belongs_to :expansion_request, OfficeGraph.AgentRuntime.ContextExpansionRequest do
      source_attribute :expansion_request_id
      define_attribute? false
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      define_attribute? false
      allow_nil? false
    end

    has_many :entries, OfficeGraph.AgentRuntime.ContextEntry do
      destination_attribute :context_package_id
    end
  end
end
