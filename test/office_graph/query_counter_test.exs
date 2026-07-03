defmodule OfficeGraph.QueryCounterTest do
  use ExUnit.Case, async: true

  alias OfficeGraph.QueryCounter

  test "source_count matches exact query sources instead of table-name prefixes" do
    queries = [
      %{source: nil, query: ~s(SELECT * FROM "document_blocks")},
      %{source: nil, query: ~s(SELECT * FROM "document")},
      %{source: "document", query: nil}
    ]

    assert QueryCounter.source_count(queries, "document") == 2
  end
end
