defmodule OfficeGraph.WorkGraph.Changes.ValidateSameScopeReferences do
  @moduledoc false

  use Ash.Resource.Change

  alias OfficeGraph.Repo

  @impl true
  def change(changeset, opts, _context) do
    with {:ok, organization_id, workspace_id} <- target_scope(changeset) do
      opts
      |> Keyword.fetch!(:references)
      |> Enum.reduce(changeset, fn {field, schema}, changeset ->
        validate_reference(changeset, field, schema, organization_id, workspace_id)
      end)
    else
      :error ->
        Ash.Changeset.add_error(
          changeset,
          field: :organization_id,
          message: "target organization_id and workspace_id are required"
        )
    end
  end

  defp target_scope(changeset) do
    organization_id = Ash.Changeset.get_attribute(changeset, :organization_id)
    workspace_id = Ash.Changeset.get_attribute(changeset, :workspace_id)

    if is_nil(organization_id) or is_nil(workspace_id) do
      :error
    else
      {:ok, organization_id, workspace_id}
    end
  end

  defp validate_reference(changeset, field, schema, organization_id, workspace_id) do
    case Ash.Changeset.get_attribute(changeset, field) do
      nil ->
        changeset

      id ->
        case Repo.get(schema, id) do
          %{organization_id: ^organization_id, workspace_id: ^workspace_id} ->
            changeset

          _missing_or_cross_scope ->
            Ash.Changeset.add_error(
              changeset,
              field: field,
              message: "#{field} must reference an existing record in the target scope"
            )
        end
    end
  end
end
