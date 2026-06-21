defmodule OfficeGraph.WorkGraph.Changes.ValidateRelationshipEndpoints do
  @moduledoc false

  use Ash.Resource.Change

  alias OfficeGraph.WorkGraph.GraphItem

  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    source_id = Ash.Changeset.get_attribute(changeset, :source_item_id)
    target_id = Ash.Changeset.get_attribute(changeset, :target_item_id)

    if is_nil(source_id) or is_nil(target_id) do
      changeset
    else
      validate_endpoints(changeset, source_id, target_id)
    end
  end

  defp validate_endpoints(changeset, source_id, target_id) do
    with {:ok, by_id} <- fetch_graph_items([source_id, target_id]),
         {:ok, source} <- fetch_endpoint(by_id, source_id),
         {:ok, target} <- fetch_endpoint(by_id, target_id),
         true <- same_scope?(source, target) do
      changeset
    else
      {:error, :missing_endpoint} ->
        add_endpoint_error(changeset)

      false ->
        add_endpoint_error(changeset)

      {:error, error} ->
        Ash.Changeset.add_error(
          changeset,
          field: :source_item_id,
          message: "relationship endpoint lookup failed: #{inspect(error)}"
        )
    end
  end

  defp fetch_graph_items(ids) do
    GraphItem
    |> Ash.Query.filter(id in ^Enum.uniq(ids))
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, records} -> {:ok, Map.new(records, &{&1.id, &1})}
      {:error, error} -> {:error, error}
    end
  end

  defp fetch_endpoint(by_id, id) do
    case Map.fetch(by_id, id) do
      {:ok, record} -> {:ok, record}
      :error -> {:error, :missing_endpoint}
    end
  end

  defp same_scope?(source, target) do
    source.organization_id == target.organization_id and
      source.workspace_id == target.workspace_id
  end

  defp add_endpoint_error(changeset) do
    changeset
    |> Ash.Changeset.add_error(
      field: :source_item_id,
      message: "relationship endpoints must exist in the same scope"
    )
    |> Ash.Changeset.add_error(
      field: :target_item_id,
      message: "relationship endpoints must exist in the same scope"
    )
  end
end
