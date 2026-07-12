defmodule OfficeGraph.WorkGraph.Changes.ValidateSameScopeReferences do
  @moduledoc false

  use Ash.Resource.Change

  require Ash.Query
  require Logger

  @impl true
  def change(changeset, opts, context) do
    [changeset] = batch_change([changeset], opts, context)
    changeset
  end

  @impl true
  def batch_change(changesets, opts, _context) do
    references = Keyword.fetch!(opts, :references)
    loaded_references = load_references(changesets, references)

    Enum.map(
      changesets,
      &validate_changeset(&1, references, loaded_references)
    )
  end

  defp validate_changeset(changeset, references, loaded_references) do
    with {:ok, organization_id, workspace_id} <- target_scope(changeset) do
      Enum.reduce(references, changeset, fn {field, reference}, changeset ->
        validate_reference(
          changeset,
          field,
          reference,
          organization_id,
          workspace_id,
          loaded_references
        )
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

  defp load_references(changesets, references) do
    references
    |> Enum.group_by(
      fn {_field, reference} -> reference |> reference_spec() |> elem(0) end,
      fn {field, _reference} -> field end
    )
    |> Map.new(fn {resource, fields} ->
      ids = reference_ids(changesets, fields)
      {resource, fetch_references(resource, ids)}
    end)
  end

  defp reference_ids(changesets, fields) do
    changesets
    |> Enum.filter(&match?({:ok, _, _}, target_scope(&1)))
    |> Enum.flat_map(fn changeset ->
      Enum.map(fields, &Ash.Changeset.get_attribute(changeset, &1))
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
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

  defp validate_reference(
         changeset,
         field,
         reference,
         organization_id,
         workspace_id,
         loaded_references
       ) do
    {resource, reference_opts} = reference_spec(reference)

    case Ash.Changeset.get_attribute(changeset, field) do
      nil ->
        changeset

      id ->
        case loaded_reference(loaded_references, resource, id) do
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

  defp fetch_references(_resource, []), do: {:ok, %{}}

  defp fetch_references(resource, record_ids) do
    resource
    |> Ash.Query.filter(id in ^record_ids)
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, records} -> {:ok, Map.new(records, &{&1.id, &1})}
      {:error, error} -> {:error, error}
    end
  end

  defp loaded_reference(loaded_references, resource, id) do
    case Map.fetch!(loaded_references, resource) do
      {:ok, records_by_id} -> {:ok, Map.get(records_by_id, id)}
      {:error, error} -> {:error, error}
    end
  end

  defp add_missing_or_cross_scope_error(changeset, field) do
    Ash.Changeset.add_error(
      changeset,
      field: field,
      message: "#{field} must reference an existing record in the target scope"
    )
  end

  defp add_lookup_error(changeset, field, error) do
    Logger.warning(fn ->
      "same-scope reference lookup failed field=#{inspect(field)} error=#{inspect(error)}"
    end)

    Ash.Changeset.add_error(
      changeset,
      field: field,
      message: "#{field} could not be validated"
    )
  end

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
