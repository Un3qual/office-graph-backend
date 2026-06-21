defmodule OfficeGraph.WorkGraph.Changes.ValidateSameScopeReferences do
  @moduledoc false

  use Ash.Resource.Change

  require Ash.Query

  @impl true
  def change(changeset, opts, _context) do
    with {:ok, organization_id, workspace_id} <- target_scope(changeset) do
      opts
      |> Keyword.fetch!(:references)
      |> Enum.reduce(changeset, fn {field, reference}, changeset ->
        validate_reference(changeset, field, reference, organization_id, workspace_id)
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

  defp validate_reference(changeset, field, reference, organization_id, workspace_id) do
    {resource, reference_opts} = reference_spec(reference)

    case Ash.Changeset.get_attribute(changeset, field) do
      nil ->
        changeset

      id ->
        case fetch_reference(resource, id) do
          {:ok, %{organization_id: ^organization_id, workspace_id: ^workspace_id} = record} ->
            validate_resource_identity(record, field, reference_opts, changeset)

          _missing_or_cross_scope ->
            Ash.Changeset.add_error(
              changeset,
              field: field,
              message: "#{field} must reference an existing record in the target scope"
            )
        end
    end
  end

  defp reference_spec({schema, opts}) when is_list(opts), do: {schema, opts}
  defp reference_spec(schema), do: {schema, []}

  defp fetch_reference(resource, record_id) do
    resource
    |> Ash.Query.filter(id == ^record_id)
    |> Ash.read_one(authorize?: false)
  rescue
    _error -> {:error, :unsupported_reference}
  end

  defp validate_resource_identity(record, field, reference_opts, changeset) do
    expected_resource_type = Keyword.get(reference_opts, :resource_type)
    expected_resource_id = expected_resource_id(changeset, reference_opts)

    cond do
      is_nil(expected_resource_type) and is_nil(expected_resource_id) ->
        changeset

      record.resource_type == expected_resource_type and
          record.resource_id == expected_resource_id ->
        changeset

      true ->
        Ash.Changeset.add_error(
          changeset,
          field: field,
          message: "#{field} must reference a graph item for the target resource"
        )
    end
  end

  defp expected_resource_id(changeset, reference_opts) do
    case Keyword.get(reference_opts, :resource_id) do
      nil -> nil
      field when is_atom(field) -> Ash.Changeset.get_attribute(changeset, field)
    end
  end
end
