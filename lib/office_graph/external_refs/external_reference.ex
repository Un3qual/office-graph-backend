defmodule OfficeGraph.ExternalRefs.ExternalReference do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.ExternalRefs.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "external_references"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names unique_source_external_id:
                           "external_references_source_id_external_id_index"

    foreign_key_names source_id: "external_references_source_id_fkey"
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :source_id, :uuid, allow_nil?: false, public?: true
    attribute :external_id, :string, allow_nil?: false, public?: true
    attribute :resource_type, :string, allow_nil?: false, public?: true
    attribute :resource_id, :uuid, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    read :read do
      primary? true
      public? false
    end

    create :create do
      accept [:id, :source_id, :external_id, :resource_type, :resource_id]
    end
  end

  identities do
    identity :unique_source_external_id, [:source_id, :external_id]
  end
end
