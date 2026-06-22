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

        insert_then_fetch!(resource, lookup, attrs)

      {:ok, record} ->
        record

      {:error, error} ->
        raise error
    end
  end

  defp insert_then_fetch!(resource, lookup, attrs) do
    {table, conflict_target, uuid_fields} = insert_contract!(resource)
    now = DateTime.utc_now()

    insert_attrs =
      attrs
      |> Map.put(:inserted_at, now)
      |> Map.put(:updated_at, now)
      |> dump_uuid_fields(uuid_fields)

    Repo.insert_all(table, [insert_attrs],
      on_conflict: :nothing,
      conflict_target: conflict_target
    )

    case Ash.get(resource, Map.new(lookup), authorize?: false, not_found_error?: false) do
      {:ok, nil} -> raise "#{inspect(resource)} not found after create"
      {:ok, record} -> record
      {:error, error} -> raise error
    end
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

  defp dump_uuid_fields(attrs, fields) do
    Enum.reduce(fields, attrs, fn field, acc ->
      Map.update!(acc, field, &Ecto.UUID.dump!/1)
    end)
  end
end
