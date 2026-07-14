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
  def reply_to_review(_request, _credential), do: {:error, :unsupported_fixture}

  @impl true
  def update_check(_request, _credential), do: {:error, :unsupported_fixture}

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
