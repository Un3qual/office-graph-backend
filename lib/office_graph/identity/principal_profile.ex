defmodule OfficeGraph.Identity.PrincipalProfile do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Identity.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "principal_profiles"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :principal_id, :uuid, allow_nil?: false, public?: true
    attribute :display_name, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    defaults [:read]

    create :create do
      accept [:id, :principal_id, :display_name]
    end
  end

  identities do
    identity :principal_id, [:principal_id]
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(principal_id == ^actor(:principal_id))
    end
  end
end
