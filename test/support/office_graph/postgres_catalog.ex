defmodule OfficeGraph.TestSupport.PostgresCatalog do
  @moduledoc false

  alias OfficeGraph.Repo

  def table_exists?(table) when is_binary(table) do
    %{rows: [[exists?]]} =
      Repo.query!("SELECT to_regclass(current_schema() || '.' || $1) IS NOT NULL", [table])

    exists?
  end

  def columns(table) when is_binary(table) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = current_schema() AND table_name = $1
        ORDER BY ordinal_position
        """,
        [table]
      )

    Enum.map(rows, fn [column] -> column end)
  end

  def column_exists?(table, column) when is_binary(table) and is_binary(column) do
    %{rows: [[exists?]]} =
      Repo.query!(
        """
        SELECT EXISTS (
          SELECT 1
          FROM information_schema.columns
          WHERE table_schema = current_schema()
            AND table_name = $1
            AND column_name = $2
        )
        """,
        [table, column]
      )

    exists?
  end

  def column_nullable?(table, column) when is_binary(table) and is_binary(column) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT is_nullable
        FROM information_schema.columns
        WHERE table_schema = current_schema()
          AND table_name = $1
          AND column_name = $2
        """,
        [table, column]
      )

    rows == [["YES"]]
  end

  def constraint_exists?(name) when is_binary(name) do
    %{rows: [[exists?]]} =
      Repo.query!(
        """
        SELECT EXISTS (
          SELECT 1
          FROM pg_constraint AS constraint_row
          JOIN pg_namespace AS namespace ON namespace.oid = constraint_row.connamespace
          WHERE namespace.nspname = current_schema() AND constraint_row.conname = $1
        )
        """,
        [name]
      )

    exists?
  end

  def index_exists?(name) when is_binary(name), do: not is_nil(index_definition(name))

  def index_columns(name) when is_binary(name) do
    case index_definition(name) do
      %{columns: columns} -> columns
      nil -> []
    end
  end

  def index_definition(name) when is_binary(name) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT
          ARRAY(
            SELECT pg_get_indexdef(index_row.indexrelid, position, true)
            FROM generate_series(1, index_row.indnkeyatts) AS position
            ORDER BY position
          ),
          index_row.indisunique,
          pg_get_expr(index_row.indpred, index_row.indrelid),
          index_row.indnullsnotdistinct
        FROM pg_index AS index_row
        JOIN pg_class AS index_class ON index_class.oid = index_row.indexrelid
        JOIN pg_namespace AS namespace ON namespace.oid = index_class.relnamespace
        WHERE namespace.nspname = current_schema() AND index_class.relname = $1
        """,
        [name]
      )

    case rows do
      [[columns, unique?, predicate, nulls_not_distinct?]] ->
        %{
          columns: columns,
          unique?: unique?,
          predicate: predicate,
          nulls_not_distinct?: nulls_not_distinct?
        }

      [] ->
        nil
    end
  end
end
