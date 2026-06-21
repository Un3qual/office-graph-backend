defmodule OfficeGraph.Tenancy do
  @moduledoc """
  Public boundary for organizations, workspaces, initiatives, and scopes.
  """

  use Boundary, deps: [OfficeGraph.Repo], exports: []

  alias OfficeGraph.Repo
  alias OfficeGraph.Tenancy.{Initiative, Organization, Workspace, Workstream}

  def ensure_local_scope(attrs) do
    Repo.transaction(fn ->
      organization =
        get_or_create!(
          Organization,
          [slug: attrs[:organization_slug]],
          %{
            name: attrs[:organization_name],
            slug: attrs[:organization_slug]
          }
        )

      workspace =
        get_or_create!(
          Workspace,
          [organization_id: organization.id, slug: attrs[:workspace_slug]],
          %{
            organization_id: organization.id,
            name: attrs[:workspace_name],
            slug: attrs[:workspace_slug]
          }
        )

      initiative =
        get_or_create!(
          Initiative,
          [workspace_id: workspace.id, slug: attrs[:initiative_slug]],
          %{
            organization_id: organization.id,
            workspace_id: workspace.id,
            name: attrs[:initiative_name],
            slug: attrs[:initiative_slug]
          }
        )

      _workstream =
        get_or_create!(
          Workstream,
          [initiative_id: initiative.id, slug: "default"],
          %{
            organization_id: organization.id,
            workspace_id: workspace.id,
            initiative_id: initiative.id,
            name: "Default Workstream",
            slug: "default"
          }
        )

      %{organization: organization, workspace: workspace, initiative: initiative}
    end)
  end

  defp get_or_create!(resource, lookup, attrs) do
    case Ash.get(resource, Map.new(lookup), authorize?: false, not_found_error?: false) do
      {:ok, nil} ->
        attrs =
          attrs
          |> Map.new()
          |> Map.put_new(:id, Ecto.UUID.generate())

        case Ash.create(resource, attrs,
               action: :create,
               authorize?: false,
               return_notifications?: true
             ) do
          {:ok, record, _notifications} ->
            record

          {:ok, record} ->
            record

          {:error, error} ->
            refetch_after_create_error!(resource, lookup, error)
        end

      {:ok, record} ->
        record

      {:error, error} ->
        raise error
    end
  end

  defp refetch_after_create_error!(resource, lookup, error) do
    case Ash.get(resource, Map.new(lookup), authorize?: false, not_found_error?: false) do
      {:ok, nil} -> raise error
      {:ok, record} -> record
      {:error, refetch_error} -> raise refetch_error
    end
  end
end
