defmodule OfficeGraph.AgentRuntime.ContextEntry do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.AgentRuntime.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "agent_context_entries"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names unique_package_ordinal: "agent_context_entries_package_ordinal_index"
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :entry_type, :string, allow_nil?: false, public?: true
    attribute :resource_type, :string, allow_nil?: false, public?: true
    attribute :resource_id, :uuid, allow_nil?: false, public?: true
    attribute :posture, :string, allow_nil?: false, public?: true
    attribute :rationale_code, :string, allow_nil?: false, public?: true
    attribute :source_version, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :content_hash, :string, public?: true
    attribute :ordinal, :integer, allow_nil?: false, constraints: [min: 0], public?: true
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
        :context_package_id,
        :organization_id,
        :workspace_id,
        :entry_type,
        :resource_type,
        :resource_id,
        :external_reference_id,
        :posture,
        :rationale_code,
        :source_version,
        :content_hash,
        :ordinal,
        :operation_id
      ]

      validate one_of(:posture, ~w(included redacted omitted restricted expansion_required))
    end
  end

  identities do
    identity :unique_package_ordinal, [:context_package_id, :ordinal]
  end

  relationships do
    belongs_to :context_package, OfficeGraph.AgentRuntime.ContextPackage do
      source_attribute :context_package_id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :external_reference, OfficeGraph.ExternalRefs.ExternalReference do
      source_attribute :external_reference_id
      attribute_public? true
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      allow_nil? false
      attribute_public? true
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
  end
end
