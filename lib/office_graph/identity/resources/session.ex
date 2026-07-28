defmodule OfficeGraph.Identity.Session do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Identity.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "sessions"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :purpose, :string, allow_nil?: false, public?: true
    attribute :authentication_method, :string, public?: true
    attribute :issued_at, :utc_datetime_usec, public?: true
    attribute :expires_at, :utc_datetime_usec, public?: true
    attribute :source_surface, :string, public?: true
    attribute :trace_id, :string, public?: true
    attribute :revoked_at, :utc_datetime_usec, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :external_identity_link, OfficeGraph.Identity.ExternalIdentityLink do
      source_attribute :external_identity_link_id
      destination_attribute :id
      attribute_public? true
    end

    belongs_to :organization, OfficeGraph.Tenancy.Organization do
      source_attribute :organization_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :principal, OfficeGraph.Identity.Principal do
      source_attribute :principal_id
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
      accept [
        :id,
        :principal_id,
        :external_identity_link_id,
        :organization_id,
        :workspace_id,
        :purpose,
        :authentication_method,
        :issued_at,
        :expires_at,
        :source_surface,
        :trace_id,
        :revoked_at
      ]
    end

    update :revoke do
      accept [:revoked_at]
    end
  end

  identities do
    identity :unique_context, [:principal_id, :organization_id, :workspace_id, :purpose],
      where: expr(is_nil(revoked_at))
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(
                     principal_id == ^actor(:principal_id) and
                       organization_id == ^actor(:organization_id) and
                       workspace_id == ^actor(:workspace_id)
                   )
    end
  end
end
