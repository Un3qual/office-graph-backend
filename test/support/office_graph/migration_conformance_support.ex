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
    |> Enum.flat_map(&MapSet.to_list/1)
    |> Enum.map(fn {source_table, source_attribute, destination_table, destination_attribute,
                    _constraint_name} ->
      {source_table, source_attribute, destination_table, destination_attribute}
    end)
    |> Enum.uniq()
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
    {functions, _attributes} =
      ast
      |> migration_module_body()
      |> module_expressions()
      |> Enum.reduce({%{}, %{}}, fn
        {:@, _metadata, [{name, _name_metadata, [value]}]}, {functions, attributes}
        when is_atom(name) ->
          attributes = Map.put(attributes, name, resolve_module_attributes(value, attributes))
          {functions, attributes}

        {kind, _meta, [head, body_options]}, {functions, attributes}
        when kind in [:def, :defp, :defmacro, :defmacrop] and is_list(body_options) ->
          head = resolve_module_attributes(head, attributes)

          case {local_function_head(head), Keyword.fetch(body_options, :do)} do
            {{key, parameters, guards}, {:ok, body}} ->
              functions =
                key
                |> local_function_definitions(
                  kind,
                  parameters,
                  guards,
                  resolve_module_attributes(body, attributes)
                )
                |> Enum.reduce(functions, fn definition, functions ->
                  Map.update(functions, definition.key, [definition], fn definitions ->
                    [definition | definitions]
                  end)
                end)

              {functions, attributes}

            _not_a_function_definition ->
              {functions, attributes}
          end

        _module_expression, accumulator ->
          accumulator
      end)

    Map.new(functions, fn {key, definitions} -> {key, Enum.reverse(definitions)} end)
  end

  defp migration_module_body({:__block__, _metadata, expressions}) do
    Enum.find_value(expressions, &migration_module_body/1)
  end

  defp migration_module_body({:defmodule, _metadata, [_module, [do: body]]}) do
    if uses_ecto_migration?(body), do: body
  end

  defp migration_module_body(_ast), do: nil

  defp uses_ecto_migration?(body) do
    body
    |> module_expressions()
    |> Enum.reduce_while(%{}, fn
      {:alias, _metadata, arguments}, aliases ->
        {:cont, put_module_aliases(aliases, arguments)}

      {:use, _metadata, [target | _options]}, aliases ->
        if resolve_module_name(target, aliases) == "Ecto.Migration",
          do: {:halt, true},
          else: {:cont, aliases}

      _module_expression, aliases ->
        {:cont, aliases}
    end)
    |> Kernel.==(true)
  end

  defp module_expressions({:__block__, _metadata, expressions}), do: expressions
  defp module_expressions(nil), do: []
  defp module_expressions(expression), do: [expression]

  defp put_module_aliases(aliases, [target]),
    do: apply_module_aliases(aliases, target, [])

  defp put_module_aliases(aliases, [target, options]) when is_list(options),
    do: apply_module_aliases(aliases, target, options)

  defp put_module_aliases(aliases, _arguments), do: aliases

  defp apply_module_aliases(aliases, target, options) do
    target
    |> module_alias_target_names()
    |> Enum.reduce(aliases, fn target_name, aliases ->
      resolved_target = resolve_module_name(target_name, aliases)

      alias_name =
        case Keyword.get(options, :as) do
          nil -> target_name |> String.split(".") |> List.last()
          explicit_alias -> module_name(explicit_alias)
        end

      if is_binary(alias_name) and is_binary(resolved_target),
        do: Map.put(aliases, alias_name, resolved_target),
        else: aliases
    end)
  end

  defp module_alias_target_names({{:., _dot_metadata, [prefix, :{}]}, _metadata, suffixes})
       when is_list(suffixes) do
    case module_name(prefix) do
      nil ->
        []

      prefix_name ->
        Enum.flat_map(suffixes, fn suffix ->
          case module_name(suffix) do
            nil -> []
            suffix_name -> ["#{prefix_name}.#{suffix_name}"]
          end
        end)
    end
  end

  defp module_alias_target_names(target) do
    case module_name(target) do
      nil -> []
      target_name -> [target_name]
    end
  end

  defp resolve_module_name(target, aliases) when is_binary(target) do
    case String.split(target, ".", parts: 2) do
      [alias_name] -> Map.get(aliases, alias_name, target)
      [alias_name, rest] -> "#{Map.get(aliases, alias_name, alias_name)}.#{rest}"
    end
  end

  defp resolve_module_name(target, aliases) do
    case module_name(target) do
      nil -> nil
      target_name -> resolve_module_name(target_name, aliases)
    end
  end

  defp module_name({:__aliases__, _metadata, parts}) do
    if Enum.all?(parts, &is_atom/1), do: Enum.join(parts, ".")
  end

  defp module_name(_target), do: nil

  defp resolve_module_attributes(node, attributes),
    do: resolve_module_attributes(node, attributes, [])

  defp resolve_module_attributes(
         {:@, _metadata, [{name, _name_metadata, nil}]} = reference,
         attributes,
         resolving
       )
       when is_atom(name) do
    if name in resolving do
      reference
    else
      case Map.fetch(attributes, name) do
        {:ok, value} ->
          resolve_module_attributes(value, attributes, [name | resolving])

        :error ->
          reference
      end
    end
  end

  defp resolve_module_attributes(nodes, attributes, resolving) when is_list(nodes) do
    Enum.map(nodes, &resolve_module_attributes(&1, attributes, resolving))
  end

  defp resolve_module_attributes(node, attributes, resolving) when is_tuple(node) do
    node
    |> Tuple.to_list()
    |> Enum.map(&resolve_module_attributes(&1, attributes, resolving))
    |> List.to_tuple()
  end

  defp resolve_module_attributes(node, _attributes, _resolving), do: node

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
    options = quote_options(arguments)

    body =
      if quote_unquotes?(options) do
        options
        |> Keyword.get(:do)
        |> Macro.postwalk(fn
          {:unquote, _metadata, [expression]} -> substitute_bindings(expression, bindings)
          node -> node
        end)
      else
        Keyword.get(options, :do)
      end

    {body, _macro_bindings} =
      resolve_local_bindings(body, bind_quoted_bindings(options, bindings))

    body
  end

  defp expand_macro_body(body, bindings), do: substitute_bindings(body, bindings)

  defp quote_options(arguments) do
    Enum.flat_map(arguments, fn
      options when is_list(options) ->
        if Keyword.keyword?(options), do: options, else: []

      _argument ->
        []
    end)
  end

  defp quote_unquotes?(options) do
    Keyword.get(options, :unquote, not Keyword.has_key?(options, :bind_quoted))
  end

  defp bind_quoted_bindings(options, call_bindings) do
    options
    |> Keyword.get(:bind_quoted, [])
    |> Enum.reduce(%{}, fn
      {name, expression}, bindings when is_atom(name) ->
        Map.put(bindings, name, substitute_bindings(expression, call_bindings))

      _binding, bindings ->
        bindings
    end)
  end

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
    collect_foreign_key_operations(ast, nil, :definite)
  end

  defp collect_foreign_key_operations(
         {operator, _metadata, [condition, options]},
         table,
         certainty
       )
       when operator in [:if, :unless] and is_list(options) do
    condition_operations = collect_foreign_key_operations(condition, table, certainty)
    do_branch = Keyword.get(options, :do)
    else_branch = Keyword.get(options, :else)

    branch_operations =
      case selected_static_branch(operator, condition) do
        :do ->
          collect_foreign_key_operations(do_branch, table, certainty)

        :else ->
          collect_foreign_key_operations(else_branch, table, certainty)

        :unknown ->
          possible_certainty = possible_certainty(certainty)

          [do_branch, else_branch]
          |> Enum.flat_map(&collect_foreign_key_operations(&1, table, possible_certainty))
      end

    condition_operations ++ branch_operations
  end

  defp collect_foreign_key_operations(
         {:rename, _metadata,
          [
            {:table, _old_table_metadata, [old_table | _old_table_options]},
            [to: {:table, _new_table_metadata, [new_table | _new_table_options]}]
          ]},
         _table,
         certainty
       )
       when is_atom(old_table) and is_atom(new_table) do
    operation = {:rename_table, Atom.to_string(old_table), Atom.to_string(new_table)}
    [with_certainty(operation, certainty)]
  end

  defp collect_foreign_key_operations(
         {:rename, _metadata,
          [
            {:table, _table_metadata, [table | _table_options]},
            old_column,
            [to: new_column]
          ]},
         _table,
         certainty
       )
       when is_atom(table) and is_atom(old_column) and is_atom(new_column) do
    operation =
      {:rename_column, Atom.to_string(table), Atom.to_string(old_column),
       Atom.to_string(new_column)}

    [with_certainty(operation, certainty)]
  end

  defp collect_foreign_key_operations(
         {operation, _metadata,
          [{:table, _table_metadata, [table | _table_options]}, [do: block]]},
         _current_table,
         certainty
       )
       when operation in @table_definition_operations and is_atom(table) do
    collect_foreign_key_operations(block, Atom.to_string(table), certainty)
  end

  defp collect_foreign_key_operations(
         {operation, _metadata,
          [{:constraint, _constraint_metadata, [table, name | _constraint_options]}]},
         _current_table,
         certainty
       )
       when operation in @table_drop_operations and
              (is_atom(table) or is_binary(table)) and
              (is_atom(name) or is_binary(name)) do
    operation = {:drop_constraint, to_string(table), to_string(name)}
    [with_certainty(operation, certainty)]
  end

  defp collect_foreign_key_operations(
         {operation, _metadata,
          [{:table, _table_metadata, [table | _table_options]} | _drop_options]},
         _current_table,
         certainty
       )
       when operation in @table_drop_operations and is_atom(table) do
    operation = {:drop_table, Atom.to_string(table)}
    [with_certainty(operation, certainty)]
  end

  defp collect_foreign_key_operations(
         {operation, _metadata,
          [
            column,
            {:references, _references_metadata, [destination | reference_options]}
            | _column_options
          ]},
         table,
         certainty
       )
       when operation in [:add, :modify] and is_binary(table) and is_atom(column) and
              is_atom(destination) do
    reference_options = List.flatten(reference_options)

    foreign_key = {
      table,
      Atom.to_string(column),
      Atom.to_string(destination),
      reference_options |> Keyword.get(:column, :id) |> Atom.to_string(),
      foreign_key_constraint_name(table, column, reference_options)
    }

    [with_certainty({:put, foreign_key}, certainty)]
  end

  defp collect_foreign_key_operations(
         {:remove, _metadata, [column | _options]},
         table,
         certainty
       )
       when is_binary(table) and is_atom(column) do
    operation = {:remove, table, Atom.to_string(column)}
    [with_certainty(operation, certainty)]
  end

  defp collect_foreign_key_operations(nodes, table, certainty) when is_list(nodes) do
    Enum.flat_map(nodes, &collect_foreign_key_operations(&1, table, certainty))
  end

  defp collect_foreign_key_operations(node, table, certainty) when is_tuple(node) do
    node
    |> Tuple.to_list()
    |> Enum.flat_map(&collect_foreign_key_operations(&1, table, certainty))
  end

  defp collect_foreign_key_operations(_node, _table, _certainty), do: []

  defp foreign_key_constraint_name(table, column, reference_options) do
    case Keyword.get(reference_options, :name) do
      nil -> "#{table}_#{column}_fkey"
      name when is_atom(name) or is_binary(name) -> to_string(name)
    end
  end

  defp migration_table_operations(ast) do
    collect_table_operations(ast, :definite)
  end

  defp collect_table_operations(
         {operator, _metadata, [condition, options]},
         certainty
       )
       when operator in [:if, :unless] and is_list(options) do
    condition_operations = collect_table_operations(condition, certainty)

    do_branch = Keyword.get(options, :do)
    else_branch = Keyword.get(options, :else)

    branch_operations =
      case selected_static_branch(operator, condition) do
        :do ->
          collect_table_operations(do_branch, certainty)

        :else ->
          collect_table_operations(else_branch, certainty)

        :unknown ->
          possible_certainty = possible_certainty(certainty)

          [do_branch, else_branch]
          |> Enum.flat_map(&collect_table_operations(&1, possible_certainty))
      end

    condition_operations ++ branch_operations
  end

  defp collect_table_operations(nodes, certainty) when is_list(nodes) do
    Enum.flat_map(nodes, &collect_table_operations(&1, certainty))
  end

  defp collect_table_operations(node, certainty) when is_tuple(node) do
    operation =
      case table_operation(node) do
        nil -> []
        operation -> [with_certainty(operation, certainty)]
      end

    children =
      node
      |> Tuple.to_list()
      |> Enum.flat_map(&collect_table_operations(&1, certainty))

    operation ++ children
  end

  defp collect_table_operations(_node, _certainty), do: []

  defp selected_static_branch(:if, condition) do
    case static_truthiness(condition) do
      :truthy -> :do
      :falsy -> :else
      :unknown -> :unknown
    end
  end

  defp selected_static_branch(:unless, condition) do
    case static_truthiness(condition) do
      :truthy -> :else
      :falsy -> :do
      :unknown -> :unknown
    end
  end

  defp static_truthiness(condition) do
    case static_guard_result(condition) do
      :match ->
        :truthy

      :no_match ->
        :falsy

      :unknown ->
        case static_guard_value(condition) do
          {:known, value} when value in [false, nil] -> :falsy
          {:known, _value} -> :truthy
          :unknown -> :unknown
        end
    end
  end

  defp possible_certainty(_certainty), do: :possible
  defp with_certainty(operation, :definite), do: operation
  defp with_certainty(operation, :possible), do: {:possible, operation}

  defp table_operation(
         {:rename, _metadata,
          [
            {:table, _old_table_metadata, [old_table | _old_table_options]},
            [to: {:table, _new_table_metadata, [new_table | _new_table_options]}]
          ]}
       )
       when is_atom(old_table) and is_atom(new_table) do
    {:rename, Atom.to_string(old_table), Atom.to_string(new_table)}
  end

  defp table_operation(
         {operation, _metadata, [{:table, _table_metadata, [table | _table_options]} | _options]}
       )
       when operation in @table_lifecycle_operations and is_atom(table) do
    lifecycle_operation = if operation in @table_create_operations, do: :create, else: :drop
    {lifecycle_operation, Atom.to_string(table)}
  end

  defp table_operation(_node), do: nil

  defp apply_table_operation({:create, table}, tables), do: MapSet.put(tables, table)
  defp apply_table_operation({:drop, table}, tables), do: MapSet.delete(tables, table)

  defp apply_table_operation({:possible, {:create, table}}, tables),
    do: MapSet.put(tables, table)

  defp apply_table_operation({:possible, {:drop, _table}}, tables), do: tables

  defp apply_table_operation({:possible, {:rename, _old_table, new_table}}, tables),
    do: MapSet.put(tables, new_table)

  defp apply_table_operation({:rename, old_table, new_table}, tables) do
    tables
    |> MapSet.delete(old_table)
    |> MapSet.put(new_table)
  end

  defp apply_foreign_key_operation({:put, foreign_key}, foreign_keys) do
    Map.put(foreign_keys, foreign_key_identity(foreign_key), MapSet.new([foreign_key]))
  end

  defp apply_foreign_key_operation({:possible, {:put, foreign_key}}, foreign_keys) do
    Map.update(
      foreign_keys,
      foreign_key_identity(foreign_key),
      MapSet.new([foreign_key]),
      &MapSet.put(&1, foreign_key)
    )
  end

  defp apply_foreign_key_operation({:remove, table, column}, foreign_keys),
    do: Map.delete(foreign_keys, {table, column})

  defp apply_foreign_key_operation({:possible, {:remove, _table, _column}}, foreign_keys),
    do: foreign_keys

  defp apply_foreign_key_operation({:drop_table, table}, foreign_keys) do
    Map.reject(foreign_keys, fn {{source_table, _column}, _foreign_keys} ->
      source_table == table
    end)
  end

  defp apply_foreign_key_operation({:possible, {:drop_table, _table}}, foreign_keys),
    do: foreign_keys

  defp apply_foreign_key_operation({:drop_constraint, table, name}, foreign_keys) do
    reject_foreign_keys(foreign_keys, fn
      {source_table, _source_column, _destination_table, _destination_column, constraint_name} ->
        source_table == table and constraint_name == name
    end)
  end

  defp apply_foreign_key_operation(
         {:possible, {:drop_constraint, _table, _name}},
         foreign_keys
       ),
       do: foreign_keys

  defp apply_foreign_key_operation({:rename_table, old_table, new_table}, foreign_keys) do
    remap_foreign_keys(foreign_keys, &rename_foreign_key_table(&1, old_table, new_table))
  end

  defp apply_foreign_key_operation(
         {:possible, {:rename_table, old_table, new_table}},
         foreign_keys
       ) do
    add_possible_foreign_key_variants(
      foreign_keys,
      &rename_foreign_key_table(&1, old_table, new_table)
    )
  end

  defp apply_foreign_key_operation(
         {:rename_column, table, old_column, new_column},
         foreign_keys
       ) do
    remap_foreign_keys(
      foreign_keys,
      &rename_foreign_key_column(&1, table, old_column, new_column)
    )
  end

  defp apply_foreign_key_operation(
         {:possible, {:rename_column, table, old_column, new_column}},
         foreign_keys
       ) do
    add_possible_foreign_key_variants(
      foreign_keys,
      &rename_foreign_key_column(&1, table, old_column, new_column)
    )
  end

  defp foreign_key_identity({table, column, _destination_table, _destination_column, _name}),
    do: {table, column}

  defp rename_foreign_key_table(
         {source_table, source_column, destination_table, destination_column, constraint_name},
         old_table,
         new_table
       ) do
    source_table = if source_table == old_table, do: new_table, else: source_table
    destination_table = if destination_table == old_table, do: new_table, else: destination_table

    {source_table, source_column, destination_table, destination_column, constraint_name}
  end

  defp rename_foreign_key_column(
         {source_table, source_column, destination_table, destination_column, constraint_name},
         table,
         old_column,
         new_column
       ) do
    source_column =
      if source_table == table and source_column == old_column,
        do: new_column,
        else: source_column

    destination_column =
      if destination_table == table and destination_column == old_column,
        do: new_column,
        else: destination_column

    {source_table, source_column, destination_table, destination_column, constraint_name}
  end

  defp remap_foreign_keys(foreign_keys, mapper) do
    Enum.reduce(foreign_keys, %{}, fn {_identity, candidates}, remapped ->
      Enum.reduce(candidates, remapped, fn foreign_key, remapped ->
        foreign_key = mapper.(foreign_key)

        Map.update(
          remapped,
          foreign_key_identity(foreign_key),
          MapSet.new([foreign_key]),
          &MapSet.put(&1, foreign_key)
        )
      end)
    end)
  end

  defp add_possible_foreign_key_variants(foreign_keys, mapper) do
    Enum.reduce(foreign_keys, foreign_keys, fn {_identity, candidates}, expanded ->
      Enum.reduce(candidates, expanded, fn foreign_key, expanded ->
        possible_foreign_key = mapper.(foreign_key)

        Map.update(
          expanded,
          foreign_key_identity(possible_foreign_key),
          MapSet.new([possible_foreign_key]),
          &MapSet.put(&1, possible_foreign_key)
        )
      end)
    end)
  end

  defp reject_foreign_keys(foreign_keys, reject?) do
    Enum.reduce(foreign_keys, %{}, fn {identity, candidates}, remaining ->
      candidates = MapSet.reject(candidates, reject?)

      if MapSet.size(candidates) == 0,
        do: remaining,
        else: Map.put(remaining, identity, candidates)
    end)
  end
end
