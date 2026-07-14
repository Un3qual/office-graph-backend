defmodule OfficeGraph.Integrations.RawArchive do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Integrations.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "raw_archives"
    repo OfficeGraph.Repo
    migrate? false

    foreign_key_names organization_id: "raw_archives_organization_id_fkey",
                      workspace_id: "raw_archives_workspace_id_fkey",
                      source_id: "raw_archives_source_id_fkey",
                      operation_id: "raw_archives_operation_id_fkey"

    identity_index_names provider_delivery: "raw_archives_provider_delivery_index"
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, public?: true
    attribute :source_id, :uuid, allow_nil?: false, public?: true
    attribute :operation_id, :uuid, allow_nil?: false, public?: true
    attribute :content_hash, :string, allow_nil?: false, public?: true
    attribute :archive_kind, :string, allow_nil?: false, default: "manual_intake", public?: true
    attribute :external_delivery_id, :string, public?: true

    attribute :body, :string,
      allow_nil?: false,
      public?: true,
      constraints: [trim?: false]

    attribute :metadata, :map, allow_nil?: false, default: %{}, public?: true

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
        :workspace_id,
        :source_id,
        :operation_id,
        :content_hash,
        :archive_kind,
        :external_delivery_id,
        :body,
        :metadata
      ]
    end
  end

  identities do
    identity :provider_delivery, [:source_id, :external_delivery_id],
      where: expr(not is_nil(external_delivery_id))
  end
end
