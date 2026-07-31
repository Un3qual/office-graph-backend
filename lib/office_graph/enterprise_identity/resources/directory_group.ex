defmodule OfficeGraph.EnterpriseIdentity.DirectoryGroup do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.EnterpriseIdentity.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "enterprise_directory_groups"
    repo OfficeGraph.Repo

    identity_index_names provider_group: "enterprise_directory_groups_provider_group_index"
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :provider_group_id, :string, allow_nil?: false, public?: true
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :status, :string, allow_nil?: false, public?: true
    attribute :provider_updated_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :provider_received_at, :utc_datetime_usec, public?: true
    attribute :provider_event_id, :string, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :directory, OfficeGraph.EnterpriseIdentity.Directory do
      allow_nil? false
      attribute_public? true
    end

    has_many :memberships, OfficeGraph.EnterpriseIdentity.DirectoryMembership do
      destination_attribute :directory_group_id
    end

    has_many :role_mappings, OfficeGraph.EnterpriseIdentity.ExternalGroupRoleMapping do
      destination_attribute :directory_group_id
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
        :provider_group_id,
        :name,
        :status,
        :provider_updated_at,
        :provider_received_at,
        :provider_event_id
      ]

      validate one_of(:status, ~w(active deleted))
    end

    update :synchronize do
      public? false

      accept [
        :name,
        :status,
        :provider_updated_at,
        :provider_received_at,
        :provider_event_id
      ]

      validate one_of(:status, ~w(active deleted)),
        where: [changing(:status)]

      require_atomic? false
    end
  end

  identities do
    identity :provider_group, [:directory_id, :provider_group_id]
  end
end
