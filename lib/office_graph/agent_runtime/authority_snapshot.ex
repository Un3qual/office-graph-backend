defmodule OfficeGraph.AgentRuntime.AuthoritySnapshot do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.AgentRuntime.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "agent_authority_snapshots"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names unique_execution_version:
                           "agent_authority_snapshots_execution_version_index"
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :execution_id, :uuid, allow_nil?: false, public?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :agent_principal_id, :uuid, allow_nil?: false, public?: true
    attribute :delegator_principal_id, :uuid, public?: true
    attribute :policy_bundle_id, :uuid, public?: true
    attribute :policy_bundle_version, :integer, public?: true
    attribute :operation_id, :uuid, allow_nil?: false, public?: true
    attribute :version, :integer, allow_nil?: false, public?: true
    attribute :capability_keys, {:array, :string}, allow_nil?: false, default: [], public?: true
    attribute :tool_keys, {:array, :string}, allow_nil?: false, default: [], public?: true
    attribute :credential_ids, {:array, :uuid}, allow_nil?: false, default: [], public?: true
    attribute :autonomy_mode, :string, allow_nil?: false, public?: true
    attribute :authority_hash, :string, allow_nil?: false, public?: true
    attribute :captured_at, :utc_datetime_usec, allow_nil?: false, public?: true
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
        :organization_id,
        :workspace_id,
        :agent_principal_id,
        :delegator_principal_id,
        :policy_bundle_id,
        :policy_bundle_version,
        :operation_id,
        :version,
        :capability_keys,
        :tool_keys,
        :credential_ids,
        :autonomy_mode,
        :authority_hash,
        :captured_at
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

    belongs_to :agent_principal, OfficeGraph.Identity.Principal do
      source_attribute :agent_principal_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :delegator_principal, OfficeGraph.Identity.Principal do
      source_attribute :delegator_principal_id
      define_attribute? false
    end

    belongs_to :policy_bundle, OfficeGraph.Authorization.PolicyBundle do
      source_attribute :policy_bundle_id
      define_attribute? false
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      define_attribute? false
      allow_nil? false
    end
  end
end
