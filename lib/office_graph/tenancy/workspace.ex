defmodule OfficeGraph.Tenancy.Workspace do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Tenancy.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "workspaces"
    repo OfficeGraph.Repo

    identity_index_names unique_slug: "workspaces_organization_id_slug_index",
                         unique_scope: "workspaces_id_organization_id_index"
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :name, :string, allow_nil?: false, public?: true
    attribute :slug, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :organization, OfficeGraph.Tenancy.Organization do
      source_attribute :organization_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    has_many :initiatives, OfficeGraph.Tenancy.Initiative do
      source_attribute :id
      destination_attribute :workspace_id
    end

    has_many :workstreams, OfficeGraph.Tenancy.Workstream do
      source_attribute :id
      destination_attribute :workspace_id
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:id, :organization_id, :name, :slug]
    end

    create :ensure do
      public? false
      accept [:organization_id, :name, :slug]
      upsert? true
      upsert_identity :unique_slug
      upsert_fields []
      return_skipped_upsert? true
    end
  end

  identities do
    identity :unique_slug, [:organization_id, :slug]
    identity :unique_scope, [:id, :organization_id]
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(
                     organization_id == ^actor(:organization_id) and
                       id == ^actor(:workspace_id)
                   )
    end
  end
end
