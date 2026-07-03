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
        changeset
        |> Ash.Changeset.add_error(
          field: :organization_id,
          message: "target organization_id and workspace_id are required"
        )
        |> Ash.Changeset.add_error(
          field: :workspace_id,
          message: "target organization_id and workspace_id are required"
        )
    end
  end

  defp target_scope(changeset) do
    organization_id =
      Map.get(changeset.attributes || %{}, :organization_id) ||
        Map.get(changeset.data || %{}, :organization_id)

    workspace_id =
      Map.get(changeset.attributes || %{}, :workspace_id) ||
        Map.get(changeset.data || %{}, :workspace_id)

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

          {:ok, _missing_or_cross_scope} ->
            add_missing_or_cross_scope_error(changeset, field)

          {:error, error} ->
            add_lookup_error(changeset, field, error)
        end
    end
  end

  defp reference_spec({schema, opts}) when is_list(opts), do: {schema, opts}
  defp reference_spec(schema), do: {schema, []}

  defp fetch_reference(resource, record_id) do
    resource
    |> Ash.Query.filter(id == ^record_id)
    |> Ash.read_one(authorize?: false)
  end

  defp add_missing_or_cross_scope_error(changeset, field) do
    Ash.Changeset.add_error(
      changeset,
      field: field,
      message: "#{field} must reference an existing record in the target scope"
    )
  end

  defp add_lookup_error(changeset, field, error) do
    Ash.Changeset.add_error(
      changeset,
      field: field,
      message: "#{field} lookup failed: #{format_lookup_error(error)}"
    )
  end

  defp format_lookup_error(%{__exception__: true} = error), do: Exception.message(error)

  defp validate_resource_identity(record, field, reference_opts, changeset) do
    expected_resource_type = Keyword.get(reference_opts, :resource_type)
    expected_resource_id = expected_resource_id(changeset, reference_opts)

    if identity_expectations_match?(record, expected_resource_type, expected_resource_id) do
      changeset
    else
      Ash.Changeset.add_error(
        changeset,
        field: field,
        message: "#{field} must reference a graph item for the target resource"
      )
    end
  end

  defp identity_expectations_match?(record, expected_resource_type, expected_resource_id) do
    type_matches? =
      is_nil(expected_resource_type) or record.resource_type == expected_resource_type

    id_matches? = is_nil(expected_resource_id) or record.resource_id == expected_resource_id

    type_matches? and id_matches?
  end

  defp expected_resource_id(changeset, reference_opts) do
    case Keyword.get(reference_opts, :resource_id) do
      nil -> nil
      field when is_atom(field) -> Ash.Changeset.get_attribute(changeset, field)
    end
  end
end
