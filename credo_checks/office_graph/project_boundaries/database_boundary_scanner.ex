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
    file_sources =
      Map.new(sources, fn %{path: path, source: source} ->
        {normalize_source_path(path), source}
      end)

    scan_sources(sources, fn path ->
      with {:ok, path} <- normalize_execute_file_path(path),
           false <- excluded_path?(path),
           {:ok, source} <- Map.fetch(file_sources, path) do
        {:ok, source}
      else
        _unavailable -> :error
      end
    end)
  end

  defp scan_sources(sources, file_resolver) do
    sources
    |> Enum.filter(&eligible_source?/1)
    |> Enum.flat_map(&scan_source/1)
    |> resolve_execute_file_occurrences(file_resolver)
    |> Enum.sort_by(&{&1.path, &1.line, &1.construct})
    |> add_ordinals_and_fingerprints()
  end

  @spec scan_repository(Path.t()) :: [map()]
  def scan_repository(root \\ File.cwd!()) do
    case System.cmd("git", ["ls-files", "-z"], cd: root, stderr_to_stdout: true) do
      {tracked_files, 0} ->
        tracked_paths = String.split(tracked_files, "\0", trim: true)
        tracked_path_set = MapSet.new(tracked_paths, &normalize_source_path/1)

        sources =
          tracked_paths
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

        scan_sources(sources, fn path ->
          with {:ok, path} <- normalize_execute_file_path(path),
               false <- excluded_path?(path),
               true <- MapSet.member?(tracked_path_set, path) do
            full_path = Path.join(root, path)

            case File.read(full_path) do
              {:ok, source} ->
                {:ok, source}

              {:error, :enoent} ->
                :error

              {:error, reason} ->
                raise File.Error, reason: reason, action: "read file", path: full_path
            end
          else
            _unavailable -> :error
          end
        end)

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
    context = %{function: nil, local_call_stack: MapSet.new(), migration?: migration?, path: path}
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
    "Ecto.Migration",
    "Ecto.Multi",
    "Ecto.Query",
    "Ecto.Query.API",
    "OfficeGraph.Repo",
    "Postgrex"
  ]

  @ecto_fragment_import_targets ["Ecto.Migration", "Ecto.Query", "Ecto.Query.API"]
  @ecto_migration_use_fixed_imports MapSet.new(
                                      execute: 1,
                                      execute: 2,
                                      execute_file: 1,
                                      execute_file: 2,
                                      insert: 2,
                                      insert: 3,
                                      repo: 0
                                    )

  @migration_repo_receiver "Ecto.Migration.repo()"
  @migration_create_operations [:create, :create_if_not_exists]
  @migration_sql_option_constructs [:constraint, :index, :table, :unique_index]
  @kernel_value_callback_operations [:tap, :then]
  @repo_supplied_callback_operations [:transact, :transaction]

  @enum_unary_element_callback_operations [
    :all?,
    :any?,
    :chunk_by,
    :count,
    :count_until,
    :dedup_by,
    :drop_while,
    :each,
    :filter,
    :find,
    :find_index,
    :find_value,
    :flat_map,
    :frequencies_by,
    :group_by,
    :into,
    :map,
    :map_every,
    :map_intersperse,
    :map_join,
    :max_by,
    :min_by,
    :min_max_by,
    :product_by,
    :reject,
    :sort_by,
    :split_while,
    :split_with,
    :sum_by,
    :take_while,
    :uniq_by
  ]

  @enum_element_first_callback_operations [
    :flat_map_reduce,
    :map_reduce,
    :reduce,
    :reduce_while,
    :scan
  ]

  @enum_second_argument_unary_callback_operations [
    :all?,
    :any?,
    :chunk_by,
    :count,
    :dedup_by,
    :drop_while,
    :each,
    :filter,
    :find,
    :find_index,
    :find_value,
    :flat_map,
    :frequencies_by,
    :group_by,
    :map,
    :max_by,
    :min_by,
    :min_max_by,
    :product_by,
    :reject,
    :sort_by,
    :split_while,
    :split_with,
    :sum_by,
    :take_while,
    :uniq_by
  ]

  @enum_third_argument_unary_callback_operations [
    :find,
    :find_value,
    :into,
    :map_every,
    :map_intersperse,
    :map_join
  ]

  @enum_callback_operations Enum.uniq(
                              @enum_unary_element_callback_operations ++
                                @enum_element_first_callback_operations
                            )
  @stream_second_argument_unary_callback_operations [
    :chunk_by,
    :dedup_by,
    :drop_while,
    :each,
    :filter,
    :flat_map,
    :map,
    :reject,
    :take_while,
    :uniq_by
  ]
  @stream_third_argument_unary_callback_operations [:map_every]
  @stream_unary_element_callback_operations Enum.uniq(
                                              @stream_second_argument_unary_callback_operations ++
                                                @stream_third_argument_unary_callback_operations
                                            )
  @ecto_sql_direct_operations [:checkout, :explain]
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

  defp scan_node({:|>, _metadata, _arguments} = pipeline, environment, context, occurrences) do
    pipeline
    |> expand_pipeline()
    |> scan_node(environment, context, occurrences)
  end

  defp scan_node(
         {operation, _metadata, [value, callback]} = node,
         environment,
         context,
         occurrences
       )
       when operation in @kernel_value_callback_operations do
    with true <- kernel_value_callback_call?(operation, environment),
         {:ok, callback} <- normalize_literal_callback(callback, environment) do
      scan_invoked_literal_callback(callback, [value], environment, context, occurrences)
    else
      _not_literal_kernel_callback ->
        scan_executable_node(node, environment, context, occurrences)
    end
  end

  defp scan_node(
         {{:., _dot_metadata, [receiver, operation]}, _metadata, [value, callback]} = node,
         environment,
         context,
         occurrences
       )
       when operation in @kernel_value_callback_operations do
    with true <- kernel_module_receiver?(receiver, environment),
         {:ok, callback} <- normalize_literal_callback(callback, environment) do
      scan_invoked_literal_callback(callback, [value], environment, context, occurrences)
    else
      _not_literal_kernel_callback ->
        scan_executable_node(node, environment, context, occurrences)
    end
  end

  defp scan_node(
         {{:., _dot_metadata, [callback]}, _metadata, arguments} = node,
         environment,
         context,
         occurrences
       )
       when is_list(arguments) do
    case normalize_literal_callback(callback, environment) do
      {:ok, callback} ->
        scan_invoked_literal_callback(callback, arguments, environment, context, occurrences)

      :error ->
        scan_executable_node(node, environment, context, occurrences)
    end
  end

  defp scan_node(
         {{:., _dot_metadata, [receiver, operation]}, _metadata, arguments} = node,
         environment,
         context,
         occurrences
       )
       when operation in @enum_callback_operations and is_list(arguments) do
    if enum_module_receiver?(receiver, environment) do
      scan_enum_literal_callbacks(
        node,
        operation,
        arguments,
        environment,
        context,
        occurrences
      )
    else
      scan_executable_node(node, environment, context, occurrences)
    end
  end

  defp scan_node(
         {{:., _dot_metadata, [receiver, :run]}, _metadata, [stream]} = node,
         environment,
         context,
         occurrences
       ) do
    if stream_module_receiver?(receiver, environment) do
      case scan_consumed_stream(stream, environment, context, occurrences) do
        {:ok, environment, occurrences} -> {environment, occurrences}
        :error -> scan_executable_node(node, environment, context, occurrences)
      end
    else
      scan_executable_node(node, environment, context, occurrences)
    end
  end

  defp scan_node(
         {{:., _dot_metadata, [receiver, operation]}, _metadata, arguments} = node,
         environment,
         context,
         occurrences
       )
       when operation in @repo_supplied_callback_operations and is_list(arguments) do
    callback = List.first(arguments)

    with {:ok, callback} <- normalize_literal_callback(callback, environment),
         1 <- literal_callback_arity(callback),
         {:ok, callback_receiver} <-
           static_repo_callback_receiver(receiver, environment, context.migration?) do
      scan_database_callback_call(
        node,
        receiver,
        arguments,
        0,
        callback,
        [callback_receiver],
        environment,
        context,
        occurrences
      )
    else
      _unsupported_callback -> scan_executable_node(node, environment, context, occurrences)
    end
  end

  defp scan_node(
         {{:., _dot_metadata, [receiver, :run]}, _metadata, arguments} = node,
         environment,
         context,
         occurrences
       )
       when length(arguments) == 3 do
    callback = Enum.at(arguments, 2)

    with true <- ecto_multi_receiver?(receiver, environment),
         {:ok, callback} <- normalize_literal_callback(callback, environment),
         2 <- literal_callback_arity(callback) do
      scan_database_callback_call(
        node,
        receiver,
        arguments,
        2,
        callback,
        [generic_repo_receiver(), {:__unresolved_multi_changes__, [], []}],
        environment,
        context,
        occurrences
      )
    else
      _unsupported_callback -> scan_executable_node(node, environment, context, occurrences)
    end
  end

  defp scan_node({:defmodule, _metadata, arguments}, environment, context, occurrences) do
    case block_body(arguments) do
      nil ->
        {environment, occurrences}

      body ->
        child_context = %{context | function: nil}

        child_environment = %{
          environment
          | attributes: %{},
            attribute_modes: %{},
            uncertain_attribute_registration?: false,
            local_functions: %{}
        }

        child_environment = %{
          child_environment
          | local_functions: collect_local_functions(body, child_environment)
        }

        {_child_environment, occurrences} =
          scan_node(body, child_environment, child_context, occurrences)

        {environment, occurrences}
    end
  end

  defp scan_node({:quote, _metadata, arguments}, environment, context, occurrences)
       when is_list(arguments) do
    options = local_quote_options(arguments)

    {environment, occurrences} =
      options
      |> Keyword.get(:bind_quoted)
      |> scan_quote_bindings(environment, context, occurrences)

    if local_quote_unquotes?(options) do
      options
      |> Keyword.get(:do)
      |> scan_quote_unquotes(environment, context, occurrences)
    else
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

    {child_environments, occurrences} =
      scan_for_qualifiers(qualifiers, environment, context, occurrences)

    {_options_environment, occurrences} =
      options
      |> Keyword.delete(:do)
      |> Keyword.values()
      |> scan_isolated_children(environment, context, occurrences)

    occurrences =
      Enum.reduce(child_environments, occurrences, fn child_environment, occurrences ->
        {_body_environment, occurrences} =
          scan_node(Keyword.get(options, :do), child_environment, context, occurrences)

        occurrences
      end)

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

    {put_module_attribute_value(environment, name, resolved_value), occurrences}
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

  defp scan_node({:use, _metadata, arguments} = node, environment, context, occurrences) do
    {_child_environment, occurrences} =
      scan_children(node, environment, context, occurrences)

    {put_use_import(environment, arguments), occurrences}
  end

  defp scan_node(
         {{:., _dot_metadata, [receiver, :register_attribute]}, _metadata, arguments} = node,
         environment,
         context,
         occurrences
       )
       when length(arguments) in [2, 3] do
    if module_attribute_registration?(receiver, arguments, environment) do
      {_child_environment, occurrences} =
        scan_children(node, environment, context, occurrences)

      {register_module_attribute(environment, arguments), occurrences}
    else
      scan_executable_node(node, environment, context, occurrences)
    end
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

  defp scan_node({name, _metadata, arguments} = node, environment, context, occurrences)
       when is_atom(name) and is_list(arguments) do
    if local_database_helper_call?(name, arguments, environment) do
      scan_invoked_local_database_helper(
        name,
        arguments,
        environment,
        context,
        occurrences
      )
    else
      scan_executable_node(node, environment, context, occurrences)
    end
  end

  defp scan_node(node, environment, context, occurrences) do
    scan_executable_node(node, environment, context, occurrences)
  end

  defp scan_quote_bindings(bindings, environment, context, occurrences)
       when is_list(bindings) do
    Enum.reduce(bindings, {environment, occurrences}, fn
      {_name, expression}, {environment, occurrences} ->
        scan_node(expression, environment, context, occurrences)

      _invalid_binding, accumulator ->
        accumulator
    end)
  end

  defp scan_quote_bindings(_bindings, environment, _context, occurrences),
    do: {environment, occurrences}

  defp scan_quote_unquotes({:quote, _metadata, _arguments}, environment, _context, occurrences),
    do: {environment, occurrences}

  defp scan_quote_unquotes(
         {operation, _metadata, [expression]},
         environment,
         context,
         occurrences
       )
       when operation in [:unquote, :unquote_splicing],
       do: scan_node(expression, environment, context, occurrences)

  defp scan_quote_unquotes(nodes, environment, context, occurrences) when is_list(nodes) do
    Enum.reduce(nodes, {environment, occurrences}, fn node, {environment, occurrences} ->
      scan_quote_unquotes(node, environment, context, occurrences)
    end)
  end

  defp scan_quote_unquotes(node, environment, context, occurrences) when is_tuple(node) do
    node
    |> Tuple.to_list()
    |> scan_quote_unquotes(environment, context, occurrences)
  end

  defp scan_quote_unquotes(_node, environment, _context, occurrences),
    do: {environment, occurrences}

  defp scan_executable_node(node, environment, context, occurrences) do
    occurrences = record_executable_occurrence(node, environment, context, occurrences)
    scan_classified_children(node, environment, context, occurrences)
  end

  defp record_executable_occurrence(node, environment, context, occurrences) do
    resolved_node = resolve_attributes(node, environment)
    fingerprint_node = resolve_bindings(resolved_node, environment)
    classification_node = normalize_static_apply(fingerprint_node, environment)
    occurrence_node = normalized_occurrence_node(classification_node, fingerprint_node)

    occurrences =
      classify_query_sql_options(classification_node, environment, context, occurrences)

    occurrences =
      classify_migration_sql_options(classification_node, environment, context, occurrences)

    occurrences =
      case classify_node(classification_node, context.migration?, environment) do
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
              occurrence_node
            )
            |> mark_sql_approval(class, construct, classification_node)
            | occurrences
          ]
      end

    occurrences
  end

  defp scan_database_callback_call(
         node,
         receiver,
         arguments,
         callback_index,
         callback,
         callback_arguments,
         environment,
         context,
         occurrences
       ) do
    occurrences = record_executable_occurrence(node, environment, context, occurrences)
    {environment, occurrences} = scan_node(receiver, environment, context, occurrences)

    {environment, occurrences} =
      arguments
      |> Enum.with_index()
      |> Enum.reduce({environment, occurrences}, fn
        {_callback, ^callback_index}, accumulator ->
          accumulator

        {argument, _index}, {environment, occurrences} ->
          scan_node(argument, environment, context, occurrences)
      end)

    {_callback_environment, occurrences} =
      scan_invoked_literal_callback(
        callback,
        callback_arguments,
        environment,
        context,
        occurrences
      )

    {environment, occurrences}
  end

  defp scan_consumed_stream(
         {{:., _dot_metadata, [receiver, operation]}, _metadata, arguments},
         environment,
         context,
         occurrences
       )
       when operation in @stream_unary_element_callback_operations and is_list(arguments) do
    with true <- stream_module_receiver?(receiver, environment),
         callback_index when is_integer(callback_index) <-
           stream_unary_element_callback_index(operation, arguments),
         callback <- Enum.at(arguments, callback_index),
         {:ok, callback} <- normalize_literal_callback(callback, environment),
         1 <- literal_callback_arity(callback) do
      {resolved_arguments, arguments_environment, occurrences} =
        scan_invoked_callback_arguments(
          List.delete_at(arguments, callback_index),
          environment,
          context,
          occurrences
        )

      resolved_enumerable = List.first(resolved_arguments)

      occurrences =
        if is_list(resolved_enumerable) and static_binding_source?(resolved_enumerable) do
          Enum.reduce(Enum.uniq(resolved_enumerable), occurrences, fn element, occurrences ->
            {_callback_environment, occurrences} =
              scan_invoked_literal_callback(
                callback,
                [element],
                arguments_environment,
                context,
                occurrences
              )

            occurrences
          end)
        else
          {_callback_environment, occurrences} =
            scan_node(callback, arguments_environment, context, occurrences)

          occurrences
        end

      {:ok, arguments_environment, occurrences}
    else
      _unsupported_stream -> :error
    end
  end

  defp scan_consumed_stream(_stream, _environment, _context, _occurrences), do: :error

  defp stream_unary_element_callback_index(operation, arguments) do
    cond do
      operation in @stream_second_argument_unary_callback_operations and length(arguments) == 2 ->
        1

      operation in @stream_third_argument_unary_callback_operations and length(arguments) == 3 ->
        2

      true ->
        nil
    end
  end

  defp expand_pipeline(pipeline) do
    [{first, _position} | rest] = Macro.unpipe(pipeline)

    Enum.reduce(rest, first, fn {call, position}, piped ->
      Macro.pipe(piped, call, position)
    end)
  end

  defp normalize_static_apply(
         {:apply, metadata, [receiver, operation, arguments]} = node,
         environment
       ) do
    imported_receiver = imported_receiver(environment, :apply, 3)

    if Map.has_key?(environment.local_functions, {:apply, 3}) or
         imported_receiver not in [nil, "Kernel"] do
      node
    else
      static_applied_call(receiver, operation, arguments, metadata, node)
    end
  end

  defp normalize_static_apply(
         {{:., _dot_metadata, [apply_receiver, :apply]}, metadata,
          [receiver, operation, arguments]} = node,
         environment
       ) do
    if kernel_apply_receiver?(apply_receiver, environment),
      do: static_applied_call(receiver, operation, arguments, metadata, node),
      else: node
  end

  defp normalize_static_apply(node, _environment), do: node

  defp normalized_occurrence_node(
         {:unresolved_database_apply, _receiver, _operation, _arguments},
         original_node
       ),
       do: original_node

  defp normalized_occurrence_node(normalized_node, _original_node), do: normalized_node

  defp static_applied_call(receiver, operation, arguments, metadata, _fallback)
       when is_atom(operation) and is_list(arguments),
       do: {{:., [], [receiver, operation]}, metadata, arguments}

  defp static_applied_call(receiver, operation, arguments, _metadata, _fallback),
    do: {:unresolved_database_apply, receiver, operation, arguments}

  defp kernel_apply_receiver?(:erlang, _environment), do: true

  defp kernel_apply_receiver?(receiver, environment) do
    receiver |> receiver_name() |> resolve_receiver(environment) == "Kernel"
  end

  defp kernel_value_callback_call?(operation, environment) do
    not Map.has_key?(environment.local_functions, {operation, 2}) and
      explicitly_imported_receiver(environment, operation, 2) in [nil, "Kernel"]
  end

  defp kernel_module_receiver?(receiver, environment) do
    receiver |> receiver_name() |> resolve_receiver(environment) == "Kernel"
  end

  defp enum_module_receiver?(receiver, environment) do
    receiver |> receiver_name() |> resolve_receiver(environment) == "Enum"
  end

  defp stream_module_receiver?(receiver, environment) do
    receiver |> receiver_name() |> resolve_receiver(environment) == "Stream"
  end

  defp ecto_multi_receiver?(receiver, environment) do
    receiver |> receiver_name() |> resolve_receiver(environment) == "Ecto.Multi"
  end

  defp static_repo_callback_receiver(receiver, environment, migration?) do
    resolved_receiver = resolve_static_expression(receiver, environment)

    case database_receiver_name(resolved_receiver, migration?, environment) do
      receiver_name when receiver_name in ["Repo", "OfficeGraph.Repo"] ->
        {:ok, resolved_receiver}

      @migration_repo_receiver ->
        {:ok, generic_repo_receiver()}

      _not_a_repo ->
        :error
    end
  end

  defp generic_repo_receiver, do: {:__aliases__, [], [:Repo]}

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
    {head, guards} = function_head_and_guards(head)

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

          arity = full_arity - omitted_count

          %{
            arity: arity,
            guards: guards,
            name: name,
            omitted_indexes: omitted_indexes,
            parameters: parameters,
            signature: "#{name}/#{arity}"
          }
        end)

      nil ->
        []
    end
  end

  defp function_head_and_guards({:when, _metadata, [head | guards]}) do
    {head, preceding_guards} = function_head_and_guards(head)
    {head, preceding_guards ++ guards}
  end

  defp function_head_and_guards(head), do: {head, []}

  defp function_name_and_parameters({:when, _metadata, [head | _guards]}),
    do: function_name_and_parameters(head)

  defp function_name_and_parameters({name, _metadata, parameters})
       when is_atom(name) and (is_list(parameters) or is_nil(parameters)),
       do: {name, parameters || []}

  defp function_name_and_parameters(_head), do: nil

  defp collect_local_functions(body, environment) do
    {functions, _environment} =
      body
      |> module_expressions()
      |> Enum.reduce({%{}, environment}, fn expression, {functions, environment} ->
        case expression do
          {:alias, metadata, arguments} ->
            {functions, put_aliases(environment, metadata, arguments)}

          {:import, metadata, arguments} ->
            {functions, put_import(environment, metadata, arguments)}

          {:use, _metadata, arguments} ->
            {functions, put_use_import(environment, arguments)}

          {:@, _metadata, [{name, _name_metadata, [value]}]} when is_atom(name) ->
            value = resolve_attributes(value, environment)
            {functions, put_module_attribute_value(environment, name, value)}

          {{:., _dot_metadata, [receiver, :register_attribute]}, _metadata, arguments}
          when length(arguments) in [2, 3] ->
            if module_attribute_registration?(receiver, arguments, environment) do
              {functions, register_module_attribute(environment, arguments)}
            else
              {functions, environment}
            end

          {kind, _metadata, [head, body_options]}
          when kind in [:def, :defp, :defmacro, :defmacrop] and is_list(body_options) ->
            definition_environment = local_definition_environment_snapshot(environment)

            functions =
              Enum.reduce(function_variants(head), functions, fn variant, functions ->
                definition =
                  variant
                  |> Map.put(:body, Keyword.get(body_options, :do))
                  |> Map.put(:definition_environment, definition_environment)
                  |> Map.put(:kind, local_definition_kind(kind))

                Map.update(
                  functions,
                  {variant.name, variant.arity},
                  [definition],
                  &(&1 ++ [definition])
                )
              end)

            {functions, environment}

          _expression ->
            {functions, environment}
        end
      end)

    functions
  end

  defp local_definition_environment_snapshot(environment) do
    Map.take(environment, [
      :aliases,
      :attribute_modes,
      :attributes,
      :imports,
      :uncertain_attribute_registration?
    ])
  end

  defp module_expressions({:__block__, _metadata, expressions}) when is_list(expressions),
    do: expressions

  defp module_expressions(expression), do: [expression]

  defp local_definition_kind(kind) when kind in [:defmacro, :defmacrop], do: :macro
  defp local_definition_kind(kind) when kind in [:def, :defp], do: :function

  defp normalize_literal_callback(callback, environment) do
    callback
    |> resolve_attributes(environment)
    |> resolve_callback_binding(environment, MapSet.new())
    |> do_normalize_literal_callback(environment)
  end

  defp resolve_callback_binding(
         {name, _metadata, binding_context} = callback,
         environment,
         resolving
       )
       when is_atom(name) and (is_atom(binding_context) or is_nil(binding_context)) do
    if MapSet.member?(resolving, name) do
      callback
    else
      case Map.fetch(environment.bindings, name) do
        {:ok, value} ->
          resolve_callback_binding(value, environment, MapSet.put(resolving, name))

        :error ->
          callback
      end
    end
  end

  defp resolve_callback_binding(callback, _environment, _resolving), do: callback

  defp do_normalize_literal_callback({:fn, _metadata, _clauses} = callback, _environment),
    do: {:ok, callback}

  defp do_normalize_literal_callback(
         {:&, metadata, [{:/, _arity_metadata, [{name, _name_metadata, context}, arity]}]},
         environment
       )
       when is_atom(name) and (is_atom(context) or is_nil(context)) and is_integer(arity) and
              arity >= 0 do
    if local_function_capture?(environment, name, arity) do
      parameters = if arity == 0, do: [], else: Enum.map(1..arity, &capture_argument/1)
      body = {name, metadata, parameters}
      {:ok, {:fn, metadata, [{:->, metadata, [parameters, body]}]}}
    else
      :error
    end
  end

  defp do_normalize_literal_callback({:&, metadata, [body]}, _environment) do
    {_body, {arity, nested_capture?}} =
      Macro.prewalk(body, {0, false}, fn
        {:&, _placeholder_metadata, [index]} = placeholder, {arity, nested_capture?}
        when is_integer(index) and index > 0 ->
          {placeholder, {max(arity, index), nested_capture?}}

        {:&, _capture_metadata, _arguments} = capture, {arity, _nested_capture?} ->
          {capture, {arity, true}}

        node, state ->
          {node, state}
      end)

    if arity > 0 and not nested_capture? do
      parameters = Enum.map(1..arity, &capture_argument/1)

      body =
        Macro.postwalk(body, fn
          {:&, _placeholder_metadata, [index]} when is_integer(index) and index > 0 ->
            capture_argument(index)

          node ->
            node
        end)

      {:ok, {:fn, metadata, [{:->, metadata, [parameters, body]}]}}
    else
      :error
    end
  end

  defp do_normalize_literal_callback(_callback, _environment), do: :error

  defp local_function_capture?(environment, name, arity) do
    environment.local_functions
    |> Map.get({name, arity}, [])
    |> Enum.any?(&(&1.kind == :function))
  end

  defp capture_argument(index), do: Macro.var(:"boundary_capture_argument_#{index}", __MODULE__)

  defp local_database_helper_call?(name, arguments, environment) do
    definitions = Map.get(environment.local_functions, {name, length(arguments)}, [])

    Enum.any?(definitions, &(&1.kind == :macro)) or
      (definitions != [] and
         Enum.any?(arguments, fn argument ->
           argument
           |> callback_argument_result()
           |> resolve_attributes(environment)
           |> resolve_bindings(environment)
           |> resolve_struct_aliases(environment)
           |> static_value_contains_database_receiver?(environment)
         end))
  end

  defp scan_invoked_local_database_helper(
         name,
         arguments,
         environment,
         context,
         occurrences
       ) do
    {resolved_arguments, arguments_environment, occurrences} =
      scan_invoked_callback_arguments(arguments, environment, context, occurrences)

    key = {name, length(arguments)}

    if MapSet.member?(context.local_call_stack, key) do
      {arguments_environment, occurrences}
    else
      definitions =
        environment.local_functions
        |> Map.get(key, [])
        |> matching_local_definitions(resolved_arguments, arguments_environment)

      occurrences =
        Enum.reduce(definitions, occurrences, fn definition, occurrences ->
          child_environment =
            bind_local_function_arguments(
              definition,
              resolved_arguments,
              arguments_environment
            )

          {body, child_environment} = expand_local_definition(definition, child_environment)

          child_context =
            context
            |> Map.put(
              :function,
              if(definition.kind == :macro, do: context.function, else: definition.signature)
            )
            |> Map.put(:local_call_stack, MapSet.put(context.local_call_stack, key))

          {_child_environment, occurrences} =
            scan_node(body, child_environment, child_context, occurrences)

          occurrences
        end)

      {arguments_environment, occurrences}
    end
  end

  defp scan_invoked_literal_callback(
         {:fn, _metadata, clauses},
         arguments,
         environment,
         context,
         occurrences
       ) do
    {resolved_arguments, arguments_environment, occurrences} =
      scan_invoked_callback_arguments(
        arguments,
        environment,
        context,
        occurrences
      )

    occurrences =
      Enum.reduce(clauses, occurrences, fn clause, occurrences ->
        scan_invoked_callback_clause(
          clause,
          resolved_arguments,
          arguments_environment,
          context,
          occurrences
        )
      end)

    {arguments_environment, occurrences}
  end

  defp scan_invoked_callback_arguments(
         arguments,
         environment,
         context,
         occurrences
       ) do
    {resolved_arguments, {environment, occurrences}} =
      Enum.map_reduce(arguments, {environment, occurrences}, fn argument,
                                                                {environment, occurrences} ->
        {argument_environment, occurrences} =
          scan_node(argument, environment, context, occurrences)

        resolved_argument =
          argument
          |> callback_argument_result()
          |> resolve_attributes(argument_environment)
          |> resolve_bindings(argument_environment)
          |> resolve_struct_aliases(argument_environment)

        {resolved_argument, {argument_environment, occurrences}}
      end)

    {resolved_arguments, environment, occurrences}
  end

  defp callback_argument_result({:=, _metadata, [_pattern, value]}),
    do: callback_argument_result(value)

  defp callback_argument_result({:__block__, _metadata, expressions})
       when is_list(expressions) and expressions != [],
       do: expressions |> List.last() |> callback_argument_result()

  defp callback_argument_result(argument), do: argument

  defp scan_invoked_callback_clause(
         {:->, _metadata, [parameters, body]},
         arguments,
         environment,
         context,
         occurrences
       )
       when is_list(parameters) do
    {patterns, guards} = clause_patterns_and_guards(parameters)

    environment = remove_pattern_bindings(environment, patterns)

    case bind_static_callback_patterns(environment, patterns, arguments) do
      {:ok, child_environment} ->
        {_guard_environment, occurrences} =
          scan_isolated_children(guards, child_environment, context, occurrences)

        {_body_environment, occurrences} =
          scan_node(body, child_environment, context, occurrences)

        occurrences

      :no_match ->
        occurrences
    end
  end

  defp scan_invoked_callback_clause(
         clause,
         _arguments,
         environment,
         context,
         occurrences
       ) do
    {_child_environment, occurrences} = scan_node(clause, environment, context, occurrences)
    occurrences
  end

  defp bind_static_callback_patterns(environment, patterns, arguments)
       when length(patterns) == length(arguments) do
    patterns = Enum.map(patterns, &resolve_struct_aliases(&1, environment))

    patterns
    |> Enum.zip(arguments)
    |> Enum.reduce_while({:ok, environment}, fn {pattern, argument}, {:ok, environment} ->
      cond do
        not static_binding_source?(argument) ->
          {:cont, {:ok, environment}}

        static_pattern_match?(pattern, argument) ->
          bindings = bind_pattern(pattern, argument, environment.bindings)
          {:cont, {:ok, %{environment | bindings: bindings}}}

        true ->
          {:halt, :no_match}
      end
    end)
  end

  defp bind_static_callback_patterns(_environment, _patterns, _arguments), do: :no_match

  defp scan_enum_literal_callbacks(
         node,
         operation,
         arguments,
         environment,
         context,
         occurrences
       ) do
    callback_indexes = enum_element_callback_indexes(operation, length(arguments))

    callback_entries =
      callback_indexes
      |> Enum.flat_map(fn index ->
        with {:ok, callback} <-
               arguments |> Enum.at(index) |> normalize_literal_callback(environment),
             true <- enum_element_callback?(operation, callback) do
          [{index, callback}]
        else
          _not_element_callback -> []
        end
      end)

    callback_indexes = Enum.map(callback_entries, &elem(&1, 0))
    callback_arguments = Enum.map(callback_entries, &elem(&1, 1))

    if callback_arguments != [] do
      {arguments_environment, occurrences} =
        arguments
        |> Enum.with_index()
        |> Enum.reduce({environment, occurrences}, fn {argument, index},
                                                      {environment, occurrences} ->
          if index in callback_indexes do
            {environment, occurrences}
          else
            scan_node(argument, environment, context, occurrences)
          end
        end)

      resolved_enumerable =
        arguments
        |> List.first()
        |> callback_argument_result()
        |> resolve_attributes(arguments_environment)
        |> resolve_bindings(arguments_environment)
        |> resolve_struct_aliases(arguments_environment)

      if is_list(resolved_enumerable) and static_binding_source?(resolved_enumerable) do
        scan_static_enum_callbacks(
          operation,
          callback_arguments,
          arguments,
          resolved_enumerable,
          arguments_environment,
          context,
          occurrences
        )
      else
        occurrences =
          Enum.reduce(callback_arguments, occurrences, fn callback, occurrences ->
            {_callback_environment, occurrences} =
              scan_node(callback, arguments_environment, context, occurrences)

            occurrences
          end)

        {arguments_environment, occurrences}
      end
    else
      scan_executable_node(node, environment, context, occurrences)
    end
  end

  defp enum_element_callback_indexes(operation, arity) do
    cond do
      arity == 2 and operation in @enum_second_argument_unary_callback_operations ->
        [1]

      arity == 3 and operation == :count_until ->
        [1]

      arity == 3 and operation == :group_by ->
        [1, 2]

      arity == 3 and operation in @enum_third_argument_unary_callback_operations ->
        [2]

      arity >= 3 and operation in [:max_by, :min_by, :min_max_by, :sort_by] ->
        [1]

      arity == 2 and operation in [:reduce, :scan] ->
        [1]

      arity == 3 and operation in @enum_element_first_callback_operations ->
        [2]

      true ->
        []
    end
  end

  defp scan_static_enum_callbacks(
         operation,
         callback_arguments,
         invocation_arguments,
         resolved_enumerable,
         arguments_environment,
         context,
         occurrences
       ) do
    callback_invocations =
      enum_callback_invocations(
        operation,
        invocation_arguments,
        resolved_enumerable,
        arguments_environment
      )

    occurrences =
      Enum.reduce(callback_arguments, occurrences, fn callback, occurrences ->
        Enum.reduce(callback_invocations, occurrences, fn callback_arguments, occurrences ->
          {_callback_environment, occurrences} =
            scan_invoked_literal_callback(
              callback,
              callback_arguments,
              arguments_environment,
              context,
              occurrences
            )

          occurrences
        end)
      end)

    {arguments_environment, occurrences}
  end

  defp enum_callback_invocations(
         operation,
         invocation_arguments,
         [accumulator | elements],
         _environment
       )
       when operation in [:reduce, :scan] and length(invocation_arguments) == 2 do
    elements
    |> Enum.uniq()
    |> Enum.map(&[&1, accumulator])
  end

  defp enum_callback_invocations(
         operation,
         invocation_arguments,
         resolved_enumerable,
         environment
       ) do
    elements =
      case Enum.uniq(resolved_enumerable) do
        [] -> [{:__unresolved_enum_element__, [], []}]
        elements -> elements
      end

    Enum.map(elements, fn element ->
      enum_callback_arguments(operation, invocation_arguments, element, environment)
    end)
  end

  defp enum_element_callback?(operation, {:fn, _metadata, clauses} = callback)
       when is_list(clauses) do
    case literal_callback_arity(callback) do
      1 -> operation in @enum_unary_element_callback_operations
      2 -> operation in @enum_element_first_callback_operations
      _arity -> false
    end
  end

  defp enum_element_callback?(_operation, _argument), do: false

  defp literal_callback_arity({:fn, _metadata, clauses}) do
    arities =
      Enum.map(clauses, fn
        {:->, _clause_metadata, [parameters, _body]} when is_list(parameters) ->
          parameters |> clause_patterns_and_guards() |> elem(0) |> length()

        _clause ->
          :unknown
      end)

    case Enum.uniq(arities) do
      [arity] when is_integer(arity) -> arity
      _arities -> :unknown
    end
  end

  defp enum_callback_arguments(
         operation,
         invocation_arguments,
         element,
         environment
       ) do
    if operation in @enum_element_first_callback_operations do
      accumulator = enum_accumulator_argument(operation, invocation_arguments, environment)
      [element, accumulator]
    else
      [element]
    end
  end

  defp enum_accumulator_argument(operation, arguments, environment)
       when operation in @enum_element_first_callback_operations and length(arguments) == 3 do
    arguments
    |> Enum.at(1)
    |> callback_argument_result()
    |> resolve_attributes(environment)
    |> resolve_bindings(environment)
    |> resolve_struct_aliases(environment)
  end

  defp enum_accumulator_argument(_operation, _arguments, _environment),
    do: {:__unresolved_enum_callback_argument__, [], []}

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

  defp scan_for_qualifiers(qualifiers, environment, context, occurrences) do
    Enum.reduce(qualifiers, {[environment], occurrences}, fn qualifier,
                                                             {environments, occurrences} ->
      {next_environments, occurrences} =
        Enum.reduce(environments, {[], occurrences}, fn environment,
                                                        {next_environments, occurrences} ->
          {qualifier_environments, occurrences} =
            scan_for_qualifier(qualifier, environment, context, occurrences)

          {Enum.reverse(qualifier_environments, next_environments), occurrences}
        end)

      {next_environments |> Enum.reverse() |> Enum.uniq(), occurrences}
    end)
  end

  defp scan_for_qualifier(
         {:<-, _metadata, [pattern, source]},
         environment,
         context,
         occurrences
       ) do
    {source_environment, occurrences} = scan_node(source, environment, context, occurrences)
    {patterns, guards} = clause_patterns_and_guards([pattern])

    resolved_source =
      source
      |> resolve_attributes(source_environment)
      |> resolve_bindings(source_environment)
      |> resolve_struct_aliases(source_environment)

    child_environment = remove_pattern_bindings(source_environment, patterns)

    child_environments =
      if is_list(resolved_source) and static_binding_source?(resolved_source) and
           Enum.any?(resolved_source, &static_value_contains_database_receiver?(&1, environment)) do
        resolved_source
        |> Enum.uniq_by(&Macro.to_string/1)
        |> Enum.flat_map(&static_generator_environments(child_environment, patterns, &1))
      else
        [bind_generator_patterns(child_environment, patterns, resolved_source, :enumerate)]
      end

    occurrences =
      Enum.reduce(child_environments, occurrences, fn child_environment, occurrences ->
        {_guard_environment, occurrences} =
          scan_isolated_children(guards, child_environment, context, occurrences)

        occurrences
      end)

    {child_environments, occurrences}
  end

  defp scan_for_qualifier(qualifier, environment, context, occurrences) do
    {environment, occurrences} = scan_node(qualifier, environment, context, occurrences)
    {[environment], occurrences}
  end

  defp static_generator_environments(environment, patterns, value) do
    patterns = Enum.map(patterns, &resolve_struct_aliases(&1, environment))

    if Enum.all?(patterns, &static_pattern_match?(&1, value)) do
      [bind_generator_value(environment, patterns, value)]
    else
      []
    end
  end

  defp static_value_contains_database_receiver?(
         {:__aliases__, _metadata, _parts} = receiver,
         environment
       ) do
    resolved_receiver = receiver |> receiver_name() |> resolve_receiver(environment)

    resolved_receiver in @database_alias_targets or repo_receiver?(resolved_receiver) or
      resolved_receiver == "Multi"
  end

  defp static_value_contains_database_receiver?({:{}, _metadata, values}, environment),
    do: Enum.any?(values, &static_value_contains_database_receiver?(&1, environment))

  defp static_value_contains_database_receiver?({:%{}, _metadata, fields}, environment),
    do: Enum.any?(fields, &static_value_contains_database_receiver?(&1, environment))

  defp static_value_contains_database_receiver?({:%, _metadata, [module, fields]}, environment),
    do:
      static_value_contains_database_receiver?(module, environment) or
        static_value_contains_database_receiver?(fields, environment)

  defp static_value_contains_database_receiver?({left, right}, environment),
    do:
      static_value_contains_database_receiver?(left, environment) or
        static_value_contains_database_receiver?(right, environment)

  defp static_value_contains_database_receiver?(values, environment) when is_list(values),
    do: Enum.any?(values, &static_value_contains_database_receiver?(&1, environment))

  defp static_value_contains_database_receiver?(value, environment) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> Enum.any?(&static_value_contains_database_receiver?(&1, environment))
  end

  defp static_value_contains_database_receiver?(_value, _environment), do: false

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

  defp scan_classified_children(node, environment, context, occurrences) do
    case migration_table_block(node, environment, context) do
      {:ok, construct, block_options, table_target} ->
        {_construct_environment, occurrences} =
          scan_node(construct, environment, context, occurrences)

        {_options_environment, occurrences} =
          block_options
          |> Keyword.delete(:do)
          |> Keyword.values()
          |> scan_isolated_children(environment, context, occurrences)

        table_context = Map.put(context, :migration_table_target, table_target)

        {_block_environment, occurrences} =
          scan_node(Keyword.get(block_options, :do), environment, table_context, occurrences)

        {environment, occurrences}

      :error ->
        scan_children(node, environment, context, occurrences)
    end
  end

  defp migration_table_block(
         {operation, _metadata, [construct, block_options]},
         environment,
         %{migration?: true}
       )
       when operation in [:alter, :create, :create_if_not_exists] and is_list(block_options) do
    migration_table_block(operation, construct, block_options, environment)
  end

  defp migration_table_block(
         {{:., _dot_metadata, [receiver, operation]}, _metadata, [construct, block_options]},
         environment,
         %{migration?: true}
       )
       when operation in [:alter, :create, :create_if_not_exists] and is_list(block_options) do
    if migration_module_receiver?(receiver, environment),
      do: migration_table_block(operation, construct, block_options, environment),
      else: :error
  end

  defp migration_table_block(_node, _environment, _context), do: :error

  defp migration_table_block(operation, construct, block_options, environment) do
    if Keyword.keyword?(block_options) and Keyword.has_key?(block_options, :do) do
      table_targets =
        construct
        |> resolve_migration_constructs(environment, MapSet.new())
        |> Enum.flat_map(fn
          {:table, _metadata, arguments} when is_list(arguments) ->
            [
              Enum.join(
                [
                  "operation: #{operation}",
                  "target: #{migration_construct_target(:table, arguments, migration_sql_option_keys(:table))}"
                ],
                "\n"
              )
            ]

          _construct ->
            []
        end)
        |> Enum.sort()

      case table_targets do
        [] -> :error
        targets -> {:ok, construct, block_options, Enum.join(targets, "\n---\n")}
      end
    else
      :error
    end
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
    resolved_receiver = resolve_static_expression(receiver, environment)
    receiver = database_receiver_name(resolved_receiver, migration?, environment)

    classify_migration_operation(receiver, operation) ||
      classify_database_operation(receiver, operation) ||
      classify_unresolved_database_receiver(resolved_receiver, operation, environment)
  end

  defp classify_node(
         {:unresolved_database_apply, receiver, operation, _arguments},
         migration?,
         environment
       ) do
    receiver =
      receiver
      |> resolve_static_expression(environment)
      |> database_receiver_name(migration?, environment)

    operation = resolve_bindings(operation, environment)

    classify_migration_operation(receiver, operation) ||
      classify_database_operation(receiver, operation) ||
      classify_dynamic_database_apply(receiver, operation)
  end

  defp classify_node({construct, _metadata, arguments}, migration?, environment)
       when construct in [:fragment, :unsafe_fragment] and is_list(arguments) do
    if migration? or imported_fragment?(environment, construct, length(arguments)),
      do: {:raw_sql, to_string(construct)}
  end

  defp classify_node({:execute, _metadata, arguments}, true, _environment)
       when is_list(arguments),
       do: {:raw_sql, "migration.execute"}

  defp classify_node({:execute_file, _metadata, arguments}, true, _environment)
       when is_list(arguments),
       do: {:raw_sql, "migration.execute_file"}

  defp classify_node({:insert, _metadata, arguments}, true, _environment)
       when is_list(arguments),
       do: {:direct_ecto, "migration.insert"}

  defp classify_node({operation, _metadata, arguments}, _migration?, environment)
       when is_atom(operation) and is_list(arguments) do
    receiver = imported_receiver(environment, operation, length(arguments))

    classify_migration_operation(receiver, operation) ||
      classify_database_operation(receiver, operation)
  end

  defp classify_node({:unsafe_fragment, sql}, _migration?, _environment) when is_binary(sql),
    do: {:raw_sql, "unsafe_fragment"}

  defp classify_node(_node, _migration?, _environment), do: nil

  defp classify_migration_operation("Ecto.Migration", :execute),
    do: {:raw_sql, "migration.execute"}

  defp classify_migration_operation("Ecto.Migration", :execute_file),
    do: {:raw_sql, "migration.execute_file"}

  defp classify_migration_operation("Ecto.Migration", :insert),
    do: {:direct_ecto, "migration.insert"}

  defp classify_migration_operation("Ecto.Migration", :fragment),
    do: {:raw_sql, "fragment"}

  defp classify_migration_operation(_receiver, _operation), do: nil

  defp classify_database_operation(nil, _operation), do: nil

  defp classify_database_operation(receiver, operation) do
    cond do
      receiver == "Ecto.Query.API" and operation in [:fragment, :unsafe_fragment] ->
        {:raw_sql, "#{receiver}.#{operation}"}

      receiver == "Ecto.Adapters.SQL" and operation in @ecto_sql_direct_operations ->
        {:direct_ecto, "#{receiver}.#{operation}"}

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

  defp classify_unresolved_database_receiver(receiver, operation, environment) do
    if static_value_contains_database_receiver?(receiver, environment) do
      cond do
        operation in [:query, :query!] -> {:raw_sql, "Repo.#{operation}"}
        operation in @direct_repo_operations -> {:direct_ecto, "Repo.#{operation}"}
        true -> nil
      end
    end
  end

  defp classify_dynamic_database_apply(_receiver, operation) when is_atom(operation), do: nil

  defp classify_dynamic_database_apply(receiver, _operation) do
    cond do
      repo_receiver?(receiver) ->
        {:raw_sql, "Repo.apply"}

      receiver in ["Ecto.Adapters.SQL", "Ecto.Migration", "Ecto.Query.API", "Postgrex"] ->
        {:raw_sql, "#{receiver}.apply"}

      receiver == "Ecto.Multi" ->
        {:direct_ecto, "#{receiver}.apply"}

      true ->
        nil
    end
  end

  defp classify_query_sql_options(node, environment, context, occurrences) do
    with {:ok, operation, metadata, arguments} <- ecto_query_call(node, environment) do
      operation
      |> query_sql_option_entries(arguments)
      |> Enum.reduce(occurrences, fn {key, value, option_keys}, occurrences ->
        if repository_authored_query_sql?(key, value) do
          [
            occurrence(
              context.path,
              Keyword.get(metadata, :line, 1),
              context.function,
              :raw_sql,
              "Ecto.Query.#{key}",
              query_sql_option_fingerprint_input(
                operation,
                arguments,
                option_keys,
                key,
                value
              )
            )
            |> mark_sql_payload_approval(value)
            | occurrences
          ]
        else
          occurrences
        end
      end)
    else
      :error -> occurrences
    end
  end

  defp ecto_query_call(
         {{:., _dot_metadata, [receiver, operation]}, metadata, arguments},
         environment
       )
       when is_atom(operation) and is_list(arguments) do
    if receiver |> receiver_name() |> resolve_receiver(environment) == "Ecto.Query",
      do: {:ok, operation, metadata, arguments},
      else: :error
  end

  defp ecto_query_call({operation, metadata, arguments}, environment)
       when is_atom(operation) and is_list(arguments) do
    arity = length(arguments)

    if not Map.has_key?(environment.local_functions, {operation, arity}) and
         imported_receiver(environment, operation, arity) == "Ecto.Query",
       do: {:ok, operation, metadata, arguments},
       else: :error
  end

  defp ecto_query_call(_node, _environment), do: :error

  defp query_sql_option_entries(:from, arguments) when length(arguments) == 2,
    do: query_keyword_sql_option_entries(List.last(arguments), [:hints, :lock])

  defp query_sql_option_entries(:join, arguments) when length(arguments) == 5,
    do: query_keyword_sql_option_entries(List.last(arguments), [:hints])

  defp query_sql_option_entries(:lock, arguments) when length(arguments) in [2, 3],
    do: [{:lock, List.last(arguments), [:lock]}]

  defp query_sql_option_entries(_operation, _arguments), do: []

  defp query_keyword_sql_option_entries(options, option_keys) when is_list(options) do
    if Keyword.keyword?(options) do
      Enum.flat_map(options, fn
        {key, value} ->
          if key in option_keys, do: [{key, value, option_keys}], else: []

        _option ->
          []
      end)
    else
      []
    end
  end

  defp query_keyword_sql_option_entries(_options, _option_keys), do: []

  defp repository_authored_query_sql?(:hints, []), do: false
  defp repository_authored_query_sql?(:lock, value) when value in [nil, true, false], do: false
  defp repository_authored_query_sql?(_key, _value), do: true

  defp query_sql_option_fingerprint_input(
         operation,
         arguments,
         option_keys,
         key,
         value
       ) do
    target_arguments = query_sql_option_target_arguments(operation, arguments, option_keys)

    Enum.join(
      [
        "query: #{Macro.to_string({operation, [], target_arguments})}",
        "option: #{key}",
        "value: #{Macro.to_string(value)}"
      ],
      "\n"
    )
  end

  defp query_sql_option_target_arguments(operation, arguments, option_keys)
       when operation in [:from, :join] do
    case List.last(arguments) do
      options when is_list(options) ->
        List.replace_at(arguments, -1, Keyword.drop(options, option_keys))

      _options ->
        arguments
    end
  end

  defp query_sql_option_target_arguments(:lock, arguments, _option_keys),
    do: List.delete_at(arguments, -1)

  defp query_sql_option_target_arguments(_operation, arguments, _option_keys), do: arguments

  defp classify_migration_sql_options(
         {operation, metadata, [construct_or_helper | _trailing_arguments]},
         environment,
         %{migration?: true} = context,
         occurrences
       )
       when operation in @migration_create_operations do
    classify_migration_constructs(
      operation,
      metadata,
      construct_or_helper,
      environment,
      context,
      occurrences
    )
  end

  defp classify_migration_sql_options(
         {operation, metadata, arguments},
         _environment,
         %{migration?: true, migration_table_target: table_target} = context,
         occurrences
       )
       when operation in [:add, :modify] and is_list(arguments) do
    classify_migration_column_sql_option(
      operation,
      metadata,
      arguments,
      table_target,
      context,
      occurrences
    )
  end

  defp classify_migration_sql_options(
         {{:., _dot_metadata, [receiver, operation]}, metadata, arguments},
         environment,
         %{migration?: true, migration_table_target: table_target} = context,
         occurrences
       )
       when operation in [:add, :modify] and is_list(arguments) do
    if migration_module_receiver?(receiver, environment) do
      classify_migration_column_sql_option(
        operation,
        metadata,
        arguments,
        table_target,
        context,
        occurrences
      )
    else
      occurrences
    end
  end

  defp classify_migration_sql_options(
         {{:., _dot_metadata, [receiver, operation]}, metadata,
          [construct_or_helper | _trailing_arguments]},
         environment,
         %{migration?: true} = context,
         occurrences
       )
       when operation in @migration_create_operations do
    if migration_module_receiver?(receiver, environment) do
      classify_migration_constructs(
        operation,
        metadata,
        construct_or_helper,
        environment,
        context,
        occurrences
      )
    else
      occurrences
    end
  end

  defp classify_migration_sql_options(_node, _environment, _context, occurrences),
    do: occurrences

  defp classify_migration_column_sql_option(
         operation,
         metadata,
         arguments,
         table_target,
         context,
         occurrences
       ) do
    case List.last(arguments) do
      options when is_list(options) ->
        if Keyword.keyword?(options) do
          classify_generated_column_option(
            operation,
            metadata,
            arguments,
            options,
            table_target,
            context,
            occurrences
          )
        else
          occurrences
        end

      _options ->
        occurrences
    end
  end

  defp classify_generated_column_option(
         operation,
         metadata,
         arguments,
         options,
         table_target,
         context,
         occurrences
       ) do
    case Keyword.fetch(options, :generated) do
      {:ok, value} ->
        fingerprint_input =
          Enum.join(
            [
              table_target,
              "column: #{migration_construct_target(operation, arguments, [:generated])}",
              "option: generated",
              "value: #{Macro.to_string(value)}"
            ],
            "\n"
          )

        [
          occurrence(
            context.path,
            Keyword.get(metadata, :line, 1),
            context.function,
            :raw_sql,
            "migration.generated",
            fingerprint_input
          )
          |> mark_sql_payload_approval(value)
          | occurrences
        ]

      :error ->
        occurrences
    end
  end

  defp classify_migration_constructs(
         operation,
         metadata,
         construct_or_helper,
         environment,
         context,
         occurrences
       ) do
    construct_or_helper
    |> resolve_migration_constructs(environment, MapSet.new())
    |> Enum.reduce(occurrences, fn construct_node, occurrences ->
      classify_migration_construct_sql_options(
        operation,
        Keyword.get(metadata, :line, 1),
        construct_node,
        context,
        occurrences
      )
    end)
  end

  defp classify_migration_construct_sql_options(
         operation,
         line,
         {construct, _construct_metadata, arguments},
         context,
         occurrences
       )
       when construct in @migration_sql_option_constructs and is_list(arguments) do
    option_keys = migration_sql_option_keys(construct)

    occurrences =
      classify_migration_index_expression_fields(
        operation,
        line,
        construct,
        arguments,
        option_keys,
        context,
        occurrences
      )

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
                |> mark_sql_payload_approval(value)
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

  defp classify_migration_construct_sql_options(
         _operation,
         _line,
         _construct_node,
         _context,
         occurrences
       ),
       do: occurrences

  defp classify_migration_index_expression_fields(
         operation,
         line,
         construct,
         arguments,
         option_keys,
         context,
         occurrences
       )
       when construct in [:index, :unique_index] do
    case Enum.at(arguments, 1) do
      fields when is_list(fields) ->
        fields
        |> Enum.with_index()
        |> Enum.reduce(occurrences, fn {field, index}, occurrences ->
          case migration_index_expression_payload(field) do
            :safe_column ->
              occurrences

            {:raw_sql, payload} ->
              [
                occurrence(
                  context.path,
                  line,
                  context.function,
                  :raw_sql,
                  "migration.index_expression",
                  migration_index_expression_fingerprint_input(
                    operation,
                    construct,
                    arguments,
                    option_keys,
                    index,
                    field
                  )
                )
                |> mark_sql_payload_approval(payload)
                | occurrences
              ]
          end
        end)

      field when is_atom(field) ->
        occurrences

      unresolved_fields ->
        [
          occurrence(
            context.path,
            line,
            context.function,
            :raw_sql,
            "migration.index_expression",
            migration_index_expression_fingerprint_input(
              operation,
              construct,
              arguments,
              option_keys,
              :unresolved,
              unresolved_fields
            )
          )
          |> mark_sql_payload_approval(unresolved_fields)
          | occurrences
        ]
    end
  end

  defp classify_migration_index_expression_fields(
         _operation,
         _line,
         _construct,
         _arguments,
         _option_keys,
         _context,
         occurrences
       ),
       do: occurrences

  defp migration_index_expression_payload(field) when is_atom(field), do: :safe_column

  defp migration_index_expression_payload({direction, field})
       when direction in [
              :asc,
              :asc_nulls_first,
              :asc_nulls_last,
              :desc,
              :desc_nulls_first,
              :desc_nulls_last
            ] and is_atom(field),
       do: :safe_column

  defp migration_index_expression_payload({direction, field})
       when direction in [
              :asc,
              :asc_nulls_first,
              :asc_nulls_last,
              :desc,
              :desc_nulls_first,
              :desc_nulls_last
            ] and is_binary(field),
       do: {:raw_sql, field}

  defp migration_index_expression_payload(field), do: {:raw_sql, field}

  defp resolve_migration_constructs(node, environment, resolving) do
    resolved_node =
      node
      |> resolve_attributes(environment)
      |> resolve_bindings(environment)

    do_resolve_migration_constructs(resolved_node, environment, resolving)
  end

  defp do_resolve_migration_constructs(
         {construct, _metadata, arguments} = node,
         _environment,
         _resolving
       )
       when construct in @migration_sql_option_constructs and is_list(arguments),
       do: [node]

  defp do_resolve_migration_constructs(
         {{:., _dot_metadata, [receiver, construct]}, metadata, arguments},
         environment,
         _resolving
       )
       when construct in @migration_sql_option_constructs and is_list(arguments) do
    if migration_module_receiver?(receiver, environment),
      do: [{construct, metadata, arguments}],
      else: []
  end

  defp do_resolve_migration_constructs(
         {:__block__, _metadata, expressions},
         environment,
         resolving
       )
       when is_list(expressions),
       do: resolve_migration_return_sequence(expressions, environment, resolving)

  defp do_resolve_migration_constructs(
         {branch, _metadata, [_condition, options]},
         environment,
         resolving
       )
       when branch in [:if, :unless] and is_list(options) do
    options
    |> Keyword.take([:do, :else])
    |> Keyword.values()
    |> Enum.flat_map(&resolve_migration_constructs(&1, environment, resolving))
  end

  defp do_resolve_migration_constructs(
         {branch, _metadata, arguments},
         environment,
         resolving
       )
       when branch in [:case, :cond, :with] and is_list(arguments) do
    arguments
    |> List.last()
    |> case do
      options when is_list(options) ->
        options
        |> Keyword.take([:do, :else])
        |> Keyword.values()
        |> Enum.flat_map(&migration_clause_bodies/1)
        |> Enum.flat_map(&resolve_migration_constructs(&1, environment, resolving))

      _not_options ->
        []
    end
  end

  defp do_resolve_migration_constructs(
         {name, _metadata, arguments},
         environment,
         resolving
       )
       when is_atom(name) and (is_list(arguments) or is_nil(arguments)) do
    arguments = arguments || []
    key = {name, length(arguments)}

    if MapSet.member?(resolving, key) do
      []
    else
      environment.local_functions
      |> Map.get(key, [])
      |> matching_local_definitions(arguments, environment)
      |> Enum.flat_map(fn definition ->
        child_environment = bind_local_function_arguments(definition, arguments, environment)
        {body, child_environment} = expand_local_definition(definition, child_environment)

        resolve_migration_constructs(
          body,
          child_environment,
          MapSet.put(resolving, key)
        )
      end)
    end
  end

  defp do_resolve_migration_constructs(_node, _environment, _resolving), do: []

  defp expand_local_definition(%{body: body, kind: :function}, environment),
    do: {body, environment}

  defp expand_local_definition(%{body: body, kind: :macro}, environment) do
    {expand_local_macro_body(body, environment), %{environment | bindings: %{}}}
  end

  defp expand_local_macro_body({:quote, _metadata, arguments}, environment)
       when is_list(arguments) do
    options = local_quote_options(arguments)

    body =
      if local_quote_unquotes?(options) do
        options
        |> Keyword.get(:do)
        |> Macro.postwalk(fn
          {:unquote, _metadata, [expression]} ->
            expression
            |> resolve_attributes(environment)
            |> resolve_bindings(environment)

          node ->
            node
        end)
      else
        Keyword.get(options, :do)
      end

    quoted_environment = %{
      environment
      | bindings: local_bind_quoted_bindings(options, environment)
    }

    body
    |> resolve_attributes(quoted_environment)
    |> resolve_bindings(quoted_environment)
  end

  defp expand_local_macro_body(body, environment) do
    body
    |> resolve_attributes(environment)
    |> resolve_bindings(environment)
  end

  defp local_quote_options(arguments) do
    Enum.flat_map(arguments, fn
      options when is_list(options) ->
        if Keyword.keyword?(options), do: options, else: []

      _argument ->
        []
    end)
  end

  defp local_quote_unquotes?(options) do
    Keyword.get(options, :unquote, not Keyword.has_key?(options, :bind_quoted))
  end

  defp local_bind_quoted_bindings(options, environment) do
    options
    |> Keyword.get(:bind_quoted, [])
    |> Enum.reduce(%{}, fn
      {name, expression}, bindings when is_atom(name) ->
        expression =
          expression
          |> resolve_attributes(environment)
          |> resolve_bindings(environment)

        Map.put(bindings, name, expression)

      _binding, bindings ->
        bindings
    end)
  end

  defp resolve_migration_return_sequence([], _environment, _resolving), do: []

  defp resolve_migration_return_sequence([expression], environment, resolving),
    do: resolve_migration_constructs(expression, environment, resolving)

  defp resolve_migration_return_sequence(
         [{:=, _metadata, [pattern, value]} | expressions],
         environment,
         resolving
       ) do
    resolved_pattern = resolve_struct_aliases(pattern, environment)

    resolved_value =
      value
      |> resolve_attributes(environment)
      |> resolve_bindings(environment)
      |> resolve_struct_aliases(environment)

    bindings = bind_pattern(resolved_pattern, resolved_value, environment.bindings)

    resolve_migration_return_sequence(
      expressions,
      %{environment | bindings: bindings},
      resolving
    )
  end

  defp resolve_migration_return_sequence([_expression | expressions], environment, resolving),
    do: resolve_migration_return_sequence(expressions, environment, resolving)

  defp migration_clause_bodies(clauses) when is_list(clauses),
    do: Enum.flat_map(clauses, &migration_clause_bodies/1)

  defp migration_clause_bodies({:->, _metadata, [_patterns, body]}), do: [body]
  defp migration_clause_bodies(_clause), do: []

  defp matching_local_definitions(definitions, arguments, environment) do
    definitions
    |> Enum.reduce_while([], fn definition, matches ->
      definition_environment = local_definition_environment(definition, environment)

      parameters =
        definition
        |> supplied_local_parameters()
        |> Enum.map(fn parameter ->
          parameter
          |> local_parameter_pattern()
          |> resolve_struct_aliases(definition_environment)
        end)

      {pattern_status, _bindings} = match_local_parameters(parameters, arguments)

      guard_status =
        definition.guards
        |> Enum.map(
          &resolve_bindings(&1, bind_local_function_arguments(definition, arguments, environment))
        )
        |> local_guards_match()

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

  defp match_local_parameters(patterns, arguments) do
    patterns
    |> Enum.zip(arguments)
    |> Enum.reduce({:match, %{}}, fn {pattern, argument}, {status, bindings} ->
      {next_status, bindings} = match_local_parameter(pattern, argument, bindings)
      {combine_local_match_status(status, next_status), bindings}
    end)
  end

  defp match_local_parameter({:^, _metadata, [_pattern]}, _argument, bindings),
    do: {:unknown, bindings}

  defp match_local_parameter({name, _metadata, binding_context}, argument, bindings)
       when is_atom(name) and (is_atom(binding_context) or is_nil(binding_context)) do
    cond do
      name == :_ ->
        {:match, bindings}

      Map.has_key?(bindings, name) ->
        {repeated_local_binding_status(Map.fetch!(bindings, name), argument), bindings}

      true ->
        {:match, Map.put(bindings, name, argument)}
    end
  end

  defp match_local_parameter(
         {:{}, _pattern_metadata, patterns},
         {:{}, _argument_metadata, arguments},
         bindings
       ) do
    if length(patterns) == length(arguments),
      do: match_local_parameter_elements(patterns, arguments, bindings),
      else: {:no_match, bindings}
  end

  defp match_local_parameter(
         {left_pattern, right_pattern},
         {left_argument, right_argument},
         bindings
       ) do
    {left_status, bindings} = match_local_parameter(left_pattern, left_argument, bindings)
    {right_status, bindings} = match_local_parameter(right_pattern, right_argument, bindings)
    {combine_local_match_status(left_status, right_status), bindings}
  end

  defp match_local_parameter(patterns, arguments, bindings)
       when is_list(patterns) and is_list(arguments) do
    if length(patterns) == length(arguments),
      do: match_local_parameter_elements(patterns, arguments, bindings),
      else: {:no_match, bindings}
  end

  defp match_local_parameter(pattern, argument, bindings)
       when is_atom(pattern) or is_binary(pattern) or is_number(pattern) do
    status =
      cond do
        pattern === argument -> :match
        static_binding_source?(argument) -> :no_match
        true -> :unknown
      end

    {status, bindings}
  end

  defp match_local_parameter(_pattern, _argument, bindings), do: {:unknown, bindings}

  defp match_local_parameter_elements(patterns, arguments, bindings) do
    patterns
    |> Enum.zip(arguments)
    |> Enum.reduce({:match, bindings}, fn {pattern, argument}, {status, bindings} ->
      {next_status, bindings} = match_local_parameter(pattern, argument, bindings)
      {combine_local_match_status(status, next_status), bindings}
    end)
  end

  defp combine_local_match_status(:no_match, _status), do: :no_match
  defp combine_local_match_status(_status, :no_match), do: :no_match
  defp combine_local_match_status(:unknown, _status), do: :unknown
  defp combine_local_match_status(_status, :unknown), do: :unknown
  defp combine_local_match_status(:match, :match), do: :match

  defp repeated_local_binding_status(existing, argument) do
    if Macro.to_string(existing) == Macro.to_string(argument) do
      :match
    else
      with {:known, existing} <- static_local_guard_value(existing),
           {:known, argument} <- static_local_guard_value(argument) do
        if existing === argument, do: :match, else: :no_match
      end
    end
  end

  defp local_guards_match(guards) do
    Enum.reduce(guards, :match, fn guard, status ->
      combine_local_guard_and(status, static_local_guard_result(guard))
    end)
  end

  defp static_local_guard_result(true), do: :match
  defp static_local_guard_result(false), do: :no_match
  defp static_local_guard_result(nil), do: :no_match

  defp static_local_guard_result({:when, _metadata, guards}) when is_list(guards) do
    Enum.reduce(guards, :no_match, fn guard, status ->
      combine_local_guard_or(status, static_local_guard_result(guard))
    end)
  end

  defp static_local_guard_result({operation, _metadata, [left, right]})
       when operation in [:and, :or] do
    left_status = static_local_guard_result(left)
    right_status = static_local_guard_result(right)

    case operation do
      :and -> combine_local_guard_and(left_status, right_status)
      :or -> combine_local_guard_or(left_status, right_status)
    end
  end

  defp static_local_guard_result({operation, _metadata, [left, right]})
       when operation in [:==, :===, :!=, :!==] do
    with {:known, left} <- static_local_guard_value(left),
         {:known, right} <- static_local_guard_value(right) do
      matches? =
        case operation do
          :== -> left == right
          :=== -> left === right
          :!= -> left != right
          :!== -> left !== right
        end

      if matches?, do: :match, else: :no_match
    end
  end

  defp static_local_guard_result(_guard), do: :unknown

  defp static_local_guard_value(value)
       when is_atom(value) or is_binary(value) or is_number(value),
       do: {:known, value}

  defp static_local_guard_value(values) when is_list(values),
    do: static_local_guard_values(values, [])

  defp static_local_guard_value({:{}, _metadata, values}) do
    case static_local_guard_values(values, []) do
      {:known, values} -> {:known, List.to_tuple(values)}
      :unknown -> :unknown
    end
  end

  defp static_local_guard_value({left, right}) do
    with {:known, left} <- static_local_guard_value(left),
         {:known, right} <- static_local_guard_value(right),
         do: {:known, {left, right}}
  end

  defp static_local_guard_value(_value), do: :unknown

  defp static_local_guard_values([], values), do: {:known, Enum.reverse(values)}

  defp static_local_guard_values([value | remaining], values) do
    case static_local_guard_value(value) do
      {:known, value} -> static_local_guard_values(remaining, [value | values])
      :unknown -> :unknown
    end
  end

  defp combine_local_guard_and(:no_match, _status), do: :no_match
  defp combine_local_guard_and(_status, :no_match), do: :no_match
  defp combine_local_guard_and(:unknown, _status), do: :unknown
  defp combine_local_guard_and(_status, :unknown), do: :unknown
  defp combine_local_guard_and(:match, :match), do: :match

  defp combine_local_guard_or(:match, _status), do: :match
  defp combine_local_guard_or(_status, :match), do: :match
  defp combine_local_guard_or(:unknown, _status), do: :unknown
  defp combine_local_guard_or(_status, :unknown), do: :unknown
  defp combine_local_guard_or(:no_match, :no_match), do: :no_match

  defp bind_local_function_arguments(definition, arguments, environment) do
    environment = local_definition_environment(definition, environment)

    bindings =
      definition
      |> supplied_local_parameters()
      |> Enum.zip(arguments)
      |> Enum.reduce(environment.bindings, fn {parameter, argument}, bindings ->
        pattern = parameter |> local_parameter_pattern() |> resolve_struct_aliases(environment)
        bind_pattern(pattern, argument, bindings)
      end)

    environment = %{environment | bindings: bindings}

    definition.parameters
    |> Enum.with_index()
    |> Enum.reduce(environment, fn
      {{:\\, _metadata, [pattern, default]}, index}, environment ->
        if MapSet.member?(definition.omitted_indexes, index) do
          resolved_default =
            default
            |> resolve_attributes(environment)
            |> resolve_bindings(environment)
            |> resolve_struct_aliases(environment)

          pattern = resolve_struct_aliases(pattern, environment)
          %{environment | bindings: bind_pattern(pattern, resolved_default, environment.bindings)}
        else
          environment
        end

      _parameter, environment ->
        environment
    end)
  end

  defp local_definition_environment(definition, environment) do
    environment
    |> Map.merge(Map.get(definition, :definition_environment, %{}))
    |> Map.put(:bindings, %{})
  end

  defp supplied_local_parameters(definition) do
    definition.parameters
    |> Enum.with_index()
    |> Enum.reject(fn {_parameter, index} ->
      MapSet.member?(definition.omitted_indexes, index)
    end)
    |> Enum.map(&elem(&1, 0))
  end

  defp local_parameter_pattern({:\\, _metadata, [pattern, _default]}), do: pattern
  defp local_parameter_pattern(pattern), do: pattern

  defp migration_sql_option_keys(:constraint), do: [:check, :exclude]

  defp migration_sql_option_keys(:table), do: [:modifiers, :options]

  defp migration_sql_option_keys(construct) when construct in [:index, :unique_index],
    do: [:options, :where]

  defp mark_sql_approval(occurrence, :raw_sql, "migration.execute_file", node) do
    with {:ok, payloads} <- raw_sql_payloads(node, "migration.execute_file"),
         {:ok, paths} <- static_execute_file_paths(payloads) do
      Map.put(occurrence, :execute_file_paths, paths)
    else
      _unresolved -> Map.put(occurrence, :approval, :unresolved_sql)
    end
  end

  defp mark_sql_approval(occurrence, :raw_sql, construct, node) do
    case raw_sql_payloads(node, construct) do
      {:ok, payloads} -> mark_sql_payloads_approval(occurrence, payloads)
      :error -> Map.put(occurrence, :approval, :unresolved_sql)
    end
  end

  defp mark_sql_approval(occurrence, _class, _construct, _node), do: occurrence

  defp mark_sql_payloads_approval(occurrence, payloads) do
    if Enum.all?(payloads, &static_sql_payload?/1),
      do: occurrence,
      else: Map.put(occurrence, :approval, :unresolved_sql)
  end

  defp mark_sql_payload_approval(occurrence, payload) do
    if static_sql_payload?(payload),
      do: occurrence,
      else: Map.put(occurrence, :approval, :unresolved_sql)
  end

  defp raw_sql_payloads(
         {{:., _dot_metadata, [_receiver, _operation]}, _metadata, arguments},
         construct
       )
       when is_list(arguments) do
    fetch_sql_arguments(arguments, construct)
  end

  defp raw_sql_payloads({_operation, _metadata, arguments}, construct)
       when is_list(arguments) do
    fetch_sql_arguments(arguments, construct)
  end

  defp raw_sql_payloads({:unsafe_fragment, payload}, "unsafe_fragment"), do: {:ok, [payload]}
  defp raw_sql_payloads(_node, _construct), do: :error

  defp fetch_sql_arguments(arguments, "migration.execute") do
    if length(arguments) in [1, 2], do: {:ok, arguments}, else: :error
  end

  defp fetch_sql_arguments(arguments, "migration.execute_file") do
    if length(arguments) in [1, 2], do: {:ok, arguments}, else: :error
  end

  defp fetch_sql_arguments(arguments, construct) do
    case fetch_sql_argument(arguments, construct) do
      {:ok, argument} -> {:ok, [argument]}
      :error -> :error
    end
  end

  defp fetch_sql_argument(arguments, "Ecto.Adapters.SQL." <> _operation),
    do: fetch_argument(arguments, 1)

  defp fetch_sql_argument(arguments, "Postgrex." <> operation)
       when operation in ["prepare", "prepare!", "prepare_execute", "prepare_execute!"],
       do: fetch_argument(arguments, 2)

  defp fetch_sql_argument(arguments, "Postgrex." <> _operation),
    do: fetch_argument(arguments, 1)

  defp fetch_sql_argument(arguments, _construct), do: fetch_argument(arguments, 0)

  defp fetch_argument(arguments, index) do
    case Enum.fetch(arguments, index) do
      {:ok, argument} -> {:ok, argument}
      :error -> :error
    end
  end

  defp static_sql_payload?({operator, _metadata, [left, right]}) when operator in [:<>, :++],
    do: static_sql_payload?(left) and static_sql_payload?(right)

  defp static_sql_payload?({:<<>>, _metadata, segments}) when is_list(segments),
    do: Enum.all?(segments, &static_sql_bitstring_segment?/1)

  defp static_sql_payload?(payload), do: Macro.quoted_literal?(payload)

  defp static_sql_bitstring_segment?(segment) when is_binary(segment), do: true

  defp static_sql_bitstring_segment?(
         {:"::", _metadata,
          [
            {{:., _dot_metadata, [Kernel, :to_string]}, interpolation_metadata, [value]},
            {:binary, _binary_metadata, nil}
          ]}
       ) do
    Keyword.get(interpolation_metadata, :from_interpolation, false) and
      static_sql_payload?(value)
  end

  defp static_sql_bitstring_segment?(segment), do: Macro.quoted_literal?(segment)

  defp static_execute_file_paths(payloads) do
    Enum.reduce_while(payloads, {:ok, []}, fn payload, {:ok, paths} ->
      case static_execute_file_path(payload) do
        {:ok, path} -> {:cont, {:ok, [path | paths]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, paths} -> {:ok, Enum.reverse(paths)}
      :error -> :error
    end
  end

  defp static_execute_file_path(path) when is_binary(path), do: {:ok, path}

  defp static_execute_file_path({:<>, _metadata, [left, right]}) do
    with {:ok, left} <- static_execute_file_path(left),
         {:ok, right} <- static_execute_file_path(right),
         do: {:ok, left <> right}
  end

  defp static_execute_file_path({:<<>>, _metadata, segments}) when is_list(segments) do
    Enum.reduce_while(segments, {:ok, []}, fn segment, {:ok, values} ->
      case static_execute_file_path_segment(segment) do
        {:ok, value} -> {:cont, {:ok, [value | values]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, values |> Enum.reverse() |> IO.iodata_to_binary()}
      :error -> :error
    end
  end

  defp static_execute_file_path(_path), do: :error

  defp static_execute_file_path_segment(segment) when is_binary(segment), do: {:ok, segment}

  defp static_execute_file_path_segment(
         {:"::", _metadata,
          [
            {{:., _dot_metadata, [Kernel, :to_string]}, interpolation_metadata, [value]},
            {:binary, _binary_metadata, nil}
          ]}
       ) do
    if Keyword.get(interpolation_metadata, :from_interpolation, false),
      do: static_execute_file_interpolation(value),
      else: :error
  end

  defp static_execute_file_path_segment(_segment), do: :error

  defp static_execute_file_interpolation(value)
       when is_atom(value) or is_binary(value) or is_number(value),
       do: {:ok, to_string(value)}

  defp static_execute_file_interpolation(value) when is_list(value) do
    if Enum.all?(value, &is_integer/1), do: {:ok, List.to_string(value)}, else: :error
  end

  defp static_execute_file_interpolation(_value), do: :error

  defp migration_sql_option_fingerprint_input(
         operation,
         construct,
         arguments,
         option_keys,
         key,
         value
       ) do
    target = migration_construct_target(construct, arguments, option_keys)

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

  defp migration_index_expression_fingerprint_input(
         operation,
         construct,
         arguments,
         option_keys,
         index,
         field
       ) do
    target = migration_construct_target(construct, arguments, option_keys)

    Enum.join(
      [
        "operation: #{operation}",
        "target: #{target}",
        "field: #{index}",
        "value: #{Macro.to_string(field)}"
      ],
      "\n"
    )
  end

  defp migration_construct_target(construct, arguments, option_keys) do
    target_arguments =
      case List.last(arguments) do
        options when is_list(options) ->
          target_options =
            Enum.reject(options, fn
              {option_key, _value} -> option_key in option_keys
              _option -> false
            end)

          List.replace_at(arguments, -1, target_options)

        _not_options ->
          arguments
      end

    {construct, [], target_arguments}
    |> Macro.to_string()
  end

  defp empty_environment do
    %{
      aliases: %{},
      attribute_modes: %{},
      attributes: %{},
      bindings: %{},
      imports: [],
      local_functions: %{},
      uncertain_attribute_registration?: false
    }
  end

  defp module_attribute_registration?(receiver, [module | _arguments], environment) do
    receiver |> receiver_name() |> resolve_receiver(environment) == "Module" and
      match?({:__MODULE__, _metadata, _context}, module)
  end

  defp register_module_attribute(environment, [_module, name | arguments]) do
    name =
      name
      |> resolve_attributes(environment)
      |> resolve_bindings(environment)

    options =
      arguments
      |> List.first([])
      |> resolve_attributes(environment)
      |> resolve_bindings(environment)

    case name do
      name when is_atom(name) ->
        mode = module_attribute_mode(options)

        %{
          environment
          | attribute_modes: Map.put(environment.attribute_modes, name, mode),
            attributes:
              if(mode == :unknown,
                do: Map.delete(environment.attributes, name),
                else: environment.attributes
              )
        }

      _dynamic_name ->
        %{environment | uncertain_attribute_registration?: true}
    end
  end

  defp module_attribute_mode(options) when is_list(options) do
    if Keyword.keyword?(options) do
      case Keyword.fetch(options, :accumulate) do
        :error -> :single
        {:ok, true} -> :accumulate
        {:ok, false} -> :single
        {:ok, _dynamic} -> :unknown
      end
    else
      :unknown
    end
  end

  defp module_attribute_mode(_options), do: :unknown

  defp put_module_attribute_value(environment, name, value) do
    mode =
      if environment.uncertain_attribute_registration? do
        :unknown
      else
        Map.get(environment.attribute_modes, name, :single)
      end

    attributes =
      case mode do
        :single ->
          Map.put(environment.attributes, name, value)

        :accumulate ->
          case Map.fetch(environment.attributes, name) do
            :error ->
              Map.put(environment.attributes, name, [value])

            {:ok, values} when is_list(values) ->
              Map.put(environment.attributes, name, [value | values])

            {:ok, _incompatible_value} ->
              Map.delete(environment.attributes, name)
          end

        :unknown ->
          Map.delete(environment.attributes, name)
      end

    %{environment | attributes: attributes}
  end

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

  defp resolve_static_expression(node, environment) do
    node
    |> resolve_attributes(environment)
    |> resolve_bindings(environment)
    |> resolve_struct_aliases(environment)
    |> Macro.postwalk(&resolve_static_projection(&1, environment))
  end

  defp resolve_static_projection(
         {{:., _dot_metadata, [container, field]}, _metadata, []} = projection,
         _environment
       )
       when is_atom(field) do
    case static_projection_fields(container) do
      {:ok, fields} ->
        case fetch_static_field(fields, field) do
          {:ok, value} -> value
          :error -> projection
        end

      :error ->
        projection
    end
  end

  defp resolve_static_projection(
         {{:., _dot_metadata, [receiver, operation]}, _metadata, [container, field]} = projection,
         environment
       )
       when operation in [:fetch!, :get] do
    if receiver |> receiver_name() |> resolve_receiver(environment) == "Map" do
      case static_projection_fields(container) do
        {:ok, fields} ->
          case fetch_static_field(fields, field) do
            {:ok, value} -> value
            :error -> projection
          end

        :error ->
          projection
      end
    else
      projection
    end
  end

  defp resolve_static_projection(node, _environment), do: node

  defp static_projection_fields({:%{}, _metadata, fields}) when is_list(fields),
    do: {:ok, fields}

  defp static_projection_fields({:%, _metadata, [_module, {:%{}, _map_metadata, fields}]})
       when is_list(fields),
       do: {:ok, fields}

  defp static_projection_fields(_container), do: :error

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

  defp put_use_import(environment, [target | _options]) do
    if migration_module_receiver?(target, environment),
      do: apply_ecto_migration_use_import(environment, target),
      else: environment
  end

  defp put_use_import(environment, _arguments), do: environment

  defp apply_ecto_migration_use_import(environment, target) do
    case target |> receiver_name() |> resolve_receiver(environment) do
      "Ecto.Migration" = target_name ->
        declaration = %{
          except: nil,
          mode: :ecto_migration_use,
          only: nil,
          target: target_name
        }

        %{environment | imports: [declaration | environment.imports]}

      _not_ecto_migration ->
        environment
    end
  end

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

  defp explicitly_imported_receiver(environment, operation, arity) do
    Enum.find_value(environment.imports, fn declaration ->
      if explicit_import_applies?(declaration, operation, arity), do: declaration.target
    end)
  end

  defp explicit_import_applies?(%{mode: :ecto_migration_use}, operation, arity),
    do: ecto_migration_use_import?(operation, arity)

  defp explicit_import_applies?(%{only: %MapSet{} = only}, operation, arity),
    do: MapSet.member?(only, {operation, arity})

  defp explicit_import_applies?(%{except: %MapSet{} = except}, operation, arity),
    do: not MapSet.member?(except, {operation, arity})

  defp explicit_import_applies?(%{only: nil, except: nil}, _operation, _arity), do: true

  defp imported_fragment?(environment, operation, arity) do
    Enum.any?(environment.imports, fn declaration ->
      declaration.target in @ecto_fragment_import_targets and
        import_applies?(declaration, operation, arity)
    end)
  end

  defp import_applies?(%{mode: :ecto_migration_use}, operation, arity),
    do: ecto_migration_use_import?(operation, arity)

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

  defp ecto_migration_use_import?(:fragment, arity), do: arity >= 1

  defp ecto_migration_use_import?(operation, arity),
    do: MapSet.member?(@ecto_migration_use_fixed_imports, {operation, arity})

  defp receiver_name({:__aliases__, _metadata, parts}) do
    if Enum.all?(parts, &is_atom/1), do: Enum.join(parts, ".")
  end

  defp receiver_name({name, _metadata, context}) when is_atom(name) and is_atom(context),
    do: to_string(name)

  defp receiver_name(_receiver), do: nil

  defp database_receiver_name(receiver, true, environment) do
    if migration_repo_call?(receiver, environment) do
      @migration_repo_receiver
    else
      receiver |> receiver_name() |> resolve_receiver(environment)
    end
  end

  defp database_receiver_name(receiver, false, environment) do
    if external_migration_repo_call?(receiver, environment),
      do: @migration_repo_receiver,
      else: receiver |> receiver_name() |> resolve_receiver(environment)
  end

  defp external_migration_repo_call?({:repo, _metadata, arguments}, environment)
       when arguments in [nil, []],
       do: imported_receiver(environment, :repo, 0) == "Ecto.Migration"

  defp external_migration_repo_call?(
         {{:., _dot_metadata, [receiver, :repo]}, _metadata, arguments},
         environment
       )
       when arguments in [nil, []],
       do: migration_module_receiver?(receiver, environment)

  defp external_migration_repo_call?(_receiver, _environment), do: false

  defp migration_repo_call?({:repo, _metadata, arguments}, _environment)
       when arguments in [nil, []],
       do: true

  defp migration_repo_call?(
         {{:., _dot_metadata, [receiver, :repo]}, _metadata, arguments},
         environment
       )
       when arguments in [nil, []] do
    receiver |> receiver_name() |> resolve_receiver(environment) == "Ecto.Migration"
  end

  defp migration_repo_call?(_receiver, _environment), do: false

  defp migration_module_receiver?(receiver, environment) do
    receiver |> receiver_name() |> resolve_receiver(environment) == "Ecto.Migration"
  end

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

  defp repo_receiver?(receiver),
    do: receiver in ["Repo", "OfficeGraph.Repo", @migration_repo_receiver]

  defp node_line({{:., _dot_metadata, _receiver_and_operation}, metadata, _arguments}),
    do: Keyword.get(metadata, :line, 1)

  defp node_line({_name, metadata, _arguments}) when is_list(metadata),
    do: Keyword.get(metadata, :line, 1)

  defp node_line(_node), do: 1

  defp eligible_source?(%{path: path}), do: eligible_path?(path)

  defp resolve_execute_file_occurrences(occurrences, file_resolver) do
    Enum.map(occurrences, fn
      %{execute_file_paths: paths} = occurrence ->
        resolved_files =
          Enum.reduce_while(paths, {:ok, []}, fn path, {:ok, files} ->
            with {:ok, path} <- normalize_execute_file_path(path),
                 {:ok, contents} <- file_resolver.(path) do
              content_fingerprint =
                contents
                |> then(&:crypto.hash(:sha256, &1))
                |> Base.encode16(case: :lower)

              {:cont, {:ok, [{path, content_fingerprint} | files]}}
            else
              _unavailable -> {:halt, :error}
            end
          end)

        occurrence = Map.delete(occurrence, :execute_file_paths)

        case resolved_files do
          {:ok, files} ->
            file_fingerprints =
              files
              |> Enum.reverse()
              |> Enum.map_join("\n", fn {path, fingerprint} ->
                "execute_file: #{path}\ncontent_sha256: #{fingerprint}"
              end)

            Map.update!(occurrence, :normalized, &Enum.join([&1, file_fingerprints], "\n"))

          :error ->
            Map.put(occurrence, :approval, :unresolved_sql)
        end

      occurrence ->
        occurrence
    end)
  end

  defp eligible_path?(path) do
    path = String.trim_leading(path, "./")
    extension = Path.extname(path)

    not excluded_path?(path) and extension in [".ex", ".exs", ".sql"]
  end

  defp excluded_path?(path) do
    Enum.any?(String.split(path, "/"), &(&1 in ["_build", "deps", "node_modules"]))
  end

  defp normalize_source_path(path) do
    case normalize_execute_file_path(path) do
      {:ok, path} -> path
      :error -> path
    end
  end

  defp normalize_execute_file_path(path) when is_binary(path) do
    if Path.type(path) == :relative do
      path
      |> Path.split()
      |> Enum.reduce_while([], fn
        segment, segments when segment in ["", "."] ->
          {:cont, segments}

        "..", [] ->
          {:halt, :error}

        "..", [_parent | segments] ->
          {:cont, segments}

        segment, segments ->
          {:cont, [segment | segments]}
      end)
      |> case do
        :error -> :error
        [] -> :error
        segments -> {:ok, segments |> Enum.reverse() |> Path.join()}
      end
    else
      :error
    end
  end

  defp normalize_execute_file_path(_path), do: :error

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
