defmodule OfficeGraph.Tenancy.Workstream do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Tenancy.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "workstreams"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names unique_slug: "workstreams_initiative_id_slug_index"
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
    belongs_to :initiative, OfficeGraph.Tenancy.Initiative do
      source_attribute :initiative_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

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
  end

  actions do
    defaults [:read]

    create :create do
      accept [:id, :organization_id, :workspace_id, :initiative_id, :name, :slug]
    end

    create :ensure do
      public? false
      accept [:organization_id, :workspace_id, :initiative_id, :name, :slug]
      upsert? true
      upsert_identity :unique_slug
      upsert_fields []
      return_skipped_upsert? true
    end
  end

  identities do
    identity :unique_slug, [:initiative_id, :slug]
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
