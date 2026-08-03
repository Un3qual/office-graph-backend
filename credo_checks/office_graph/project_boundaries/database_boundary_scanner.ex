defmodule OfficeGraph.ProjectQuality.DatabaseBoundaryScanner do
  @moduledoc """
  Finds repository-owned database access that must be removed or explicitly
  approved.

  The scanner parses Elixir syntax and returns deterministic occurrence
  fingerprints. It does not execute source files or write inventories.
  """

  @spec scan_sources([%{required(:path) => String.t(), required(:source) => String.t()}]) ::
          [map()]
  def scan_sources(sources) do
    sources
    |> Enum.filter(&eligible_source?/1)
    |> Enum.flat_map(&scan_source/1)
    |> Enum.sort_by(&{&1.path, &1.line, &1.construct})
    |> add_ordinals_and_fingerprints()
  end

  @spec scan_repository(Path.t()) :: [map()]
  def scan_repository(root \\ File.cwd!()) do
    case System.cmd("git", ["ls-files", "-z"], cd: root, stderr_to_stdout: true) do
      {tracked_files, 0} ->
        tracked_files
        |> String.split("\0", trim: true)
        |> Enum.filter(&eligible_path?/1)
        |> Enum.flat_map(fn path ->
          full_path = Path.join(root, path)

          case File.read(full_path) do
            {:ok, source} ->
              [%{path: path, source: source}]

            {:error, :enoent} ->
              []

            {:error, reason} ->
              raise File.Error, reason: reason, action: "read file", path: full_path
          end
        end)
        |> scan_sources()

      {error, status} ->
        raise "git ls-files failed with status #{status}: #{String.trim(error)}"
    end
  end

  defp scan_source(%{path: path, source: source}) when is_binary(source) do
    if Path.extname(path) == ".sql" do
      if String.trim(source) == "" do
        []
      else
        [occurrence(path, 1, nil, :raw_sql, "sql_file", String.trim(source))]
      end
    else
      scan_elixir_source(path, source)
    end
  end

  defp scan_elixir_source(path, source) do
    migration? = migration_path?(path)
    ast = Code.string_to_quoted!(source, file: path, columns: true)
    context = %{function: nil, migration?: migration?, path: path}
    {_environment, occurrences} = scan_node(ast, empty_environment(), context, [])
    Enum.reverse(occurrences)
  end

  @direct_repo_operations [
    :aggregate,
    :all,
    :all_by,
    :checkout,
    :delete,
    :delete!,
    :delete_all,
    :exists?,
    :get,
    :get!,
    :get_by,
    :get_by!,
    :insert,
    :insert!,
    :insert_all,
    :insert_or_update,
    :insert_or_update!,
    :one,
    :one!,
    :preload,
    :preload!,
    :reload,
    :reload!,
    :rollback,
    :stream,
    :transact,
    :transaction,
    :update,
    :update!,
    :update_all
  ]

  @direct_multi_operations [
    :all,
    :append,
    :delete,
    :delete_all,
    :error,
    :exists?,
    :insert,
    :insert_all,
    :insert_or_update,
    :merge,
    :one,
    :prepend,
    :put,
    :run,
    :update,
    :update_all
  ]

  @database_alias_targets [
    "Ecto.Adapters.SQL",
    "Ecto.Multi",
    "Ecto.Query",
    "Ecto.Query.API",
    "OfficeGraph.Repo",
    "Postgrex"
  ]

  @ecto_fragment_import_targets ["Ecto.Query", "Ecto.Query.API"]

  @migration_create_operations [:create, :create_if_not_exists]
  @migration_sql_option_constructs [:constraint, :index, :unique_index]
  @ecto_sql_raw_sql_operations [:query, :query!, :query_many, :query_many!, :stream]

  @postgrex_raw_sql_operations [
    :execute,
    :execute!,
    :prepare,
    :prepare!,
    :prepare_execute,
    :prepare_execute!,
    :query,
    :query!,
    :stream
  ]

  defp scan_node({:__block__, _metadata, expressions}, environment, context, occurrences) do
    scan_sequence(expressions, environment, context, occurrences)
  end

  defp scan_node({:defmodule, _metadata, arguments}, environment, context, occurrences) do
    case block_body(arguments) do
      nil ->
        {environment, occurrences}

      body ->
        child_context = %{context | function: nil}
        child_environment = %{environment | attributes: %{}}

        {_child_environment, occurrences} =
          scan_node(body, child_environment, child_context, occurrences)

        {environment, occurrences}
    end
  end

  defp scan_node({kind, _metadata, [head, body_options]}, environment, context, occurrences)
       when kind in [:def, :defp, :defmacro, :defmacrop] and is_list(body_options) do
    occurrences =
      head
      |> function_variants()
      |> Enum.reduce(occurrences, fn variant, occurrences ->
        child_context = %{context | function: variant.signature}
        child_environment = %{environment | bindings: %{}}

        {child_environment, occurrences} =
          scan_function_defaults(
            variant.parameters,
            variant.omitted_indexes,
            child_environment,
            child_context,
            occurrences
          )

        {_child_environment, occurrences} =
          scan_children(body_options, child_environment, child_context, occurrences)

        occurrences
      end)

    {environment, occurrences}
  end

  defp scan_node({:case, _metadata, [value, options]}, environment, context, occurrences)
       when is_list(options) do
    {value_environment, occurrences} = scan_node(value, environment, context, occurrences)

    resolved_value =
      value
      |> resolve_attributes(value_environment)
      |> resolve_bindings(value_environment)
      |> resolve_struct_aliases(value_environment)

    occurrences =
      options
      |> Keyword.get(:do, [])
      |> Enum.reduce(occurrences, fn clause, occurrences ->
        scan_pattern_clause(
          clause,
          value_environment,
          context,
          occurrences,
          resolved_value
        )
      end)

    {environment, occurrences}
  end

  defp scan_node({:fn, _metadata, clauses}, environment, context, occurrences) do
    occurrences =
      Enum.reduce(clauses, occurrences, fn clause, occurrences ->
        scan_pattern_clause(clause, environment, context, occurrences)
      end)

    {environment, occurrences}
  end

  defp scan_node({:cond, _metadata, [options]}, environment, context, occurrences)
       when is_list(options) do
    occurrences =
      options
      |> Keyword.get(:do, [])
      |> Enum.reduce(occurrences, fn clause, occurrences ->
        scan_condition_clause(clause, environment, context, occurrences)
      end)

    {environment, occurrences}
  end

  defp scan_node({:receive, _metadata, [options]}, environment, context, occurrences)
       when is_list(options) do
    occurrences =
      options
      |> Keyword.get(:do, [])
      |> Enum.reduce(occurrences, fn clause, occurrences ->
        scan_pattern_clause(clause, environment, context, occurrences)
      end)

    occurrences =
      options
      |> Keyword.get(:after, [])
      |> Enum.reduce(occurrences, fn clause, occurrences ->
        scan_condition_clause(clause, environment, context, occurrences)
      end)

    {environment, occurrences}
  end

  defp scan_node({:for, _metadata, arguments}, environment, context, occurrences)
       when is_list(arguments) do
    {qualifiers, options} = split_qualifiers_and_options(arguments)

    {child_environment, occurrences} =
      scan_generator_qualifiers(qualifiers, environment, context, occurrences, :enumerate)

    {_options_environment, occurrences} =
      options
      |> Keyword.delete(:do)
      |> Keyword.values()
      |> scan_isolated_children(environment, context, occurrences)

    {_body_environment, occurrences} =
      scan_node(Keyword.get(options, :do), child_environment, context, occurrences)

    {environment, occurrences}
  end

  defp scan_node({:with, _metadata, arguments}, environment, context, occurrences)
       when is_list(arguments) do
    {qualifiers, options} = split_qualifiers_and_options(arguments)

    {child_environment, occurrences} =
      scan_generator_qualifiers(qualifiers, environment, context, occurrences, :match)

    {_body_environment, occurrences} =
      scan_node(Keyword.get(options, :do), child_environment, context, occurrences)

    occurrences =
      options
      |> Keyword.get(:else, [])
      |> Enum.reduce(occurrences, fn clause, occurrences ->
        scan_pattern_clause(clause, environment, context, occurrences)
      end)

    {environment, occurrences}
  end

  defp scan_node({:->, _metadata, [patterns, _body]} = clause, environment, context, occurrences)
       when is_list(patterns) do
    {environment, scan_pattern_clause(clause, environment, context, occurrences)}
  end

  defp scan_node(
         {:@, _metadata, [{name, _name_metadata, [value]}]},
         environment,
         context,
         occurrences
       )
       when is_atom(name) do
    {_child_environment, occurrences} =
      scan_node(value, environment, context, occurrences)

    resolved_value = resolve_attributes(value, environment)

    {%{environment | attributes: Map.put(environment.attributes, name, resolved_value)},
     occurrences}
  end

  defp scan_node(
         {:@, _metadata, [{name, _name_metadata, nil}]},
         environment,
         _context,
         occurrences
       )
       when is_atom(name),
       do: {environment, occurrences}

  defp scan_node({:alias, metadata, arguments}, environment, _context, occurrences) do
    {put_aliases(environment, metadata, arguments), occurrences}
  end

  defp scan_node({:import, metadata, arguments}, environment, _context, occurrences) do
    {put_import(environment, metadata, arguments), occurrences}
  end

  defp scan_node({:=, _metadata, [pattern, value]}, environment, context, occurrences) do
    {environment, occurrences} = scan_node(value, environment, context, occurrences)

    resolved_pattern = resolve_struct_aliases(pattern, environment)

    resolved_value =
      value
      |> resolve_attributes(environment)
      |> resolve_bindings(environment)
      |> resolve_struct_aliases(environment)

    bindings = bind_pattern(resolved_pattern, resolved_value, environment.bindings)

    {%{environment | bindings: bindings}, occurrences}
  end

  defp scan_node(node, environment, context, occurrences) do
    resolved_node = resolve_attributes(node, environment)
    fingerprint_node = resolve_bindings(resolved_node, environment)

    occurrences =
      classify_migration_sql_options(fingerprint_node, context, occurrences)

    occurrences =
      case classify_node(resolved_node, context.migration?, environment) do
        nil ->
          occurrences

        {class, construct} ->
          [
            occurrence(
              context.path,
              node_line(node),
              context.function,
              class,
              construct,
              fingerprint_node
            )
            | occurrences
          ]
      end

    scan_children(node, environment, context, occurrences)
  end

  defp scan_function_defaults(
         parameters,
         omitted_indexes,
         environment,
         context,
         occurrences
       ) do
    parameters
    |> Enum.with_index()
    |> Enum.reduce({environment, occurrences}, fn
      {{:\\, _metadata, [pattern, default]}, index}, {environment, occurrences} ->
        if MapSet.member?(omitted_indexes, index) do
          {environment, occurrences} =
            scan_node(default, environment, context, occurrences)

          resolved_pattern = resolve_struct_aliases(pattern, environment)

          resolved_default =
            default
            |> resolve_attributes(environment)
            |> resolve_bindings(environment)
            |> resolve_struct_aliases(environment)

          bindings = bind_pattern(resolved_pattern, resolved_default, environment.bindings)
          {%{environment | bindings: bindings}, occurrences}
        else
          {environment, occurrences}
        end

      _parameter, accumulator ->
        accumulator
    end)
  end

  defp function_variants(head) do
    case function_name_and_parameters(head) do
      {name, parameters} ->
        defaults =
          parameters
          |> Enum.with_index()
          |> Enum.flat_map(fn
            {{:\\, _metadata, [_pattern, _default]}, index} -> [index]
            {_parameter, _index} -> []
          end)

        full_arity = length(parameters)

        0..length(defaults)
        |> Enum.map(fn omitted_count ->
          omitted_indexes = defaults |> Enum.take(-omitted_count) |> MapSet.new()

          %{
            omitted_indexes: omitted_indexes,
            parameters: parameters,
            signature: "#{name}/#{full_arity - omitted_count}"
          }
        end)

      nil ->
        []
    end
  end

  defp function_name_and_parameters({:when, _metadata, [head | _guards]}),
    do: function_name_and_parameters(head)

  defp function_name_and_parameters({name, _metadata, parameters})
       when is_atom(name) and (is_list(parameters) or is_nil(parameters)),
       do: {name, parameters || []}

  defp function_name_and_parameters(_head), do: nil

  defp scan_pattern_clause(
         {:->, _metadata, [parameters, body]},
         environment,
         context,
         occurrences
       )
       when is_list(parameters) do
    {patterns, guards} = clause_patterns_and_guards(parameters)

    child_environment = remove_pattern_bindings(environment, patterns)

    {_guard_environment, occurrences} =
      scan_isolated_children(guards, child_environment, context, occurrences)

    {_body_environment, occurrences} =
      scan_node(body, child_environment, context, occurrences)

    occurrences
  end

  defp scan_pattern_clause(clause, environment, context, occurrences) do
    {_child_environment, occurrences} = scan_node(clause, environment, context, occurrences)
    occurrences
  end

  defp scan_pattern_clause(
         {:->, _metadata, [parameters, body]},
         environment,
         context,
         occurrences,
         matched_value
       )
       when is_list(parameters) do
    {patterns, guards} = clause_patterns_and_guards(parameters)

    child_environment =
      environment
      |> remove_pattern_bindings(patterns)
      |> bind_static_clause_patterns(patterns, matched_value)

    {_guard_environment, occurrences} =
      scan_isolated_children(guards, child_environment, context, occurrences)

    {_body_environment, occurrences} =
      scan_node(body, child_environment, context, occurrences)

    occurrences
  end

  defp scan_pattern_clause(clause, environment, context, occurrences, _matched_value),
    do: scan_pattern_clause(clause, environment, context, occurrences)

  defp scan_condition_clause(
         {:->, _metadata, [conditions, body]},
         environment,
         context,
         occurrences
       )
       when is_list(conditions) do
    {child_environment, occurrences} =
      scan_sequence(conditions, environment, context, occurrences)

    {_body_environment, occurrences} =
      scan_node(body, child_environment, context, occurrences)

    occurrences
  end

  defp scan_condition_clause(clause, environment, context, occurrences) do
    {_child_environment, occurrences} = scan_node(clause, environment, context, occurrences)
    occurrences
  end

  defp clause_patterns_and_guards([
         {:when, _metadata, guarded_patterns_and_guard}
       ])
       when length(guarded_patterns_and_guard) >= 2 do
    {Enum.drop(guarded_patterns_and_guard, -1), [List.last(guarded_patterns_and_guard)]}
  end

  defp clause_patterns_and_guards(patterns), do: {patterns, []}

  defp bind_static_clause_patterns(environment, [pattern], matched_value) do
    pattern = resolve_struct_aliases(pattern, environment)

    if static_binding_source?(matched_value) and static_pattern_match?(pattern, matched_value) do
      %{environment | bindings: bind_pattern(pattern, matched_value, environment.bindings)}
    else
      environment
    end
  end

  defp bind_static_clause_patterns(environment, _patterns, _matched_value), do: environment

  defp static_pattern_match?({:^, _metadata, [_pattern]}, _value), do: false

  defp static_pattern_match?({:=, _metadata, [left_pattern, right_pattern]}, value),
    do: static_pattern_match?(left_pattern, value) and static_pattern_match?(right_pattern, value)

  defp static_pattern_match?({name, _metadata, binding_context}, _value)
       when is_atom(name) and (is_atom(binding_context) or is_nil(binding_context)),
       do: true

  defp static_pattern_match?(
         {:%, _pattern_metadata, [pattern_struct, pattern_map]},
         {:%, _value_metadata, [value_struct, value_map]}
       ),
       do:
         same_static_ast?(pattern_struct, value_struct) and
           static_pattern_match?(pattern_map, value_map)

  defp static_pattern_match?(
         {:%{}, _pattern_metadata, pattern_fields},
         {:%{}, _value_metadata, value_fields}
       ) do
    Enum.all?(pattern_fields, fn
      {key, pattern} ->
        case fetch_static_field(value_fields, key) do
          {:ok, value} -> static_pattern_match?(pattern, value)
          :error -> false
        end

      _field ->
        false
    end)
  end

  defp static_pattern_match?(
         {:{}, _pattern_metadata, patterns},
         {:{}, _value_metadata, values}
       )
       when length(patterns) == length(values),
       do:
         Enum.zip(patterns, values)
         |> Enum.all?(fn {pattern, value} ->
           static_pattern_match?(pattern, value)
         end)

  defp static_pattern_match?({left_pattern, right_pattern}, {left_value, right_value}),
    do:
      static_pattern_match?(left_pattern, left_value) and
        static_pattern_match?(right_pattern, right_value)

  defp static_pattern_match?(patterns, values) when is_list(patterns) and is_list(values) do
    case List.last(patterns) do
      {:|, _metadata, [_head_pattern, _tail_pattern]} ->
        static_cons_pattern_match?(patterns, values)

      _not_a_cons_pattern ->
        length(patterns) == length(values) and
          patterns
          |> Enum.zip(values)
          |> Enum.all?(fn {pattern, value} ->
            static_pattern_match?(pattern, value)
          end)
    end
  end

  defp static_pattern_match?(pattern, value)
       when is_atom(pattern) or is_binary(pattern) or is_number(pattern),
       do: pattern === value

  defp static_pattern_match?(_pattern, _value), do: false

  defp static_cons_pattern_match?(
         [{:|, _metadata, [head_pattern, tail_pattern]}],
         [head_value | tail_value]
       ) do
    static_pattern_match?(head_pattern, head_value) and
      static_pattern_match?(tail_pattern, tail_value)
  end

  defp static_cons_pattern_match?([pattern | patterns], [value | values]) do
    static_pattern_match?(pattern, value) and
      static_cons_pattern_match?(patterns, values)
  end

  defp static_cons_pattern_match?(_patterns, _values), do: false

  defp pattern_binding_names({:^, _metadata, [_pattern]}), do: []

  defp pattern_binding_names({:<<>>, _metadata, segments}) when is_list(segments),
    do: Enum.flat_map(segments, &bitstring_pattern_binding_names/1)

  defp pattern_binding_names({name, _metadata, binding_context})
       when is_atom(name) and (is_atom(binding_context) or is_nil(binding_context)),
       do: if(name == :_, do: [], else: [name])

  defp pattern_binding_names({_form, _metadata, arguments}) when is_list(arguments) do
    Enum.flat_map(arguments, &pattern_binding_names/1)
  end

  defp pattern_binding_names({left_pattern, right_pattern}) do
    pattern_binding_names(left_pattern) ++ pattern_binding_names(right_pattern)
  end

  defp pattern_binding_names(patterns) when is_list(patterns) do
    Enum.flat_map(patterns, &pattern_binding_names/1)
  end

  defp pattern_binding_names(_pattern), do: []

  defp bitstring_pattern_binding_names({:"::", _metadata, [value_pattern, _spec]}),
    do: pattern_binding_names(value_pattern)

  defp bitstring_pattern_binding_names(pattern), do: pattern_binding_names(pattern)

  defp split_qualifiers_and_options(arguments) do
    case Enum.split(arguments, -1) do
      {qualifiers, [options]} when is_list(options) -> {qualifiers, options}
      {qualifiers, options} -> {qualifiers ++ options, []}
    end
  end

  defp scan_generator_qualifiers(
         qualifiers,
         environment,
         context,
         occurrences,
         binding_mode
       ) do
    Enum.reduce(qualifiers, {environment, occurrences}, fn
      {:<-, _metadata, [pattern, source]}, {environment, occurrences} ->
        {environment, occurrences} = scan_node(source, environment, context, occurrences)
        {patterns, guards} = clause_patterns_and_guards([pattern])

        resolved_source =
          source
          |> resolve_attributes(environment)
          |> resolve_bindings(environment)
          |> resolve_struct_aliases(environment)

        child_environment =
          environment
          |> remove_pattern_bindings(patterns)
          |> bind_generator_patterns(patterns, resolved_source, binding_mode)

        {_guard_environment, occurrences} =
          scan_isolated_children(guards, child_environment, context, occurrences)

        {child_environment, occurrences}

      qualifier, {environment, occurrences} ->
        scan_node(qualifier, environment, context, occurrences)
    end)
  end

  defp bind_generator_patterns(environment, patterns, source, :match) do
    if static_binding_source?(source) do
      bind_generator_value(environment, patterns, source)
    else
      environment
    end
  end

  defp bind_generator_patterns(environment, patterns, [value], :enumerate) do
    if static_binding_source?(value) do
      bind_generator_value(environment, patterns, value)
    else
      environment
    end
  end

  defp bind_generator_patterns(environment, _patterns, _source, :enumerate), do: environment

  defp bind_generator_value(environment, patterns, value) do
    patterns = Enum.map(patterns, &resolve_struct_aliases(&1, environment))

    if Enum.all?(patterns, &static_pattern_match?(&1, value)) do
      bindings =
        Enum.reduce(patterns, environment.bindings, fn pattern, bindings ->
          bind_pattern(pattern, value, bindings)
        end)

      %{environment | bindings: bindings}
    else
      environment
    end
  end

  defp static_binding_source?(value)
       when is_atom(value) or is_binary(value) or is_number(value),
       do: true

  defp static_binding_source?(values) when is_list(values),
    do: Enum.all?(values, &static_binding_source?/1)

  defp static_binding_source?({:{}, _metadata, values}),
    do: Enum.all?(values, &static_binding_source?/1)

  defp static_binding_source?({:%{}, _metadata, fields}),
    do: Enum.all?(fields, &static_binding_source?/1)

  defp static_binding_source?({:%, _metadata, [module, fields]}),
    do: match?({:__aliases__, _, _}, module) and static_binding_source?(fields)

  defp static_binding_source?({:__aliases__, _metadata, parts}),
    do: Enum.all?(parts, &is_atom/1)

  defp static_binding_source?({left, right}),
    do: static_binding_source?(left) and static_binding_source?(right)

  defp static_binding_source?(_value), do: false

  defp remove_pattern_bindings(environment, patterns) do
    Enum.reduce(patterns, environment, fn pattern, environment ->
      bindings =
        Enum.reduce(pattern_binding_names(pattern), environment.bindings, &Map.delete(&2, &1))

      %{environment | bindings: bindings}
    end)
  end

  defp scan_sequence(expressions, environment, context, occurrences) do
    Enum.reduce(expressions, {environment, occurrences}, fn expression,
                                                            {environment, occurrences} ->
      scan_node(expression, environment, context, occurrences)
    end)
  end

  defp scan_children({_name, metadata, arguments}, environment, context, occurrences)
       when is_list(metadata) and is_list(arguments) do
    scan_isolated_children(arguments, environment, context, occurrences)
  end

  defp scan_children({_key, value}, environment, context, occurrences) do
    {_child_environment, occurrences} = scan_node(value, environment, context, occurrences)
    {environment, occurrences}
  end

  defp scan_children(values, environment, context, occurrences) when is_list(values) do
    scan_isolated_children(values, environment, context, occurrences)
  end

  defp scan_children(_node, environment, _context, occurrences),
    do: {environment, occurrences}

  defp scan_isolated_children(children, environment, context, occurrences) do
    occurrences =
      Enum.reduce(children, occurrences, fn child, occurrences ->
        {_child_environment, occurrences} = scan_node(child, environment, context, occurrences)
        occurrences
      end)

    {environment, occurrences}
  end

  defp classify_node(
         {{:., _dot_metadata, [receiver, operation]}, _metadata, _arguments},
         migration?,
         environment
       ) do
    receiver =
      receiver
      |> resolve_bindings(environment)
      |> receiver_name()
      |> resolve_receiver(environment)

    classify_migration_operation(receiver, operation, migration?) ||
      classify_database_operation(receiver, operation)
  end

  defp classify_node({construct, _metadata, arguments}, migration?, environment)
       when construct in [:fragment, :unsafe_fragment] and is_list(arguments) do
    if migration? or imported_fragment?(environment, construct, length(arguments)),
      do: {:raw_sql, to_string(construct)}
  end

  defp classify_node({:execute, _metadata, arguments}, true, _environment)
       when is_list(arguments),
       do: {:raw_sql, "migration.execute"}

  defp classify_node({:insert, _metadata, arguments}, true, _environment)
       when is_list(arguments),
       do: {:direct_ecto, "migration.insert"}

  defp classify_node({operation, _metadata, arguments}, _migration?, environment)
       when is_atom(operation) and is_list(arguments) do
    environment
    |> imported_receiver(operation, length(arguments))
    |> classify_database_operation(operation)
  end

  defp classify_node({:unsafe_fragment, sql}, _migration?, _environment) when is_binary(sql),
    do: {:raw_sql, "unsafe_fragment"}

  defp classify_node(_node, _migration?, _environment), do: nil

  defp classify_migration_operation("Ecto.Migration", :execute, true),
    do: {:raw_sql, "migration.execute"}

  defp classify_migration_operation("Ecto.Migration", :insert, true),
    do: {:direct_ecto, "migration.insert"}

  defp classify_migration_operation("Ecto.Migration", :fragment, true),
    do: {:raw_sql, "fragment"}

  defp classify_migration_operation(_receiver, _operation, _migration?), do: nil

  defp classify_database_operation(nil, _operation), do: nil

  defp classify_database_operation(receiver, operation) do
    cond do
      receiver == "Ecto.Query.API" and operation in [:fragment, :unsafe_fragment] ->
        {:raw_sql, "#{receiver}.#{operation}"}

      operation in [:query, :query!] and repo_receiver?(receiver) ->
        {:raw_sql, "Repo.#{operation}"}

      receiver == "Ecto.Adapters.SQL" and operation in @ecto_sql_raw_sql_operations ->
        {:raw_sql, "#{receiver}.#{operation}"}

      receiver == "Postgrex" and operation in @postgrex_raw_sql_operations ->
        {:raw_sql, "#{receiver}.#{operation}"}

      repo_receiver?(receiver) and operation in @direct_repo_operations ->
        {:direct_ecto, "Repo.#{operation}"}

      receiver in ["Ecto.Multi", "Multi"] and operation in @direct_multi_operations ->
        {:direct_ecto, "Ecto.Multi.#{operation}"}

      true ->
        nil
    end
  end

  defp classify_migration_sql_options(
         {operation, _metadata, [{construct, construct_metadata, arguments}]},
         %{migration?: true} = context,
         occurrences
       )
       when operation in @migration_create_operations and
              construct in @migration_sql_option_constructs and is_list(arguments) do
    option_keys = migration_sql_option_keys(construct)
    line = Keyword.get(construct_metadata, :line, 1)

    case List.last(arguments) do
      options when is_list(options) ->
        Enum.reduce(options, occurrences, fn
          {key, value}, occurrences ->
            if key in option_keys do
              [
                occurrence(
                  context.path,
                  line,
                  context.function,
                  :raw_sql,
                  "migration.#{key}",
                  migration_sql_option_fingerprint_input(
                    operation,
                    construct,
                    arguments,
                    option_keys,
                    key,
                    value
                  )
                )
                | occurrences
              ]
            else
              occurrences
            end

          _option, occurrences ->
            occurrences
        end)

      _argument ->
        occurrences
    end
  end

  defp classify_migration_sql_options(_node, _context, occurrences), do: occurrences

  defp migration_sql_option_keys(:constraint), do: [:check, :exclude]

  defp migration_sql_option_keys(construct) when construct in [:index, :unique_index],
    do: [:options, :where]

  defp migration_sql_option_fingerprint_input(
         operation,
         construct,
         arguments,
         option_keys,
         key,
         value
       ) do
    target_options =
      arguments
      |> List.last()
      |> Enum.reject(fn
        {option_key, _value} -> option_key in option_keys
        _option -> false
      end)

    target =
      arguments
      |> List.replace_at(-1, target_options)
      |> then(&{construct, [], &1})
      |> Macro.to_string()

    Enum.join(
      [
        "operation: #{operation}",
        "target: #{target}",
        "option: #{key}",
        "value: #{Macro.to_string(value)}"
      ],
      "\n"
    )
  end

  defp empty_environment, do: %{aliases: %{}, attributes: %{}, bindings: %{}, imports: []}

  defp resolve_attributes(node, environment) do
    Macro.prewalk(node, fn
      {:@, _metadata, [{name, _name_metadata, nil}]} = reference when is_atom(name) ->
        Map.get(environment.attributes, name, reference)

      child ->
        child
    end)
  end

  defp resolve_bindings(node, environment),
    do: resolve_bindings(node, environment, MapSet.new())

  defp resolve_bindings(
         {name, _metadata, binding_context} = reference,
         environment,
         resolving
       )
       when is_atom(name) and (is_atom(binding_context) or is_nil(binding_context)) do
    if MapSet.member?(resolving, name) do
      reference
    else
      case Map.fetch(environment.bindings, name) do
        {:ok, value} -> resolve_bindings(value, environment, MapSet.put(resolving, name))
        :error -> reference
      end
    end
  end

  defp resolve_bindings(node, environment, resolving) when is_list(node) do
    Enum.map(node, &resolve_bindings(&1, environment, resolving))
  end

  defp resolve_bindings(node, environment, resolving) when is_tuple(node) do
    node
    |> Tuple.to_list()
    |> resolve_bindings(environment, resolving)
    |> List.to_tuple()
  end

  defp resolve_bindings(node, _environment, _resolving), do: node

  defp resolve_struct_aliases(node, environment) do
    Macro.prewalk(node, fn
      {:%, metadata, [module, fields]} ->
        {:%, metadata, [resolve_module_alias(module, environment), fields]}

      child ->
        child
    end)
  end

  defp resolve_module_alias(module, environment) do
    case receiver_name(module) do
      nil ->
        module

      module_name ->
        module_name
        |> resolve_receiver(environment)
        |> String.split(".")
        |> Enum.map(&String.to_existing_atom/1)
        |> then(&{:__aliases__, [], &1})
    end
  end

  defp bind_pattern({:^, _metadata, [_pattern]}, _value, bindings), do: bindings

  defp bind_pattern({:=, _metadata, [left_pattern, right_pattern]}, value, bindings) do
    bindings = bind_pattern(left_pattern, value, bindings)
    bind_pattern(right_pattern, value, bindings)
  end

  defp bind_pattern({name, _metadata, binding_context}, value, bindings)
       when is_atom(name) and (is_atom(binding_context) or is_nil(binding_context)) do
    if name == :_, do: bindings, else: Map.put(bindings, name, value)
  end

  defp bind_pattern(
         {:%, _pattern_metadata, [pattern_struct, pattern_map]},
         {:%, _value_metadata, [value_struct, value_map]},
         bindings
       ) do
    if same_static_ast?(pattern_struct, value_struct),
      do: bind_pattern(pattern_map, value_map, bindings),
      else: bindings
  end

  defp bind_pattern(
         {:%{}, _pattern_metadata, _pattern_fields} = pattern,
         {:%, _, [_, value]},
         bindings
       ) do
    bind_pattern(pattern, value, bindings)
  end

  defp bind_pattern(
         {:%{}, _pattern_metadata, pattern_fields},
         {:%{}, _value_metadata, value_fields},
         bindings
       ) do
    Enum.reduce(pattern_fields, bindings, fn
      {key, pattern}, bindings ->
        case fetch_static_field(value_fields, key) do
          {:ok, value} -> bind_pattern(pattern, value, bindings)
          :error -> bindings
        end

      _field, bindings ->
        bindings
    end)
  end

  defp bind_pattern({:{}, _pattern_metadata, patterns}, {:{}, _value_metadata, values}, bindings)
       when length(patterns) == length(values) do
    bind_pattern_elements(patterns, values, bindings)
  end

  defp bind_pattern({left_pattern, right_pattern}, {left_value, right_value}, bindings) do
    bindings = bind_pattern(left_pattern, left_value, bindings)
    bind_pattern(right_pattern, right_value, bindings)
  end

  defp bind_pattern(
         [{:|, _pattern_metadata, [head_pattern, tail_pattern]}],
         [{:|, _value_metadata, [head_value, tail_value]}],
         bindings
       ) do
    bindings = bind_pattern(head_pattern, head_value, bindings)
    bind_pattern(tail_pattern, tail_value, bindings)
  end

  defp bind_pattern(patterns, values, bindings)
       when is_list(patterns) and is_list(values) do
    case List.last(patterns) do
      {:|, _metadata, [_head_pattern, _tail_pattern]} ->
        bind_cons_pattern(patterns, values, bindings)

      _not_a_cons_pattern when length(patterns) == length(values) ->
        bind_pattern_elements(patterns, values, bindings)

      _length_mismatch ->
        bindings
    end
  end

  defp bind_pattern(_pattern, _value, bindings), do: bindings

  defp bind_pattern_elements(patterns, values, bindings) do
    patterns
    |> Enum.zip(values)
    |> Enum.reduce(bindings, fn {pattern, value}, bindings ->
      bind_pattern(pattern, value, bindings)
    end)
  end

  defp bind_cons_pattern(
         [{:|, _metadata, [head_pattern, tail_pattern]}],
         [head_value | tail_value],
         bindings
       ) do
    bindings = bind_pattern(head_pattern, head_value, bindings)
    bind_pattern(tail_pattern, tail_value, bindings)
  end

  defp bind_cons_pattern([pattern | patterns], [value | values], bindings) do
    bindings = bind_pattern(pattern, value, bindings)
    bind_cons_pattern(patterns, values, bindings)
  end

  defp bind_cons_pattern(_patterns, _values, bindings), do: bindings

  defp fetch_static_field(fields, key) do
    Enum.find_value(fields, :error, fn
      {candidate_key, value} ->
        if same_static_ast?(candidate_key, key), do: {:ok, value}, else: false

      _field ->
        false
    end)
  end

  defp same_static_ast?(left, right), do: Macro.to_string(left) == Macro.to_string(right)

  defp block_body([_head, body_options]) when is_list(body_options),
    do: Keyword.get(body_options, :do)

  defp block_body(_arguments), do: nil

  defp put_aliases(environment, _metadata, [target]),
    do: apply_aliases(environment, target, [])

  defp put_aliases(environment, _metadata, [target, options]) when is_list(options),
    do: apply_aliases(environment, target, options)

  defp put_aliases(environment, _metadata, _arguments), do: environment

  defp apply_aliases(environment, target, options) do
    bindings =
      target
      |> alias_target_names()
      |> Enum.map(fn target_name ->
        resolved_target = resolve_receiver(target_name, environment)

        alias_name =
          options
          |> Keyword.get(:as)
          |> case do
            nil -> target_name |> String.split(".") |> List.last()
            explicit_alias -> receiver_name(explicit_alias)
          end

        {alias_name, resolved_target}
      end)

    aliases =
      Enum.reduce(bindings, environment.aliases, fn
        {alias_name, target_name}, aliases
        when is_binary(alias_name) and is_binary(target_name) ->
          Map.put(aliases, alias_name, target_name)

        _binding, aliases ->
          aliases
      end)

    %{environment | aliases: aliases}
  end

  defp alias_target_names({{:., _dot_metadata, [prefix, :{}]}, _metadata, suffixes})
       when is_list(suffixes) do
    case receiver_name(prefix) do
      nil ->
        []

      prefix_name ->
        Enum.flat_map(suffixes, fn suffix ->
          case receiver_name(suffix) do
            nil -> []
            suffix_name -> ["#{prefix_name}.#{suffix_name}"]
          end
        end)
    end
  end

  defp alias_target_names(target) do
    case receiver_name(target) do
      nil -> []
      target_name -> [target_name]
    end
  end

  defp put_import(environment, _metadata, [target]),
    do: apply_import(environment, target, [])

  defp put_import(environment, _metadata, [target, options]) when is_list(options),
    do: apply_import(environment, target, options)

  defp put_import(environment, _metadata, _arguments), do: environment

  defp apply_import(environment, target, options) do
    case target |> receiver_name() |> resolve_receiver(environment) do
      nil ->
        environment

      target_name ->
        declaration = %{
          except: import_entries(Keyword.get(options, :except)),
          only: import_entries(Keyword.get(options, :only)),
          target: target_name
        }

        %{environment | imports: [declaration | environment.imports]}
    end
  end

  defp import_entries(entries) when is_list(entries) do
    entries
    |> Enum.flat_map(fn
      {name, arity} when is_atom(name) and is_integer(arity) -> [{name, arity}]
      _entry -> []
    end)
    |> MapSet.new()
  end

  defp import_entries(_entries), do: nil

  defp imported_receiver(environment, operation, arity) do
    Enum.find_value(environment.imports, fn declaration ->
      if import_applies?(declaration, operation, arity), do: declaration.target
    end)
  end

  defp imported_fragment?(environment, operation, arity) do
    Enum.any?(environment.imports, fn declaration ->
      declaration.target in @ecto_fragment_import_targets and
        import_applies?(declaration, operation, arity)
    end)
  end

  defp import_applies?(%{only: %MapSet{} = only}, operation, arity),
    do: MapSet.member?(only, {operation, arity})

  defp import_applies?(
         %{except: %MapSet{} = except, target: target},
         operation,
         arity
       )
       when target in @database_alias_targets,
       do: not MapSet.member?(except, {operation, arity})

  defp import_applies?(%{only: nil, target: target}, _operation, _arity),
    do: target in @database_alias_targets

  defp import_applies?(_declaration, _operation, _arity), do: false

  defp receiver_name({:__aliases__, _metadata, parts}) do
    if Enum.all?(parts, &is_atom/1), do: Enum.join(parts, ".")
  end

  defp receiver_name({name, _metadata, context}) when is_atom(name) and is_atom(context),
    do: to_string(name)

  defp receiver_name(_receiver), do: nil

  defp resolve_receiver(nil, _environment), do: nil

  defp resolve_receiver(receiver, environment) do
    case String.split(receiver, ".", parts: 2) do
      [alias_name] ->
        Map.get(environment.aliases, alias_name, receiver)

      [alias_name, rest] ->
        case Map.get(environment.aliases, alias_name) do
          nil -> receiver
          target -> "#{target}.#{rest}"
        end
    end
  end

  defp repo_receiver?(receiver), do: receiver in ["Repo", "OfficeGraph.Repo"]

  defp node_line({{:., _dot_metadata, _receiver_and_operation}, metadata, _arguments}),
    do: Keyword.get(metadata, :line, 1)

  defp node_line({_name, metadata, _arguments}) when is_list(metadata),
    do: Keyword.get(metadata, :line, 1)

  defp node_line(_node), do: 1

  defp eligible_source?(%{path: path}), do: eligible_path?(path)

  defp eligible_path?(path) do
    path = String.trim_leading(path, "./")
    extension = Path.extname(path)

    not excluded_path?(path) and extension in [".ex", ".exs", ".sql"]
  end

  defp excluded_path?(path) do
    Enum.any?(String.split(path, "/"), &(&1 in ["_build", "deps", "node_modules"]))
  end

  defp migration_path?(path), do: String.starts_with?(path, "priv/repo/migrations/")

  defp occurrence(path, line, function, class, construct, node_or_source) do
    normalized =
      if is_binary(node_or_source),
        do: node_or_source,
        else: Macro.to_string(node_or_source)

    %{
      path: path,
      line: line,
      function: function,
      class: class,
      construct: construct,
      normalized: normalized
    }
  end

  defp add_ordinals_and_fingerprints(occurrences) do
    {occurrences, _counts} =
      Enum.map_reduce(occurrences, %{}, fn occurrence, counts ->
        locator = {
          occurrence.path,
          occurrence.class,
          occurrence.construct,
          occurrence.function
        }

        ordinal = Map.get(counts, locator, 0) + 1

        fingerprint_input =
          Enum.join(
            [
              occurrence.path,
              occurrence.class,
              occurrence.construct,
              occurrence.function || "<module>",
              ordinal,
              occurrence.normalized
            ],
            "\n"
          )

        fingerprint =
          fingerprint_input
          |> then(&:crypto.hash(:sha256, &1))
          |> Base.encode16(case: :lower)
          |> then(&"sha256:#{&1}")

        finalized =
          occurrence
          |> Map.drop([:normalized])
          |> Map.merge(%{fingerprint: fingerprint, ordinal: ordinal})

        {finalized, Map.put(counts, locator, ordinal)}
      end)

    occurrences
  end
end
