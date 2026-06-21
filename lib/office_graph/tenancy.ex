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
        get_or_insert!(
          Organization,
          [slug: attrs[:organization_slug]],
          Organization.changeset(%Organization{}, %{
            name: attrs[:organization_name],
            slug: attrs[:organization_slug]
          })
        )

      workspace =
        get_or_insert!(
          Workspace,
          [organization_id: organization.id, slug: attrs[:workspace_slug]],
          Workspace.changeset(%Workspace{}, %{
            organization_id: organization.id,
            name: attrs[:workspace_name],
            slug: attrs[:workspace_slug]
          })
        )

      initiative =
        get_or_insert!(
          Initiative,
          [workspace_id: workspace.id, slug: attrs[:initiative_slug]],
          Initiative.changeset(%Initiative{}, %{
            organization_id: organization.id,
            workspace_id: workspace.id,
            name: attrs[:initiative_name],
            slug: attrs[:initiative_slug]
          })
        )

      _workstream =
        get_or_insert!(
          Workstream,
          [initiative_id: initiative.id, slug: "default"],
          Workstream.changeset(%Workstream{}, %{
            organization_id: organization.id,
            workspace_id: workspace.id,
            initiative_id: initiative.id,
            name: "Default Workstream",
            slug: "default"
          })
        )

      %{organization: organization, workspace: workspace, initiative: initiative}
    end)
  end

  defp get_or_insert!(schema, lookup, changeset) do
    Repo.get_by(schema, lookup) || Repo.insert!(changeset)
  end
end
