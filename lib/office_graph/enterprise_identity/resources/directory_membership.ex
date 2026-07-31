defmodule OfficeGraph.EnterpriseIdentity.DirectoryMembership do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.EnterpriseIdentity.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "enterprise_directory_memberships"
    repo OfficeGraph.Repo

    identity_index_names active_membership:
                           "enterprise_directory_memberships_active_membership_index"

    custom_indexes do
      index [
              :directory_user_id,
              :directory_group_id,
              :provider_updated_at,
              :provider_received_at,
              :provider_event_id,
              :id
            ],
            name: "enterprise_directory_memberships_order_index"
    end
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :status, :string, allow_nil?: false, public?: true
    attribute :active_identity_slot, :string, public?: false, writable?: false
    attribute :provider_updated_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :provider_received_at, :utc_datetime_usec, public?: true
    attribute :provider_event_id, :string, public?: true
    attribute :removed_at, :utc_datetime_usec, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :directory_user, OfficeGraph.EnterpriseIdentity.DirectoryUser do
      allow_nil? false
      attribute_public? true
    end

    belongs_to :directory_group, OfficeGraph.EnterpriseIdentity.DirectoryGroup do
      allow_nil? false
      attribute_public? true
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
        :directory_user_id,
        :directory_group_id,
        :status,
        :provider_updated_at,
        :provider_received_at,
        :provider_event_id,
        :removed_at
      ]

      change set_attribute(:active_identity_slot, nil)

      change set_attribute(:active_identity_slot, "active") do
        where attribute_equals(:status, "active")
      end

      validate one_of(:status, ~w(active removed))
    end

    update :set_lifecycle do
      public? false

      accept [
        :status,
        :provider_updated_at,
        :provider_received_at,
        :provider_event_id,
        :removed_at
      ]

      change set_attribute(:active_identity_slot, nil)

      change set_attribute(:active_identity_slot, "active") do
        where attribute_equals(:status, "active")
      end

      validate one_of(:status, ~w(active removed)),
        where: [changing(:status)]

      require_atomic? false
    end
  end

  identities do
    identity :active_membership,
             [:directory_user_id, :directory_group_id, :active_identity_slot]
  end
end
