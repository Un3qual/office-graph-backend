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

    identity_index_names unique_scoped_source_external_id:
                           "external_references_scoped_source_external_id_index",
                         unique_legacy_source_external_id:
                           "external_references_source_id_external_id_index"

    foreign_key_names source_id: "external_references_source_id_fkey"
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :organization_id, :uuid, public?: true
    attribute :source_id, :uuid, allow_nil?: false, public?: true
    attribute :provider, :string, public?: true
    attribute :object_type, :string, public?: true
    attribute :external_id, :string, allow_nil?: false, public?: true
    attribute :url, :string, public?: true

    attribute :sync_state, :string,
      allow_nil?: false,
      default: "synced",
      public?: true

    attribute :operation_id, :uuid, public?: true
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
      accept [
        :id,
        :organization_id,
        :source_id,
        :provider,
        :object_type,
        :external_id,
        :url,
        :sync_state,
        :operation_id,
        :resource_type,
        :resource_id
      ]

      validate one_of(:sync_state, ~w(pending synced stale failed))
      validate present([:organization_id, :operation_id]), where: [present(:provider)]
    end

    update :reconcile do
      accept [
        :provider,
        :object_type,
        :url,
        :sync_state,
        :operation_id,
        :resource_type,
        :resource_id
      ]

      validate one_of(:sync_state, ~w(pending synced stale failed))
      require_atomic? false
      public? false
    end
  end

  identities do
    identity :unique_scoped_source_external_id,
             [:organization_id, :source_id, :external_id],
             where: expr(not is_nil(organization_id))

    identity :unique_legacy_source_external_id,
             [:source_id, :external_id],
             where: expr(is_nil(organization_id))
  end
end
