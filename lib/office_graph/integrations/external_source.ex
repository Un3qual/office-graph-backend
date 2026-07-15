defmodule OfficeGraph.Integrations.ExternalSource do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Integrations.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "external_sources"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names unique_kind_key: "external_sources_kind_key_index"
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :key, :string, allow_nil?: false, public?: true
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :kind, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    read :read do
      primary? true
      public? false
    end

    create :create do
      accept [:id, :key, :name, :kind]
    end
  end

  identities do
    identity :unique_kind_key, [:kind, :key]
  end
end
