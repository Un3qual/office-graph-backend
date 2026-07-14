defmodule OfficeGraph.GitHubIntegration.Adapter.TestAdapter do
  @moduledoc false

  @behaviour OfficeGraph.GitHubIntegration.Adapter
  @table __MODULE__

  def put(responses) when is_map(responses) do
    ensure_table!()
    :ets.delete_all_objects(@table)
    :ets.insert(@table, Enum.to_list(responses))
    :ok
  end

  @impl true
  def fetch(%{object_type: object_type, object_id: object_id}) do
    ensure_table!()

    case :ets.lookup(@table, {object_type, object_id}) do
      [{{^object_type, ^object_id}, response}] -> response
      [] -> {:error, :fixture_not_found}
    end
  end

  @impl true
  def reply_to_review(%{target_node_id: node_id}, _credential) do
    fetch_outbound("review_reply", node_id)
  end

  @impl true
  def update_check(%{target_node_id: node_id}, _credential) do
    fetch_outbound("check_update", node_id)
  end

  def calls(kind, node_id) do
    ensure_table!()

    case :ets.lookup(@table, {:calls, kind, node_id}) do
      [{{:calls, ^kind, ^node_id}, count}] -> count
      [] -> 0
    end
  end

  defp fetch_outbound(kind, node_id) do
    ensure_table!()
    :ets.update_counter(@table, {:calls, kind, node_id}, {2, 1}, {{:calls, kind, node_id}, 0})

    case :ets.lookup(@table, {kind, node_id}) do
      [{{^kind, ^node_id}, response}] -> response
      [] -> {:error, :fixture_not_found}
    end
  end

  defp ensure_table! do
    case :ets.whereis(@table) do
      :undefined ->
        try do
          :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
        rescue
          ArgumentError -> @table
        end

      table ->
        table
    end
  end
end
