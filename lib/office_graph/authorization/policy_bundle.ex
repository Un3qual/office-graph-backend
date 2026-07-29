defmodule OfficeGraph.Authorization.PolicyBundle do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Authorization.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "policy_bundles"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names unique_version: "policy_bundles_organization_id_version_index"
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :version, :integer, allow_nil?: false, public?: true
    attribute :status, :string, allow_nil?: false, public?: true

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
  end

  actions do
    defaults [:read]

    create :create do
      accept [:id, :organization_id, :version, :status]
    end

    create :ensure do
      public? false
      accept [:organization_id, :version, :status]
      upsert? true
      upsert_identity :unique_version
      upsert_fields []
      return_skipped_upsert? true
    end
  end

  identities do
    identity :unique_version, [:organization_id, :version]
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(organization_id == ^actor(:organization_id))
    end
  end
end
