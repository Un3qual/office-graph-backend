defmodule OfficeGraph.QueryCounter do
  @moduledoc false

  @repo_query_event [:office_graph, :repo, :query]

  def count(fun) when is_function(fun, 0) do
    owner = self()
    ref = make_ref()
    handler_id = {__MODULE__, owner, ref}

    :ok =
      :telemetry.attach(
        handler_id,
        @repo_query_event,
        fn _event, measurements, metadata, _config ->
          send(owner, {ref, query_entry(measurements, metadata)})
        end,
        nil
      )

    try do
      result = fun.()
      queries = collect_queries(ref, [])

      {result, queries}
    after
      :telemetry.detach(handler_id)
    end
  end

  def source_count(queries, source) when is_binary(source) do
    Enum.count(queries, &query_source?(&1, source))
  end

  defp query_entry(measurements, metadata) do
    %{
      query: Map.get(metadata, :query),
      source: Map.get(metadata, :source),
      result: Map.get(metadata, :result),
      total_time: Map.get(measurements, :total_time)
    }
  end

  defp collect_queries(ref, acc) do
    receive do
      {^ref, query} -> collect_queries(ref, [query | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp query_source?(%{source: source}, source), do: true

  defp query_source?(%{query: query}, source) when is_binary(query) do
    String.contains?(query, ~s("#{source}"))
  end

  defp query_source?(_query, _source), do: false
end
