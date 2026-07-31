defmodule OfficeGraph.Tenancy do
  @moduledoc """
  Public boundary for organizations, workspaces, initiatives, and scopes.
  """

  use Boundary, deps: [OfficeGraph.CommandSupport], exports: []

  alias OfficeGraph.CommandSupport
  alias OfficeGraph.Tenancy.{Organization, Workspace}

  @identity_constraints ~w[
    organizations_slug_index
    workspaces_organization_id_slug_index
    initiatives_workspace_id_slug_index
    workstreams_initiative_id_slug_index
  ]

  def validate_workspace_scope(organization_id, workspace_id) do
    if is_binary(organization_id) and is_binary(workspace_id) do
      case Ash.get(Workspace, workspace_id,
             authorize?: false,
             not_found_error?: false
           ) do
        {:ok, %Workspace{organization_id: ^organization_id}} -> :ok
        {:ok, _missing_or_mismatched} -> {:error, :invalid_scope}
        {:error, %Ash.Error.Invalid{}} -> {:error, :invalid_scope}
        {:error, _storage_error} -> {:error, :tenancy_storage_unavailable}
      end
    else
      {:error, :invalid_scope}
    end
  end

  def ensure_local_scope(attrs) do
    input =
      attrs
      |> Map.new()
      |> Map.take([
        :organization_name,
        :organization_slug,
        :workspace_name,
        :workspace_slug,
        :initiative_name,
        :initiative_slug
      ])

    case run_ensure_local_scope(input) do
      {:error, %Ash.Error.Invalid{} = error} ->
        if CommandSupport.unique_constraint?(error, @identity_constraints) do
          run_ensure_local_scope(input)
        else
          {:error, error}
        end

      result ->
        result
    end
  end

  defp run_ensure_local_scope(input) do
    Organization
    |> Ash.ActionInput.for_action(:ensure_local_scope, input)
    |> Ash.run_action(authorize?: false)
  end
end
