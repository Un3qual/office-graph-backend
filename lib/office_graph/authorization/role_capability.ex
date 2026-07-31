defmodule OfficeGraph.Authorization.RoleCapability do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Authorization.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "role_capabilities"
    repo OfficeGraph.Repo

    identity_index_names unique_role_capability: "role_capabilities_role_id_capability_id_index"
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :capability, OfficeGraph.Authorization.Capability do
      source_attribute :capability_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :role, OfficeGraph.Authorization.Role do
      source_attribute :role_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end
  end

  actions do
    read :read do
      primary? true
      public? false
    end

    read :read_for_local_development_login do
      public? false

      argument :role_ids, {:array, :uuid}, allow_nil?: false
      filter expr(role_id in ^arg(:role_ids))
    end

    create :create do
      accept [:id, :role_id, :capability_id]
    end

    create :ensure do
      public? false
      accept [:role_id, :capability_id]
      upsert? true
      upsert_identity :unique_role_capability
      upsert_fields []
      return_skipped_upsert? true
    end

    destroy :revoke do
      public? false
    end
  end

  identities do
    identity :unique_role_capability, [:role_id, :capability_id]
  end

  policies do
    policy action(:read_for_local_development_login) do
      authorize_if always()
    end
  end
end
