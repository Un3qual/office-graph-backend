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
    :stream,
    :transact,
    :transaction,
    :update,
    :update!,
    :update_all
  ]

  @direct_multi_operations [
    :append,
    :delete,
    :delete_all,
    :error,
    :insert,
    :insert_all,
    :insert_or_update,
    :merge,
    :prepend,
    :put,
    :run,
    :update,
    :update_all
  ]

  @database_alias_targets [
    "Ecto.Adapters.SQL",
    "Ecto.Multi",
    "OfficeGraph.Repo",
    "Postgrex"
  ]

  @migration_create_operations [:create, :create_if_not_exists]
  @migration_sql_option_constructs [:constraint, :index, :unique_index]

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
    child_context = %{context | function: function_signature(head)}

    {_child_environment, occurrences} =
      scan_children(body_options, environment, child_context, occurrences)

    {environment, occurrences}
  end

  defp scan_node({:fn, _metadata, clauses}, environment, context, occurrences) do
    {_child_environment, occurrences} =
      scan_children(clauses, environment, context, occurrences)

    {environment, occurrences}
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

  defp scan_node(node, environment, context, occurrences) do
    resolved_node = resolve_attributes(node, environment)
    occurrences = classify_migration_sql_options(resolved_node, context, occurrences)

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
              resolved_node
            )
            | occurrences
          ]
      end

    scan_children(node, environment, context, occurrences)
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
         _migration?,
         environment
       ) do
    receiver =
      receiver
      |> receiver_name()
      |> resolve_receiver(environment)

    classify_database_operation(receiver, operation)
  end

  defp classify_node({construct, _metadata, arguments}, _migration?, _environment)
       when construct in [:fragment, :unsafe_fragment] and is_list(arguments),
       do: {:raw_sql, to_string(construct)}

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

  defp classify_database_operation(nil, _operation), do: nil

  defp classify_database_operation(receiver, operation) do
    cond do
      operation in [:query, :query!] and repo_receiver?(receiver) ->
        {:raw_sql, "Repo.#{operation}"}

      operation in [:query, :query!] and receiver in ["Ecto.Adapters.SQL", "Postgrex"] ->
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

  defp empty_environment, do: %{aliases: %{}, attributes: %{}, imports: []}

  defp resolve_attributes(node, environment) do
    Macro.prewalk(node, fn
      {:@, _metadata, [{name, _name_metadata, nil}]} = reference when is_atom(name) ->
        Map.get(environment.attributes, name, reference)

      child ->
        child
    end)
  end

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

  defp function_signature({:when, _metadata, [head | _guards]}), do: function_signature(head)

  defp function_signature({name, _metadata, arguments}) when is_atom(name) do
    "#{name}/#{length(arguments || [])}"
  end

  defp function_signature(_head), do: nil

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
