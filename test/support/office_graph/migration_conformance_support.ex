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
        |> resolve_local_bindings()

      nil ->
        {:__block__, [], []}
    end
  end

  defp migration_functions(ast) do
    {_ast, functions} =
      Macro.prewalk(ast, %{}, fn
        {kind, _meta, [head, body_options]} = node, functions
        when kind in [:def, :defp, :defmacro, :defmacrop] and is_list(body_options) ->
          case {local_function_head(head), Keyword.fetch(body_options, :do)} do
            {{key, parameters, guards}, {:ok, body}} ->
              functions =
                key
                |> local_function_definitions(kind, parameters, guards, body)
                |> Enum.reduce(functions, fn definition, functions ->
                  Map.update(functions, definition.key, [definition], fn definitions ->
                    [definition | definitions]
                  end)
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

  defp local_function_definitions({name, _arity} = key, kind, parameters, guards, body) do
    {parameters, defaults} = normalize_default_parameters(parameters)

    definition = %{
      body: body,
      guards: guards,
      key: key,
      kind: definition_kind(kind),
      parameters: parameters
    }

    defaults_by_index = Map.new(defaults)

    wrappers =
      defaults
      |> Enum.with_index(1)
      |> Enum.map(fn {_default, omitted_count} ->
        omitted_indexes =
          defaults
          |> Enum.take(-omitted_count)
          |> MapSet.new(fn {index, _default} -> index end)

        wrapper_parameters =
          parameters
          |> Enum.with_index()
          |> Enum.reject(fn {_parameter, index} -> MapSet.member?(omitted_indexes, index) end)
          |> Enum.map(&elem(&1, 0))

        call_arguments =
          parameters
          |> Enum.with_index()
          |> Enum.map(fn {parameter, index} ->
            if MapSet.member?(omitted_indexes, index),
              do: Map.fetch!(defaults_by_index, index),
              else: parameter
          end)

        %{
          body: {name, [], call_arguments},
          guards: [],
          key: {name, length(wrapper_parameters)},
          kind: :function,
          parameters: wrapper_parameters
        }
      end)

    [definition | wrappers]
  end

  defp normalize_default_parameters(parameters) do
    parameters
    |> Stream.with_index()
    |> Enum.reduce({[], []}, fn
      {{:\\, _metadata, [parameter, default]}, index}, {parameters, defaults} ->
        {[parameter | parameters], [{index, default} | defaults]}

      {parameter, _index}, {parameters, defaults} ->
        {[parameter | parameters], defaults}
    end)
    |> then(fn {parameters, defaults} ->
      {Enum.reverse(parameters), Enum.reverse(defaults)}
    end)
  end

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
          |> Enum.map(&expand_definition(&1, functions, [key | call_stack]))
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
          |> Enum.map(&expand_definition(&1, functions, [key | call_stack]))
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

  defp expand_definition(
         %{bindings: bindings, body: body, kind: :function},
         functions,
         call_stack
       ) do
    body
    |> substitute_bindings(bindings)
    |> resolve_local_bindings()
    |> expand_local_calls(functions, call_stack)
  end

  defp expand_definition(%{bindings: bindings, body: body, kind: :macro}, functions, call_stack) do
    body
    |> expand_macro_body(bindings)
    |> expand_local_calls(functions, call_stack)
  end

  defp expand_macro_body({:quote, _metadata, arguments}, bindings) when is_list(arguments) do
    arguments
    |> quoted_body()
    |> Macro.postwalk(fn
      {:unquote, _metadata, [expression]} -> substitute_bindings(expression, bindings)
      node -> node
    end)
  end

  defp expand_macro_body(body, bindings), do: substitute_bindings(body, bindings)

  defp quoted_body([options]) when is_list(options), do: Keyword.get(options, :do)
  defp quoted_body(options), do: Keyword.get(options, :do)

  defp definition_kind(kind) when kind in [:defmacro, :defmacrop], do: :macro
  defp definition_kind(kind) when kind in [:def, :defp], do: :function

  defp matching_definitions(definitions, arguments) do
    definitions
    |> Enum.reduce_while([], fn definition, matches ->
      {pattern_status, bindings} = match_parameters(definition.parameters, arguments)
      guard_status = guards_match(definition.guards, bindings)
      definition = Map.put(definition, :bindings, bindings)

      case {pattern_status, guard_status} do
        {:no_match, _guard_status} ->
          {:cont, matches}

        {_pattern_status, :no_match} ->
          {:cont, matches}

        {:match, :match} ->
          {:halt, [definition | matches]}

        {_possible_pattern, _possible_guard} ->
          {:cont, [definition | matches]}
      end
    end)
    |> Enum.reverse()
  end

  defp match_parameters(patterns, arguments) do
    match_parameter_elements(patterns, arguments, %{})
  end

  defp match_parameter_pattern({:^, _metadata, [_pattern]}, _argument, bindings),
    do: {:unknown, bindings}

  defp match_parameter_pattern({name, _metadata, binding_context}, argument, bindings)
       when is_atom(name) and (is_atom(binding_context) or is_nil(binding_context)) do
    cond do
      name == :_ ->
        {:match, bindings}

      Map.has_key?(bindings, name) ->
        {repeated_binding_status(Map.fetch!(bindings, name), argument), bindings}

      true ->
        {:match, Map.put(bindings, name, argument)}
    end
  end

  defp match_parameter_pattern(
         {:{}, _pattern_metadata, patterns},
         {:{}, _argument_metadata, arguments},
         bindings
       ) do
    if length(patterns) == length(arguments),
      do: match_parameter_elements(patterns, arguments, bindings),
      else: {:no_match, bindings}
  end

  defp match_parameter_pattern(
         {left_pattern, right_pattern},
         {left_argument, right_argument},
         bindings
       ) do
    {left_status, bindings} =
      match_parameter_pattern(left_pattern, left_argument, bindings)

    {right_status, bindings} =
      match_parameter_pattern(right_pattern, right_argument, bindings)

    {combine_match_status(left_status, right_status), bindings}
  end

  defp match_parameter_pattern(patterns, arguments, bindings)
       when is_list(patterns) and is_list(arguments) do
    if length(patterns) == length(arguments),
      do: match_parameter_elements(patterns, arguments, bindings),
      else: {:no_match, bindings}
  end

  defp match_parameter_pattern(pattern, argument, bindings)
       when is_atom(pattern) or is_binary(pattern) or is_number(pattern) do
    status =
      cond do
        pattern == argument -> :match
        is_atom(argument) or is_binary(argument) or is_number(argument) -> :no_match
        true -> :unknown
      end

    {status, bindings}
  end

  defp match_parameter_pattern(_pattern, _argument, bindings), do: {:unknown, bindings}

  defp match_parameter_elements(patterns, arguments, bindings) do
    patterns
    |> Enum.zip(arguments)
    |> Enum.reduce({:match, bindings}, fn {pattern, argument}, {status, bindings} ->
      {next_status, bindings} = match_parameter_pattern(pattern, argument, bindings)
      {combine_match_status(status, next_status), bindings}
    end)
  end

  defp combine_match_status(:no_match, _status), do: :no_match
  defp combine_match_status(_status, :no_match), do: :no_match
  defp combine_match_status(:unknown, _status), do: :unknown
  defp combine_match_status(_status, :unknown), do: :unknown
  defp combine_match_status(:match, :match), do: :match

  defp repeated_binding_status(existing, argument) do
    if Macro.to_string(existing) == Macro.to_string(argument) do
      :match
    else
      with {:known, existing} <- static_guard_value(existing),
           {:known, argument} <- static_guard_value(argument) do
        if existing === argument, do: :match, else: :no_match
      end
    end
  end

  defp block([body]), do: body
  defp block(bodies), do: {:__block__, [], bodies}

  defp substitute_bindings(body, bindings) do
    Macro.postwalk(body, fn
      {name, _metadata, binding_context} = node
      when is_atom(name) and (is_atom(binding_context) or is_nil(binding_context)) ->
        Map.get(bindings, name, node)

      node ->
        node
    end)
  end

  defp resolve_local_bindings(ast) do
    {ast, _bindings} = resolve_local_bindings(ast, %{})
    ast
  end

  defp resolve_local_bindings({:__block__, metadata, expressions}, bindings) do
    {expressions, bindings} =
      Enum.map_reduce(expressions, bindings, &resolve_local_bindings/2)

    {{:__block__, metadata, expressions}, bindings}
  end

  defp resolve_local_bindings({:=, _metadata, [pattern, value]}, bindings) do
    resolved_value = substitute_bindings(value, bindings)

    bindings =
      case match_parameter_pattern(pattern, resolved_value, %{}) do
        {:no_match, _new_bindings} -> bindings
        {_status, new_bindings} -> Map.merge(bindings, new_bindings)
      end

    {resolved_value, bindings}
  end

  defp resolve_local_bindings(nodes, bindings) when is_list(nodes) do
    nodes =
      Enum.map(nodes, fn node ->
        {node, _child_bindings} = resolve_local_bindings(node, bindings)
        node
      end)

    {nodes, bindings}
  end

  defp resolve_local_bindings(node, bindings) when is_tuple(node) do
    node =
      node
      |> Tuple.to_list()
      |> Enum.map(fn child ->
        {child, _child_bindings} = resolve_local_bindings(child, bindings)
        child
      end)
      |> List.to_tuple()
      |> substitute_bindings(bindings)

    {node, bindings}
  end

  defp resolve_local_bindings(node, bindings), do: {node, bindings}

  defp guards_match([], _bindings), do: :match

  defp guards_match(guards, bindings) do
    Enum.reduce(guards, :match, fn guard, status ->
      guard_status = guard |> substitute_bindings(bindings) |> static_guard_result()
      combine_guard_and(status, guard_status)
    end)
  end

  defp static_guard_result(true), do: :match
  defp static_guard_result(false), do: :no_match
  defp static_guard_result(nil), do: :no_match

  defp static_guard_result({:when, _metadata, guards}) when is_list(guards) do
    Enum.reduce(guards, :no_match, fn guard, status ->
      combine_guard_or(status, static_guard_result(guard))
    end)
  end

  defp static_guard_result({operation, _metadata, [left, right]})
       when operation in [:==, :===, :!=, :!==] do
    with {:known, left} <- static_guard_value(left),
         {:known, right} <- static_guard_value(right) do
      result =
        case operation do
          :== -> left == right
          :=== -> left === right
          :!= -> left != right
          :!== -> left !== right
        end

      if result, do: :match, else: :no_match
    end
  end

  defp static_guard_result(_guard), do: :unknown

  defp static_guard_value(value)
       when is_atom(value) or is_binary(value) or is_number(value),
       do: {:known, value}

  defp static_guard_value(values) when is_list(values) do
    static_guard_values(values, [])
  end

  defp static_guard_value({:{}, _metadata, values}) do
    case static_guard_values(values, []) do
      {:known, values} -> {:known, List.to_tuple(values)}
      :unknown -> :unknown
    end
  end

  defp static_guard_value({left, right}) do
    with {:known, left} <- static_guard_value(left),
         {:known, right} <- static_guard_value(right),
         do: {:known, {left, right}}
  end

  defp static_guard_value(_value), do: :unknown

  defp static_guard_values([], values), do: {:known, Enum.reverse(values)}

  defp static_guard_values([value | remaining], values) do
    case static_guard_value(value) do
      {:known, value} -> static_guard_values(remaining, [value | values])
      :unknown -> :unknown
    end
  end

  defp combine_guard_and(:no_match, _status), do: :no_match
  defp combine_guard_and(_status, :no_match), do: :no_match
  defp combine_guard_and(:unknown, _status), do: :unknown
  defp combine_guard_and(_status, :unknown), do: :unknown
  defp combine_guard_and(:match, :match), do: :match

  defp combine_guard_or(:match, _status), do: :match
  defp combine_guard_or(_status, :match), do: :match
  defp combine_guard_or(:unknown, _status), do: :unknown
  defp combine_guard_or(_status, :unknown), do: :unknown
  defp combine_guard_or(:no_match, :no_match), do: :no_match

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
