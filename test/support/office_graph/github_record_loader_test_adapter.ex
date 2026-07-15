defmodule OfficeGraph.GitHubIntegration.RecordLoaderTestAdapter do
  @moduledoc false

  @behaviour OfficeGraph.GitHubIntegration.RecordLoader

  @table __MODULE__

  def put(responses) when is_map(responses) do
    ensure_table!()
    :ets.delete_all_objects(@table)
    :ets.insert(@table, Enum.to_list(responses))
    :ok
  end

  @impl true
  def get(resource, id, opts) do
    ensure_table!()

    case :ets.lookup(@table, resource) do
      [{^resource, response}] -> response
      [] -> Ash.get(resource, id, opts)
    end
  end

  @impl true
  def read_one(resource, query, opts) do
    ensure_table!()

    case :ets.lookup(@table, resource) do
      [{^resource, response}] -> response
      [] -> Ash.read_one(query, opts)
    end
  end

  defp ensure_table! do
    case :ets.whereis(@table) do
      :undefined ->
        try do
          :ets.new(@table, [:named_table, :public, :set])
        rescue
          ArgumentError -> @table
        end

      table ->
        table
    end
  end
end
