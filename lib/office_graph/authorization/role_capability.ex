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
    attribute :role_id, :uuid, allow_nil?: false, public?: true
    attribute :capability_id, :uuid, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    defaults [:read]

    create :create do
      accept [:id, :role_id, :capability_id]
    end
  end

  identities do
    identity :unique_role_capability, [:role_id, :capability_id]
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end
  end
end
