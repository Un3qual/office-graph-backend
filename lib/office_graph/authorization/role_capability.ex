defmodule OfficeGraph.Authorization.RoleCapability do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Authorization.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "role_capabilities"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false, public?: true, writable?: true
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

    create :create do
      accept [:id, :role_id, :capability_id]
    end
  end

  identities do
    identity :unique_role_capability, [:role_id, :capability_id]
  end
end
