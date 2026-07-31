defmodule OfficeGraph.TestSupport.MigrationConformanceSupport do
  @moduledoc false

  def migration_tables do
    "priv/repo/migrations/*.exs"
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.reduce(MapSet.new(), fn path, tables ->
      path
      |> File.read!()
      |> migration_forward_ast()
      |> migration_table_operations()
      |> Enum.reduce(tables, &apply_table_operation/2)
    end)
    |> MapSet.to_list()
    |> Enum.sort()
  end

  def migration_foreign_key_relationship_errors(expected_resources) do
    resources_by_table =
      Map.new(expected_resources, fn {table, {_domain, resource}} -> {table, resource} end)

    migration_foreign_keys()
    |> Enum.flat_map(fn {source_table, source_attribute, destination_table, destination_attribute} ->
      with source when not is_nil(source) <- Map.get(resources_by_table, source_table),
           destination when not is_nil(destination) <-
             Map.get(resources_by_table, destination_table),
           source_attribute <- String.to_existing_atom(source_attribute),
           destination_attribute <- String.to_existing_atom(destination_attribute),
           nil <-
             Enum.find(Ash.Resource.Info.relationships(source), fn relationship ->
               match?(%Ash.Resource.Relationships.BelongsTo{}, relationship) and
                 relationship.source_attribute == source_attribute and
                 relationship.destination == destination and
                 relationship.destination_attribute == destination_attribute
             end) do
        [
          "#{source_table}.#{source_attribute} references #{destination_table}.#{destination_attribute} without a matching belongs_to"
        ]
      else
        %Ash.Resource.Relationships.BelongsTo{} -> []
        _table_without_resource -> []
      end
    end)
    |> Enum.sort()
  end

  defp migration_foreign_keys do
    "priv/repo/migrations/*.exs"
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.reduce(%{}, fn path, foreign_keys ->
      path
      |> File.read!()
      |> migration_forward_ast()
      |> migration_foreign_key_operations()
      |> Enum.reduce(foreign_keys, &apply_foreign_key_operation/2)
    end)
    |> Map.values()
    |> Enum.sort()
  end

  defp migration_forward_ast(source) do
    ast = Code.string_to_quoted!(source)

    {_ast, functions} =
      Macro.prewalk(ast, [], fn
        {:def, _meta, [{name, _name_meta, _arguments}, [do: body]]} = node, functions
        when name in [:up, :change] ->
          {node, [{name, body} | functions]}

        node, functions ->
          {node, functions}
      end)

    case Enum.find(functions, &(elem(&1, 0) == :up)) ||
           Enum.find(functions, &(elem(&1, 0) == :change)) do
      {_name, body} -> body
      nil -> {:__block__, [], []}
    end
  end

  defp migration_foreign_key_operations(ast) do
    {_ast, operations} =
      Macro.prewalk(ast, [], fn
        {operation, _meta, [{:table, _table_meta, [table | _table_options]}, [do: block]]} = node,
        operations
        when operation in [:create, :alter] and is_atom(table) ->
          table_operations = table_foreign_key_operations(table, block)
          {node, Enum.reverse(table_operations, operations)}

        {:drop, _meta, [{:table, _table_meta, [table | _table_options]}]} = node, operations
        when is_atom(table) ->
          {node, [{:drop_table, Atom.to_string(table)} | operations]}

        node, operations ->
          {node, operations}
      end)

    Enum.reverse(operations)
  end

  defp migration_table_operations(ast) do
    {_ast, operations} =
      Macro.prewalk(ast, [], fn
        {operation, _meta, [{:table, _table_meta, [table | _table_options]} | _options]} = node,
        operations
        when operation in [:create, :drop] and is_atom(table) ->
          {node, [{operation, Atom.to_string(table)} | operations]}

        node, operations ->
          {node, operations}
      end)

    Enum.reverse(operations)
  end

  defp apply_table_operation({:create, table}, tables), do: MapSet.put(tables, table)
  defp apply_table_operation({:drop, table}, tables), do: MapSet.delete(tables, table)

  defp table_foreign_key_operations(table, block) do
    table = Atom.to_string(table)

    {_block, operations} =
      Macro.prewalk(block, [], fn
        {operation, _meta,
         [
           column,
           {:references, _references_meta, [destination | reference_options]}
           | _column_options
         ]} = node,
        operations
        when operation in [:add, :modify] and is_atom(column) and is_atom(destination) ->
          destination_attribute =
            reference_options
            |> List.flatten()
            |> Keyword.get(:column, :id)

          foreign_key = {
            table,
            Atom.to_string(column),
            Atom.to_string(destination),
            Atom.to_string(destination_attribute)
          }

          {node, [{:put, foreign_key} | operations]}

        {:remove, _meta, [column | _options]} = node, operations when is_atom(column) ->
          {node, [{:remove, table, Atom.to_string(column)} | operations]}

        node, operations ->
          {node, operations}
      end)

    Enum.reverse(operations)
  end

  defp apply_foreign_key_operation({:put, foreign_key}, foreign_keys) do
    {table, column, _destination_table, _destination_column} = foreign_key
    Map.put(foreign_keys, {table, column}, foreign_key)
  end

  defp apply_foreign_key_operation({:remove, table, column}, foreign_keys),
    do: Map.delete(foreign_keys, {table, column})

  defp apply_foreign_key_operation({:drop_table, table}, foreign_keys) do
    Map.reject(foreign_keys, fn {{source_table, _column}, _foreign_key} ->
      source_table == table
    end)
  end
end
