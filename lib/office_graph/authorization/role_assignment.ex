defmodule OfficeGraph.Authorization.RoleAssignment do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Authorization.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "role_assignments"
    repo OfficeGraph.Repo
    migrate? false

    unique_index_names [
      {[:principal_id, :role_id, :organization_id], "role_assignments_org_wide_unique_index"},
      {[:principal_id, :role_id, :organization_id, :workspace_id],
       "role_assignments_workspace_unique_index"}
    ]
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

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

    belongs_to :principal, OfficeGraph.Identity.Principal do
      source_attribute :principal_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :role, OfficeGraph.Authorization.Role do
      source_attribute :role_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :workspace, OfficeGraph.Tenancy.Workspace do
      source_attribute :workspace_id
      destination_attribute :id
      attribute_public? true
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:id, :principal_id, :role_id, :organization_id, :workspace_id]
    end

    create :ensure do
      public? false
      accept [:principal_id, :role_id, :organization_id, :workspace_id]
      upsert? true
      upsert_identity :unique_assignment
      upsert_fields []
      return_skipped_upsert? true
    end

    destroy :revoke do
      public? false
    end
  end

  identities do
    identity :unique_assignment, [:principal_id, :role_id, :organization_id, :workspace_id],
      nils_distinct?: false
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(
                     principal_id == ^actor(:principal_id) and
                       organization_id == ^actor(:organization_id) and
                       (is_nil(workspace_id) or workspace_id == ^actor(:workspace_id))
                   )
    end
  end
end
