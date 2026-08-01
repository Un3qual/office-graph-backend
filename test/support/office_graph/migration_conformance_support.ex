defmodule OfficeGraph.TestSupport.MigrationConformanceSupport do
  @moduledoc false

  @table_create_operations [:create, :create_if_not_exists]
  @table_drop_operations [:drop, :drop_if_exists]
  @table_definition_operations [:alter | @table_create_operations]
  @table_lifecycle_operations @table_create_operations ++ @table_drop_operations

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
    functions = migration_functions(ast)

    case Map.get(functions, {:up, 0}) || Map.get(functions, {:change, 0}) do
      definitions when is_list(definitions) ->
        definitions
        |> Enum.map(fn %{body: body, key: key} ->
          expand_local_calls(body, functions, [key])
        end)
        |> block()

      nil ->
        {:__block__, [], []}
    end
  end

  defp migration_functions(ast) do
    {_ast, functions} =
      Macro.prewalk(ast, %{}, fn
        {kind, _meta, [head, body_options]} = node, functions
        when kind in [:def, :defp] and is_list(body_options) ->
          case {local_function_head(head), Keyword.fetch(body_options, :do)} do
            {{key, parameters, guards}, {:ok, body}} ->
              definition = %{body: body, guards: guards, key: key, parameters: parameters}

              functions =
                Map.update(functions, key, [definition], fn definitions ->
                  [definition | definitions]
                end)

              {node, functions}

            _not_a_function_definition ->
              {node, functions}
          end

        node, functions ->
          {node, functions}
      end)

    Map.new(functions, fn {key, definitions} -> {key, Enum.reverse(definitions)} end)
  end

  defp local_function_head({:when, _meta, [head | guards]}) do
    case local_function_head(head) do
      {key, parameters, []} -> {key, parameters, guards}
      nil -> nil
    end
  end

  defp local_function_head({name, _meta, parameters})
       when is_atom(name) and (is_list(parameters) or is_nil(parameters)) do
    parameters = parameters || []
    {{name, length(parameters)}, parameters, []}
  end

  defp local_function_head(_head), do: nil

  defp expand_local_calls({name, metadata, arguments}, functions, call_stack)
       when is_atom(name) and is_list(arguments) do
    key = {name, length(arguments)}

    case Map.get(functions, key) do
      definitions when is_list(definitions) ->
        if key in call_stack do
          {name, metadata, expand_local_calls(arguments, functions, call_stack)}
        else
          definitions
          |> matching_definitions(arguments)
          |> Enum.map(fn %{body: body, parameters: parameters} ->
            body
            |> substitute_parameters(parameters, arguments)
            |> expand_local_calls(functions, [key | call_stack])
          end)
          |> block()
        end

      _not_a_reachable_helper ->
        {name, metadata, expand_local_calls(arguments, functions, call_stack)}
    end
  end

  defp expand_local_calls({name, _metadata, nil} = node, functions, call_stack)
       when is_atom(name) do
    key = {name, 0}

    case Map.get(functions, key) do
      definitions when is_list(definitions) ->
        if key in call_stack do
          node
        else
          definitions
          |> matching_definitions([])
          |> Enum.map(fn %{body: body} ->
            expand_local_calls(body, functions, [key | call_stack])
          end)
          |> block()
        end

      _variable_or_recursive_call ->
        node
    end
  end

  defp expand_local_calls(nodes, functions, call_stack) when is_list(nodes) do
    Enum.map(nodes, &expand_local_calls(&1, functions, call_stack))
  end

  defp expand_local_calls(node, functions, call_stack) when is_tuple(node) do
    node
    |> Tuple.to_list()
    |> expand_local_calls(functions, call_stack)
    |> List.to_tuple()
  end

  defp expand_local_calls(node, _functions, _call_stack), do: node

  defp matching_definitions(definitions, arguments) do
    definitions
    |> Enum.reduce_while([], fn definition, matches ->
      case {patterns_match(definition.parameters, arguments), definition.guards} do
        {:no_match, _guards} ->
          {:cont, matches}

        {:match, []} ->
          {:halt, [definition | matches]}

        {_possible_match, _guards} ->
          {:cont, [definition | matches]}
      end
    end)
    |> Enum.reverse()
  end

  defp patterns_match(patterns, arguments) do
    patterns
    |> Enum.zip(arguments)
    |> Enum.reduce(:match, fn {pattern, argument}, status ->
      combine_match_status(status, pattern_match(pattern, argument))
    end)
  end

  defp pattern_match({:^, _metadata, [_pattern]}, _argument), do: :unknown

  defp pattern_match({name, _metadata, binding_context}, _argument)
       when is_atom(name) and (is_atom(binding_context) or is_nil(binding_context)),
       do: :match

  defp pattern_match({:{}, _pattern_metadata, patterns}, {:{}, _argument_metadata, arguments}) do
    if length(patterns) == length(arguments),
      do: patterns_match(patterns, arguments),
      else: :no_match
  end

  defp pattern_match({left_pattern, right_pattern}, {left_argument, right_argument}) do
    combine_match_status(
      pattern_match(left_pattern, left_argument),
      pattern_match(right_pattern, right_argument)
    )
  end

  defp pattern_match(patterns, arguments) when is_list(patterns) and is_list(arguments) do
    if length(patterns) == length(arguments),
      do: patterns_match(patterns, arguments),
      else: :no_match
  end

  defp pattern_match(pattern, argument)
       when is_atom(pattern) or is_binary(pattern) or is_number(pattern) do
    cond do
      pattern == argument -> :match
      is_atom(argument) or is_binary(argument) or is_number(argument) -> :no_match
      true -> :unknown
    end
  end

  defp pattern_match(_pattern, _argument), do: :unknown

  defp combine_match_status(:no_match, _status), do: :no_match
  defp combine_match_status(_status, :no_match), do: :no_match
  defp combine_match_status(:unknown, _status), do: :unknown
  defp combine_match_status(_status, :unknown), do: :unknown
  defp combine_match_status(:match, :match), do: :match

  defp block([body]), do: body
  defp block(bodies), do: {:__block__, [], bodies}

  defp substitute_parameters(body, parameters, arguments) do
    bindings =
      parameters
      |> Enum.zip(arguments)
      |> Enum.reduce(%{}, fn
        {{name, _metadata, binding_context}, argument}, bindings
        when is_atom(name) and (is_atom(binding_context) or is_nil(binding_context)) ->
          Map.put(bindings, name, argument)

        _unsupported_pattern, bindings ->
          bindings
      end)

    Macro.postwalk(body, fn
      {name, _metadata, binding_context} = node
      when is_atom(name) and (is_atom(binding_context) or is_nil(binding_context)) ->
        Map.get(bindings, name, node)

      node ->
        node
    end)
  end

  defp migration_foreign_key_operations(ast) do
    {_ast, operations} =
      Macro.prewalk(ast, [], fn
        {operation, _meta, [{:table, _table_meta, [table | _table_options]}, [do: block]]} = node,
        operations
        when operation in @table_definition_operations and is_atom(table) ->
          table_operations = table_foreign_key_operations(table, block)
          {node, Enum.reverse(table_operations, operations)}

        {operation, _meta, [{:table, _table_meta, [table | _table_options]} | _drop_options]} =
            node,
        operations
        when operation in @table_drop_operations and is_atom(table) ->
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
        when operation in @table_lifecycle_operations and is_atom(table) ->
          lifecycle_operation =
            if operation in @table_create_operations, do: :create, else: :drop

          {node, [{lifecycle_operation, Atom.to_string(table)} | operations]}

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
