defmodule OfficeGraph.AgentRuntime.AgentDefinition do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.AgentRuntime.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "agent_definitions"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names unique_key: "agent_definitions_key_index"
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :key, :string, allow_nil?: false, public?: true
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :description, :string, public?: true
    attribute :lifecycle_state, :string, allow_nil?: false, public?: true
    attribute :supported_modes, {:array, :string}, allow_nil?: false, default: [], public?: true

    attribute :requested_capabilities, {:array, :string},
      allow_nil?: false,
      default: [],
      public?: true

    attribute :model_adapter_key, :string, allow_nil?: false, public?: true
    attribute :model_credential_id, :uuid, public?: true
    attribute :tool_allowlist, {:array, :string}, allow_nil?: false, default: [], public?: true
    attribute :default_autonomy_mode, :string, allow_nil?: false, public?: true

    attribute :allowed_output_kinds, {:array, :string},
      allow_nil?: false,
      default: [],
      public?: true

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
        :key,
        :name,
        :description,
        :lifecycle_state,
        :supported_modes,
        :requested_capabilities,
        :model_adapter_key,
        :model_credential_id,
        :tool_allowlist,
        :default_autonomy_mode,
        :allowed_output_kinds
      ]

      validate one_of(:lifecycle_state, ~w(active disabled retired))
      validate one_of(:default_autonomy_mode, ~w(human_supervised bounded_automatic))
    end

    update :set_lifecycle_state do
      public? false
      accept [:lifecycle_state]
      validate one_of(:lifecycle_state, ~w(active disabled retired))
    end
  end

  identities do
    identity :unique_key, [:key]
  end

  relationships do
    belongs_to :model_credential, OfficeGraph.Integrations.IntegrationCredential do
      source_attribute :model_credential_id
      define_attribute? false
      public? true
    end

    has_many :organization_bindings, OfficeGraph.AgentRuntime.OrganizationBinding do
      destination_attribute :definition_id
    end
  end
end
