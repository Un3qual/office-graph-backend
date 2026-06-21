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
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :principal_id, :uuid, allow_nil?: false, public?: true
    attribute :role_id, :uuid, allow_nil?: false, public?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    defaults [:read]

    create :create do
      accept [:id, :principal_id, :role_id, :organization_id, :workspace_id]
    end
  end

  identities do
    identity :unique_assignment, [:principal_id, :role_id, :organization_id, :workspace_id]
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
