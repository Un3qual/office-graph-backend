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
    Repo.get_or_insert!(resource, lookup, attrs, fn resource, _attrs ->
      insert_contract!(resource)
    end)
  end

  defp insert_contract!(Organization), do: {"organizations", [:slug], [:id]}

  defp insert_contract!(Workspace) do
    {"workspaces", [:organization_id, :slug], [:id, :organization_id]}
  end

  defp insert_contract!(Initiative) do
    {"initiatives", [:workspace_id, :slug], [:id, :organization_id, :workspace_id]}
  end

  defp insert_contract!(Workstream) do
    {"workstreams", [:initiative_id, :slug],
     [:id, :organization_id, :workspace_id, :initiative_id]}
  end
end
