defmodule OfficeGraph.AgentRuntime.AuthoritySnapshot do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.AgentRuntime.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "agent_authority_snapshots"
    repo OfficeGraph.Repo

    identity_index_names unique_execution_version:
                           "agent_authority_snapshots_execution_version_index"
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :policy_bundle_version, :integer, public?: true
    attribute :version, :integer, allow_nil?: false, public?: true
    attribute :capability_keys, {:array, :string}, allow_nil?: false, default: [], public?: true
    attribute :tool_keys, {:array, :string}, allow_nil?: false, default: [], public?: true
    attribute :credential_ids, {:array, :uuid}, allow_nil?: false, default: [], public?: true
    attribute :model_adapter_key, :string, allow_nil?: false, public?: true
    attribute :model_adapter_version, :string, allow_nil?: false, public?: true
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
        :model_adapter_key,
        :model_adapter_version,
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
      allow_nil? false
      attribute_public? true
    end

    belongs_to :agent_principal, OfficeGraph.Identity.Principal do
      source_attribute :agent_principal_id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :delegator_principal, OfficeGraph.Identity.Principal do
      source_attribute :delegator_principal_id
      attribute_public? true
    end

    belongs_to :policy_bundle, OfficeGraph.Authorization.PolicyBundle do
      source_attribute :policy_bundle_id
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
