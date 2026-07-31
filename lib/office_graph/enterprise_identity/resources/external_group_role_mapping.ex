defmodule OfficeGraph.EnterpriseIdentity.ExternalGroupRoleMapping do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.EnterpriseIdentity.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "external_group_role_mappings"
    repo OfficeGraph.Repo

    identity_index_names active_mapping: "external_group_role_mappings_active_mapping_index"
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
    attribute :disabled_at, :utc_datetime_usec, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :directory_group, OfficeGraph.EnterpriseIdentity.DirectoryGroup do
      allow_nil? false
      attribute_public? true
    end

    belongs_to :role, OfficeGraph.Authorization.Role do
      allow_nil? false
      attribute_public? true
    end

    belongs_to :organization, OfficeGraph.Tenancy.Organization do
      allow_nil? false
      attribute_public? true
    end

    belongs_to :workspace, OfficeGraph.Tenancy.Workspace do
      attribute_public? true
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
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
        :directory_group_id,
        :role_id,
        :organization_id,
        :workspace_id,
        :operation_id,
        :status,
        :disabled_at
      ]

      change set_attribute(:active_identity_slot, nil)

      change set_attribute(:active_identity_slot, "active") do
        where attribute_equals(:status, "active")
      end

      validate one_of(:status, ~w(active disabled))
    end

    update :set_lifecycle do
      public? false
      accept [:operation_id, :status, :disabled_at]

      change set_attribute(:active_identity_slot, nil)

      change set_attribute(:active_identity_slot, "active") do
        where attribute_equals(:status, "active")
      end

      validate one_of(:status, ~w(active disabled)),
        where: [changing(:status)]

      require_atomic? false
    end
  end

  identities do
    identity :active_mapping,
             [
               :directory_group_id,
               :role_id,
               :organization_id,
               :workspace_id,
               :active_identity_slot
             ],
             nils_distinct?: false
  end
end
