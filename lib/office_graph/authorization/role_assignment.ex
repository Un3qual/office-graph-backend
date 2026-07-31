defmodule OfficeGraph.Authorization.Actions.ReconcileLocalDevelopmentRoleAssignments do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.Authorization.RoleAssignment

  require Ash.Query

  @impl true
  def run(input, _opts, _context) do
    principal_id = input.arguments.principal_id
    expected_assignment_id = input.arguments.expected_assignment_id

    with :ok <- revoke_unexpected_assignments(principal_id, expected_assignment_id),
         :ok <- validate_exact_assignment(principal_id, expected_assignment_id) do
      {:ok, :ok}
    end
  end

  defp revoke_unexpected_assignments(principal_id, expected_assignment_id) do
    RoleAssignment
    |> Ash.Query.filter(principal_id == ^principal_id and id != ^expected_assignment_id)
    |> Ash.bulk_destroy(:revoke, %{},
      authorize?: false,
      return_errors?: true,
      strategy: [:atomic]
    )
    |> case do
      %Ash.BulkResult{status: :success} -> :ok
      %Ash.BulkResult{errors: errors} -> {:error, Ash.Error.to_error_class(errors)}
    end
  end

  defp validate_exact_assignment(principal_id, expected_assignment_id) do
    RoleAssignment
    |> Ash.Query.filter(principal_id == ^principal_id)
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, [%RoleAssignment{id: ^expected_assignment_id}]} -> :ok
      {:ok, _unexpected_assignments} -> {:error, "local development role assignment drift"}
      {:error, error} -> {:error, error}
    end
  end
end

defmodule OfficeGraph.Authorization.RoleAssignment do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Authorization.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "role_assignments"
    repo OfficeGraph.Repo

    unique_index_names [
      {[:principal_id, :role_id, :organization_id], "role_assignments_org_wide_unique_index"},
      {[:principal_id, :role_id, :organization_id, :workspace_id],
       "role_assignments_workspace_unique_index"}
    ]

    references do
      reference :workspace do
        name "role_assignments_workspace_scope_fkey"
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

    read :read_for_local_development_login do
      public? false

      argument :principal_id, :uuid, allow_nil?: false
      filter expr(principal_id == ^arg(:principal_id))
    end

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

    action :reconcile_local_development_assignments, :atom do
      public? false
      transaction? true

      argument :principal_id, :uuid, allow_nil?: false
      argument :expected_assignment_id, :uuid, allow_nil?: false

      run OfficeGraph.Authorization.Actions.ReconcileLocalDevelopmentRoleAssignments
    end
  end

  identities do
    identity :unique_assignment, [:principal_id, :role_id, :organization_id, :workspace_id],
      nils_distinct?: false
  end

  policies do
    policy action(:read) do
      authorize_if expr(
                     principal_id == ^actor(:principal_id) and
                       organization_id == ^actor(:organization_id) and
                       (is_nil(workspace_id) or workspace_id == ^actor(:workspace_id))
                   )
    end

    policy action(:read_for_local_development_login) do
      authorize_if always()
    end
  end
end
