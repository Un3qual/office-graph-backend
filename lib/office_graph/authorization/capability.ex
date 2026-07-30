defmodule OfficeGraph.Authorization.Capability do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Authorization.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "capabilities"
    repo OfficeGraph.Repo

    identity_index_names key: "capabilities_key_index"
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :key, :string, allow_nil?: false, public?: true
    attribute :description, :string, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    has_many :role_capabilities, OfficeGraph.Authorization.RoleCapability do
      source_attribute :id
      destination_attribute :capability_id
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:id, :key, :description]
    end

    create :ensure do
      public? false
      accept [:key, :description]
      upsert? true
      upsert_identity :key
      upsert_fields []
      return_skipped_upsert? true
    end

    action :setup_catalog, :integer do
      public? false
      transaction? true
      run OfficeGraph.Authorization.Actions.SetupCapabilityCatalog
    end
  end

  identities do
    identity :key, [:key]
  end

  policies do
    policy action(:setup_catalog) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if always()
    end
  end
end
