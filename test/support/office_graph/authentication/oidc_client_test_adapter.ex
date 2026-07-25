defmodule OfficeGraph.Authentication.OidcClient.TestAdapter do
  @moduledoc false

  @behaviour OfficeGraph.Authentication.OidcClient

  @table __MODULE__

  def put(responses) when is_map(responses) do
    ensure_table!()
    :ets.delete_all_objects(@table)
    :ets.insert(@table, Enum.to_list(responses))
    :ok
  end

  def authorization_uri(request), do: respond(:authorization_uri, request)
  def exchange(request), do: respond(:exchange, request)
  def logout_uri(request), do: respond(:logout_uri, request)

  def request(operation) do
    ensure_table!()

    case :ets.lookup(@table, {:request, operation}) do
      [{{:request, ^operation}, request}] -> request
      [] -> nil
    end
  end

  def calls(operation) do
    ensure_table!()

    case :ets.lookup(@table, {:calls, operation}) do
      [{{:calls, ^operation}, count}] -> count
      [] -> 0
    end
  end

  defp respond(operation, request) do
    ensure_table!()
    :ets.insert(@table, {{:request, operation}, request})
    :ets.update_counter(@table, {:calls, operation}, {2, 1}, {{:calls, operation}, 0})

    case :ets.lookup(@table, operation) do
      [{^operation, response}] -> response
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
