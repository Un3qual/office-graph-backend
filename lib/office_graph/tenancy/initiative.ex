defmodule OfficeGraph.Tenancy.Initiative do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Tenancy.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "initiatives"
    repo OfficeGraph.Repo

    identity_index_names unique_slug: "initiatives_workspace_id_slug_index",
                         unique_scope: "initiatives_id_workspace_id_organization_id_index"

    references do
      reference :workspace do
        name "initiatives_workspace_scope_fkey"
        match_with organization_id: :organization_id
      end
    end
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

    belongs_to :workspace, OfficeGraph.Tenancy.Workspace do
      source_attribute :workspace_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    has_many :workstreams, OfficeGraph.Tenancy.Workstream do
      source_attribute :id
      destination_attribute :initiative_id
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:id, :organization_id, :workspace_id, :name, :slug]
    end

    create :ensure do
      public? false
      accept [:organization_id, :workspace_id, :name, :slug]
      upsert? true
      upsert_identity :unique_slug
      upsert_fields []
      return_skipped_upsert? true
    end
  end

  identities do
    identity :unique_slug, [:workspace_id, :slug]
    identity :unique_scope, [:id, :workspace_id, :organization_id]
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(
                     organization_id == ^actor(:organization_id) and
                       workspace_id == ^actor(:workspace_id)
                   )
    end
  end
end
