defmodule OfficeGraph.EnterpriseIdentity.DirectoryUser do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.EnterpriseIdentity.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "enterprise_directory_users"
    repo OfficeGraph.Repo

    identity_index_names provider_user: "enterprise_directory_users_provider_user_index",
                         idp_user: "enterprise_directory_users_idp_user_index"

    custom_indexes do
      index [:principal_id], name: "enterprise_directory_users_principal_id_index"
    end
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :provider_user_id, :string, allow_nil?: false, public?: true
    attribute :idp_id, :string, public?: true
    attribute :email, :string, allow_nil?: false, public?: true
    attribute :first_name, :string, public?: true
    attribute :last_name, :string, public?: true

    attribute :status, :string, allow_nil?: false, public?: true
    attribute :review_reason, :string, public?: true
    attribute :principal_origin, :string, public?: true
    attribute :provider_updated_at, :utc_datetime_usec, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :directory, OfficeGraph.EnterpriseIdentity.Directory do
      allow_nil? false
      attribute_public? true
    end

    belongs_to :principal, OfficeGraph.Identity.Principal do
      attribute_public? true
    end

    belongs_to :external_identity_link, OfficeGraph.Identity.ExternalIdentityLink do
      attribute_public? true
    end

    has_many :memberships, OfficeGraph.EnterpriseIdentity.DirectoryMembership do
      destination_attribute :directory_user_id
    end
  end

  actions do
    read :read do
      primary? true
      public? false
    end

    create :create do
      public? false

      accept [
        :id,
        :directory_id,
        :principal_id,
        :external_identity_link_id,
        :provider_user_id,
        :idp_id,
        :email,
        :first_name,
        :last_name,
        :status,
        :review_reason,
        :principal_origin,
        :provider_updated_at
      ]

      validate one_of(:status, ~w(active suspended deleted review_required))
      validate one_of(:principal_origin, ~w(created reused))
    end

    update :synchronize do
      public? false

      accept [
        :principal_id,
        :external_identity_link_id,
        :idp_id,
        :email,
        :first_name,
        :last_name,
        :status,
        :review_reason,
        :principal_origin,
        :provider_updated_at
      ]

      validate one_of(:status, ~w(active suspended deleted review_required)),
        where: [changing(:status)]

      validate one_of(:principal_origin, ~w(created reused)),
        where: [changing(:principal_origin)]

      require_atomic? false
    end
  end

  identities do
    identity :provider_user, [:directory_id, :provider_user_id]
    identity :idp_user, [:directory_id, :idp_id]
  end
end
