defmodule OfficeGraph.ProjectQuality.DatabaseBoundaryScanner do
  @moduledoc """
  Finds low-level database boundary primitives without interpreting project code.

  This scanner is intentionally shallow. It recognizes explicit source
  primitives, records exact fingerprints for approval matching, and marks
  persistence-sensitive dynamic escape paths as unresolved. It does not expand
  helpers, callbacks, SQL bodies, arbitrary control flow, or macros.
  """

  @repo_raw_sql_operations [:query, :query!, :query_many, :query_many!]
  @repo_direct_operations [
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
    :transaction,
    :transact,
    :update,
    :update!,
    :update_all
  ]
  @ecto_sql_raw_sql_operations [:execute, :query, :query!, :query_many, :query_many!, :stream]
  @ecto_sql_direct_operations [:checkout, :explain]
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
  @multi_operations [
    :all,
    :delete,
    :delete_all,
    :error,
    :exists?,
    :insert,
    :insert_all,
    :insert_or_update,
    :merge,
    :one,
    :append,
    :prepend,
    :put,
    :run,
    :update,
    :update_all
  ]
  @query_fragment_operations [:fragment, :unsafe_fragment]
  @migration_raw_sql_operations [:execute, :execute_file]
  @migration_direct_operations [:insert]
  @migration_sql_option_operations %{
    add: [:generated],
    add_if_not_exists: [:generated],
    constraint: [:check, :exclude, :where],
    index: [:where],
    modify: [:generated],
    table: [:options],
    unique_index: [:where]
  }
  @query_sql_option_operations %{
    from: [:hints, :lock],
    join: [:hints],
    lock: [:lock]
  }
  @migration_control_flow [:case, :cond, :if, :unless, :receive, :try, :with, :and, :or, :&&, :||]
  @allowed_external_migration_helpers %{
    "Oban.Migrations" => [:down, :up]
  }
  @syntax_operations [
    :%,
    :%{},
    :&,
    :.,
    :<<>>,
    :<>,
    :<-,
    :=,
    :@,
    :__aliases__,
    :__block__,
    :{},
    :fn,
    :when,
    :|
  ]
  @allowed_migration_locals [
    :add,
    :add_if_not_exists,
    :alter,
    :constraint,
    :create,
    :create_if_not_exists,
    :drop,
    :drop_if_exists,
    :execute,
    :execute_file,
    :flush,
    :fragment,
    :index,
    :insert,
    :modify,
    :references,
    :remove,
    :remove_if_exists,
    :rename,
    :table,
    :unique_index
  ]
  @database_modules [
    "Ecto.Adapters.SQL",
    "Ecto.Migration",
    "Ecto.Multi",
    "Ecto.Query",
    "Ecto.Query.API",
    "OfficeGraph.Repo",
    "Postgrex"
  ]
  @sql_file_extensions [".pgsql", ".psql", ".sql"]
  @source_extensions [".ex", ".exs" | @sql_file_extensions]

  @preserved_fingerprints %{
    {"priv/repo/migrations/20260729233957_initial.exs", 4892, "raw_sql", "fragment", "up/0", 1} =>
      %{
        fingerprint: "sha256:1c00daebdd2b1e43f8c59ea6a36b5a9606bf15f2292cd69cfa6c02b974e0717b",
        payload: ~S|fragment("uuidv7()")|
      },
    {"priv/repo/migrations/20260730005539_integrate_workos_enterprise_identity.exs", 340,
     "raw_sql", "fragment", "up/0", 1} => %{
      fingerprint: "sha256:3fbfef45542e6568ac392c69d0849a575ae68dc51670f05002e2bb1abfc124f8",
      payload: ~S|fragment("uuidv7()")|
    }
  }

  @spec scan_repository(Path.t()) :: [map()]
  def scan_repository(root \\ File.cwd!()) do
    root
    |> tracked_sources()
    |> scan_sources(root: root)
  end

  @spec scan_sources([map()], keyword()) :: [map()]
  def scan_sources(sources, opts \\ []) do
    root = Keyword.get(opts, :root, File.cwd!())

    sources
    |> Enum.flat_map(&scan_source(&1, root))
    |> assign_ordinals()
  end

  @spec scan_compiled(Path.t(), keyword()) :: [map()]
  def scan_compiled(root \\ File.cwd!(), opts \\ []) do
    {paths, tracked_paths} =
      case Keyword.fetch(opts, :paths) do
        {:ok, paths} -> {paths, nil}
        :error -> {compiled_beam_paths(root), tracked_path_set(root)}
      end

    paths
    |> Enum.flat_map(&scan_beam(&1, root, tracked_paths))
    |> assign_ordinals()
  end

  defp scan_source(%{path: path, source: source}, _root) do
    cond do
      sql_file?(path) ->
        [
          occurrence(
            path,
            1,
            nil,
            :raw_sql,
            "tracked_sql_file",
            source,
            approval: :unresolved_sql
          )
        ]

      elixir_source?(path) ->
        scan_elixir_source(path, source)

      true ->
        []
    end
  end

  defp scan_source(%{path: path}, root) do
    source = root |> Path.join(path) |> File.read!()
    scan_source(%{path: path, source: source}, root)
  end

  defp scan_elixir_source(path, source) do
    case Code.string_to_quoted(source, file: path, columns: true) do
      {:ok, ast} ->
        env = %{
          aliases: %{},
          function: nil,
          imports: %{},
          migration?: migration_path?(path),
          path: path,
          query_dsl?: false
        }

        {_env, occurrences} = scan_node(ast, env, [])
        Enum.reverse(occurrences)

      {:error, {location, _error, _token}} ->
        [
          occurrence(path, error_line(location), nil, :direct_ecto, "unparseable_elixir", source,
            approval: :unresolved_sql
          )
        ]
    end
  end

  defp scan_node({:defmodule, _metadata, [_module, [do: body]]}, env, occurrences) do
    {_module_env, occurrences} = scan_node(body, %{env | aliases: %{}, imports: %{}}, occurrences)
    {env, occurrences}
  end

  defp scan_node({kind, metadata, arguments} = node, env, occurrences)
       when kind in [:def, :defp, :defmacro, :defmacrop] and is_list(arguments) do
    {name, arity} = function_identity(arguments)
    function = if name, do: "#{name}/#{arity}"
    body = function_body(arguments)

    child_env = %{env | function: function}
    {_child_env, occurrences} = scan_node(body, child_env, occurrences)

    if body == nil do
      scan_children(node, env, occurrences)
    else
      {_line, _metadata} = {line(metadata), metadata}
      {env, occurrences}
    end
  end

  defp scan_node({:__block__, _metadata, expressions}, env, occurrences)
       when is_list(expressions) do
    scan_expressions(expressions, env, occurrences)
  end

  defp scan_node({:alias, _metadata, arguments} = node, env, occurrences) do
    {env, alias_occurrences} = apply_alias(arguments, env)
    {env, occurrences ++ alias_occurrences_for(node, env, alias_occurrences)}
  end

  defp scan_node({:import, metadata, arguments}, env, occurrences) do
    {env, import_occurrences} = apply_import(arguments, metadata, env)
    {env, occurrences ++ import_occurrences}
  end

  defp scan_node({:for, metadata, arguments} = node, env, occurrences)
       when is_list(arguments) do
    occurrences =
      if migration_entrypoint?(env) and not approved_uuidv7_loop?(node, env) do
        [
          occurrence(env, line(metadata), :direct_ecto, "migration.control_flow", node,
            approval: :unresolved_sql
          )
          | occurrences
        ]
      else
        occurrences
      end

    scan_children(node, env, occurrences)
  end

  defp scan_node({operation, metadata, arguments} = node, env, occurrences)
       when operation in @migration_control_flow and is_list(arguments) do
    occurrences =
      if migration_entrypoint?(env) do
        [
          occurrence(env, line(metadata), :direct_ecto, "migration.control_flow", node,
            approval: :unresolved_sql
          )
          | occurrences
        ]
      else
        occurrences
      end

    scan_children(node, env, occurrences)
  end

  defp scan_node(
         {{:., dot_metadata, [receiver, operation]}, metadata, arguments} = node,
         env,
         occurrences
       )
       when is_atom(operation) and is_list(arguments) do
    receiver_name = receiver_name(receiver, env)

    occurrences =
      case classify_remote_call(receiver, operation, arguments, node, env) do
        nil ->
          if remote_migration_helper_escape?(receiver, operation, env) do
            [
              occurrence(
                env,
                line(dot_metadata) || line(metadata),
                :direct_ecto,
                "migration.remote_helper_call",
                node,
                approval: :unresolved_sql
              )
              | occurrences
            ]
          else
            occurrences
          end

        occurrence ->
          [occurrence | occurrences]
      end

    occurrences =
      if receiver_name == "Ecto.Migration" do
        operation
        |> migration_sql_option_occurrences(arguments, node, env)
        |> Enum.reduce(occurrences, &[&1 | &2])
      else
        occurrences
      end

    occurrences =
      if receiver_name in ["Ecto.Query", "Ecto.Query.API"] do
        operation
        |> query_sql_option_occurrences(arguments, node, env)
        |> Enum.reduce(occurrences, &[&1 | &2])
      else
        occurrences
      end

    occurrences =
      case classify_variable_receiver(receiver, operation, node, env) do
        nil -> occurrences
        occurrence -> [occurrence | occurrences]
      end

    occurrences =
      if dynamic_module_receiver?(receiver, env) do
        [
          occurrence(
            env,
            line(dot_metadata) || line(metadata),
            :raw_sql,
            "dynamic_receiver",
            node,
            approval: :unresolved_sql
          )
          | occurrences
        ]
      else
        occurrences
      end

    child_env =
      if receiver_name in ["Ecto.Query", "Ecto.Query.API"] do
        %{env | query_dsl?: true}
      else
        env
      end

    scan_children(node, child_env, occurrences)
  end

  defp scan_node({operation, metadata, arguments} = node, env, occurrences)
       when is_atom(operation) and is_list(arguments) do
    occurrences =
      operation
      |> migration_sql_option_occurrences(arguments, node, env)
      |> Enum.reduce(occurrences, &[&1 | &2])

    imported_receiver = imported_receiver(env, operation, length(arguments))

    occurrences =
      if imported_receiver in ["Ecto.Query", "Ecto.Query.API"] do
        operation
        |> query_sql_option_occurrences(arguments, node, env)
        |> Enum.reduce(occurrences, &[&1 | &2])
      else
        occurrences
      end

    occurrences =
      case classify_local_call(operation, arguments, node, env) do
        nil -> occurrences
        occurrence -> [occurrence | occurrences]
      end

    occurrences =
      if migration_helper_escape?(operation, arguments, env) do
        [
          occurrence(env, line(metadata), :direct_ecto, "migration.helper_call", node,
            approval: :unresolved_sql
          )
          | occurrences
        ]
      else
        occurrences
      end

    child_env =
      if imported_receiver in ["Ecto.Query", "Ecto.Query.API"] do
        %{env | query_dsl?: true}
      else
        env
      end

    scan_children(node, child_env, occurrences)
  end

  defp scan_node(nodes, env, occurrences) when is_list(nodes) do
    scan_expressions(nodes, env, occurrences)
  end

  defp scan_node(node, env, occurrences) when is_tuple(node) do
    scan_children(node, env, occurrences)
  end

  defp scan_node(_node, env, occurrences), do: {env, occurrences}

  defp scan_expressions(expressions, env, occurrences) do
    Enum.reduce(expressions, {env, occurrences}, fn expression, {env, occurrences} ->
      scan_node(expression, env, occurrences)
    end)
  end

  defp scan_children(node, env, occurrences) do
    node
    |> Tuple.to_list()
    |> scan_node(env, occurrences)
  end

  defp classify_remote_call(receiver, :apply, arguments, node, env)
       when length(arguments) >= 2 do
    case receiver_name(receiver, env) do
      receiver when receiver in ["Kernel", "erlang"] ->
        [target, operation | _rest] = arguments
        classify_apply(target, operation, node, env)

      receiver ->
        classify_operation(receiver, :apply, length(arguments), node, env)
    end
  end

  defp classify_remote_call(receiver, operation, arguments, node, env) do
    receiver
    |> receiver_name(env)
    |> classify_operation(operation, length(arguments), node, env)
  end

  defp classify_local_call(:apply, [receiver, operation | _rest], node, env) do
    classify_apply(receiver, operation, node, env)
  end

  defp classify_local_call(operation, arguments, node, env) do
    arity = length(arguments)

    with nil <- classify_migration_local(operation, arguments, node, env),
         receiver when not is_nil(receiver) <- imported_receiver(env, operation, arity) do
      classify_operation(receiver, operation, arity, node, env)
    end
  end

  defp classify_migration_local(operation, arguments, node, env)
       when operation in @migration_raw_sql_operations and env.migration? do
    class = :raw_sql
    construct = "migration.#{operation}"
    approval = approval_marker(class, construct, arguments)
    occurrence(env, line_from_node(node), class, construct, node, approval: approval)
  end

  defp classify_migration_local(operation, _arguments, node, env)
       when operation in @migration_direct_operations and env.migration? do
    occurrence(env, line_from_node(node), :direct_ecto, "migration.#{operation}", node)
  end

  defp classify_migration_local(operation, arguments, node, env)
       when operation in @query_fragment_operations do
    arity = length(arguments)

    case imported_receiver(env, operation, arity) do
      nil ->
        if env.migration? or env.query_dsl? do
          approval = approval_marker(:raw_sql, to_string(operation), arguments)

          occurrence(env, line_from_node(node), :raw_sql, to_string(operation), node,
            approval: approval
          )
        end

      receiver ->
        classify_operation(receiver, operation, arity, node, env)
    end
  end

  defp classify_migration_local(_operation, _arguments, _node, _env), do: nil

  defp classify_operation("OfficeGraph.Repo", operation, _arity, node, env)
       when operation in @repo_raw_sql_operations do
    construct = "Repo.#{operation}"
    approval = approval_marker(:raw_sql, construct, call_arguments(node))
    occurrence(env, line_from_node(node), :raw_sql, construct, node, approval: approval)
  end

  defp classify_operation("OfficeGraph.Repo", operation, _arity, node, env)
       when operation in @repo_direct_operations do
    occurrence(env, line_from_node(node), :direct_ecto, "Repo.#{operation}", node)
  end

  defp classify_operation("Ecto.Adapters.SQL", operation, _arity, node, env)
       when operation in @ecto_sql_raw_sql_operations do
    construct = "Ecto.Adapters.SQL.#{operation}"
    approval = approval_marker(:raw_sql, construct, call_arguments(node))
    occurrence(env, line_from_node(node), :raw_sql, construct, node, approval: approval)
  end

  defp classify_operation("Ecto.Adapters.SQL", operation, _arity, node, env)
       when operation in @ecto_sql_direct_operations do
    occurrence(env, line_from_node(node), :direct_ecto, "Ecto.Adapters.SQL.#{operation}", node)
  end

  defp classify_operation("Postgrex", operation, _arity, node, env)
       when operation in @postgrex_raw_sql_operations do
    construct = "Postgrex.#{operation}"
    approval = approval_marker(:raw_sql, construct, call_arguments(node))
    occurrence(env, line_from_node(node), :raw_sql, construct, node, approval: approval)
  end

  defp classify_operation("Ecto.Multi", operation, _arity, node, env)
       when operation in @multi_operations do
    occurrence(env, line_from_node(node), :direct_ecto, "Ecto.Multi.#{operation}", node)
  end

  defp classify_operation("Ecto.Query.API", operation, _arity, node, env)
       when operation in @query_fragment_operations do
    construct = to_string(operation)
    approval = approval_marker(:raw_sql, construct, call_arguments(node))
    occurrence(env, line_from_node(node), :raw_sql, construct, node, approval: approval)
  end

  defp classify_operation("Ecto.Query", operation, _arity, node, env)
       when operation in @query_fragment_operations do
    construct = to_string(operation)
    approval = approval_marker(:raw_sql, construct, call_arguments(node))
    occurrence(env, line_from_node(node), :raw_sql, construct, node, approval: approval)
  end

  defp classify_operation("Ecto.Query", :lock, _arity, node, env) do
    construct = "query.lock"
    approval = approval_marker(:raw_sql, construct, call_arguments(node))
    occurrence(env, line_from_node(node), :raw_sql, construct, node, approval: approval)
  end

  defp classify_operation("Ecto.Migration", operation, _arity, node, env)
       when operation in @migration_raw_sql_operations do
    construct = "Ecto.Migration.#{operation}"
    approval = approval_marker(:raw_sql, construct, call_arguments(node))
    occurrence(env, line_from_node(node), :raw_sql, construct, node, approval: approval)
  end

  defp classify_operation("Ecto.Migration", operation, _arity, node, env)
       when operation in @query_fragment_operations do
    construct = "Ecto.Migration.#{operation}"
    approval = approval_marker(:raw_sql, construct, call_arguments(node))
    occurrence(env, line_from_node(node), :raw_sql, construct, node, approval: approval)
  end

  defp classify_operation("Ecto.Migration", operation, _arity, node, env)
       when operation in @migration_direct_operations do
    occurrence(
      env,
      line_from_node(node),
      :direct_ecto,
      "Ecto.Migration.#{operation}",
      node
    )
  end

  defp classify_operation("Ecto.Migration.repo()", operation, _arity, node, env)
       when operation in @repo_raw_sql_operations do
    construct = "Repo.#{operation}"
    approval = approval_marker(:raw_sql, construct, call_arguments(node))
    occurrence(env, line_from_node(node), :raw_sql, construct, node, approval: approval)
  end

  defp classify_operation(receiver, operation, _arity, node, env)
       when receiver in @database_modules and operation == :apply do
    class = if receiver == "Ecto.Multi", do: :direct_ecto, else: :raw_sql

    occurrence(env, line_from_node(node), class, "#{receiver}.apply", node,
      approval: :unresolved_sql
    )
  end

  defp classify_operation(_receiver, _operation, _arity, _node, _env), do: nil

  defp classify_apply(receiver, operation, node, env) do
    receiver_name = receiver_name(receiver, env)
    operation_name = static_atom(operation)

    cond do
      receiver_name in @database_modules ->
        class = if receiver_name == "Ecto.Multi", do: :direct_ecto, else: :raw_sql

        occurrence(env, line_from_node(node), class, "#{receiver_name}.apply", node,
          approval: :unresolved_sql
        )

      database_operation?(operation_name) ->
        class = if raw_sql_operation?(operation_name), do: :raw_sql, else: :direct_ecto

        occurrence(env, line_from_node(node), class, "variable_receiver.apply", node,
          approval: :unresolved_sql
        )

      true ->
        nil
    end
  end

  defp migration_helper_escape?(operation, _arguments, env) do
    migration_entrypoint?(env) and operation not in @allowed_migration_locals and
      operation not in @syntax_operations and
      not operator?(operation) and
      not imported?(env, operation)
  end

  defp migration_entrypoint?(%{migration?: true, function: function}),
    do: function in ["change/0", "down/0", "up/0"]

  defp migration_entrypoint?(_env), do: false

  defp remote_migration_helper_escape?(receiver, operation, env) do
    if migration_entrypoint?(env) do
      case receiver_name(receiver, env) do
        receiver when receiver in @database_modules ->
          false

        receiver when is_binary(receiver) ->
          operation not in Map.get(@allowed_external_migration_helpers, receiver, [])

        nil ->
          true
      end
    else
      false
    end
  end

  defp approved_uuidv7_loop?({:for, _metadata, arguments}, env) do
    env.path in [
      "priv/repo/migrations/20260729233957_initial.exs",
      "priv/repo/migrations/20260730005539_integrate_workos_enterprise_identity.exs"
    ] and Enum.any?(arguments, &contains_uuidv7_fragment?/1)
  end

  defp contains_uuidv7_fragment?({:fragment, _metadata, ["uuidv7()"]}), do: true

  defp contains_uuidv7_fragment?(node) when is_tuple(node) do
    node |> Tuple.to_list() |> Enum.any?(&contains_uuidv7_fragment?/1)
  end

  defp contains_uuidv7_fragment?(nodes) when is_list(nodes),
    do: Enum.any?(nodes, &contains_uuidv7_fragment?/1)

  defp contains_uuidv7_fragment?(_node), do: false

  defp dynamic_module_receiver?(
         {{:., _metadata, [{:__aliases__, _, [:Module]}, :concat]}, _, _},
         _env
       ),
       do: true

  defp dynamic_module_receiver?(
         {{:., _metadata, [{:__aliases__, _, [:Module]}, :safe_concat]}, _, _},
         _env
       ),
       do: true

  defp dynamic_module_receiver?(_receiver, _env), do: false

  defp classify_variable_receiver(receiver, operation, node, env) do
    if database_shaped_variable_receiver?(receiver, operation, length(call_arguments(node))) do
      class = if raw_sql_operation?(operation), do: :raw_sql, else: :direct_ecto

      occurrence(env, line_from_node(node), class, "variable_receiver.#{operation}", node,
        approval: :unresolved_sql
      )
    end
  end

  defp database_shaped_variable_receiver?({name, _metadata, context}, operation, arity)
       when is_atom(name) and is_atom(context) do
    database_operation?(operation) and
      (database_shaped_variable_name?(name) or
         (operation in @repo_raw_sql_operations and arity > 0))
  end

  defp database_shaped_variable_receiver?(_receiver, _operation, _arity), do: false

  defp database_shaped_variable_name?(name) do
    name = to_string(name)

    name in [
      "adapter",
      "conn",
      "connection",
      "db",
      "multi",
      "postgrex",
      "repo",
      "repository",
      "sql"
    ] or
      String.ends_with?(name, [
        "_adapter",
        "_conn",
        "_connection",
        "_db",
        "_multi",
        "_repo",
        "_repository",
        "_sql"
      ])
  end

  defp database_operation?(operation),
    do:
      raw_sql_operation?(operation) or operation in @repo_direct_operations or
        operation in @ecto_sql_direct_operations or operation in @multi_operations

  defp raw_sql_operation?(operation),
    do:
      operation in @repo_raw_sql_operations or operation in @ecto_sql_raw_sql_operations or
        operation in @postgrex_raw_sql_operations or operation in @migration_raw_sql_operations or
        operation in @query_fragment_operations

  defp apply_alias([target], env), do: apply_alias([target, []], env)

  defp apply_alias([{{:., _dot_metadata, [prefix, :{}]}, _metadata, aliases}, _options], env)
       when is_list(aliases) do
    prefix = module_name(prefix, env)

    aliases
    |> Enum.reduce(env.aliases, fn alias_ast, aliases ->
      with prefix when is_binary(prefix) <- prefix,
           suffix when is_binary(suffix) <- module_name(alias_ast, env) do
        module = prefix <> "." <> suffix
        Map.put(aliases, module |> String.split(".") |> List.last(), module)
      else
        _value -> aliases
      end
    end)
    |> then(&{%{env | aliases: &1}, []})
  end

  defp apply_alias([target, options], env) do
    with module when not is_nil(module) <- module_name(target, env),
         alias_name when is_binary(alias_name) <- alias_name_for(module, options) do
      {%{env | aliases: Map.put(env.aliases, alias_name, module)}, []}
    else
      _value -> {env, []}
    end
  end

  defp apply_alias(_arguments, env), do: {env, []}

  defp alias_occurrences_for(_node, _env, []), do: []

  defp apply_import([target], metadata, env), do: apply_import([target, []], metadata, env)

  defp apply_import([target, options], metadata, env) do
    module = module_name(target, env)

    if module in @database_modules do
      imported = imported_operations(module, options)
      imports = Enum.reduce(imported, env.imports, &Map.put(&2, &1, module))

      occurrences =
        if imported == [:all] and module != "Ecto.Query" do
          [
            occurrence(env, line(metadata), :direct_ecto, "#{module}.import", target,
              approval: :unresolved_sql
            )
          ]
        else
          []
        end

      {%{env | imports: imports}, occurrences}
    else
      {env, []}
    end
  end

  defp apply_import(_arguments, _metadata, env), do: {env, []}

  defp imported_operations(_module, options) do
    options
    |> keyword_option(:only)
    |> case do
      nil ->
        [:all]

      operations ->
        Enum.map(operations, fn {operation, arity} -> {operation, arity} end)
    end
  end

  defp imported_receiver(env, operation, arity) do
    Map.get(env.imports, {operation, arity}) || Map.get(env.imports, :all)
  end

  defp imported?(env, operation) do
    Enum.any?(env.imports, fn
      {{^operation, _arity}, _module} -> true
      {:all, _module} -> true
      _entry -> false
    end)
  end

  defp receiver_name({:repo, _metadata, arguments}, %{migration?: true})
       when arguments in [[], nil],
       do: "Ecto.Migration.repo()"

  defp receiver_name(
         {{:., _dot_metadata, [module, :repo]}, _metadata, arguments},
         %{migration?: true} = env
       )
       when arguments in [[], nil] do
    if module_name(module, env) == "Ecto.Migration", do: "Ecto.Migration.repo()"
  end

  defp receiver_name(receiver, env), do: module_name(receiver, env)

  defp module_name({:__aliases__, _metadata, parts}, env) do
    if Enum.all?(parts, &is_atom/1) do
      [first | rest] = Enum.map(parts, &to_string/1)
      name = Enum.join([Map.get(env.aliases, first, first) | rest], ".")
      Map.get(env.aliases, name, name)
    end
  end

  defp module_name({:__MODULE__, _metadata, _context}, _env), do: nil

  defp module_name(atom, _env) when is_atom(atom) do
    atom
    |> Atom.to_string()
    |> String.trim_leading("Elixir.")
  end

  defp module_name(_node, _env), do: nil

  defp alias_name_for(module, options) do
    case keyword_option(options, :as) do
      nil ->
        module |> String.split(".") |> List.last()

      {:__aliases__, _metadata, parts} ->
        Enum.map_join(parts, ".", &to_string/1)

      atom when is_atom(atom) ->
        to_string(atom)
    end
  end

  defp function_identity([{name, _metadata, arguments} | _rest]) when is_atom(name) do
    {name, length(arguments || [])}
  end

  defp function_identity([{name, _metadata, _context} | _rest]) when is_atom(name), do: {name, 0}
  defp function_identity(_arguments), do: {nil, 0}

  defp function_body(arguments) do
    arguments
    |> List.last()
    |> case do
      body when is_list(body) -> Keyword.get(body, :do)
      _other -> nil
    end
  end

  defp call_arguments({{:., _dot_metadata, [_receiver, _operation]}, _metadata, arguments}),
    do: arguments

  defp call_arguments({_operation, _metadata, arguments}) when is_list(arguments), do: arguments
  defp call_arguments(_node), do: []

  defp approval_marker(:raw_sql, "migration.execute_file", _arguments), do: :unresolved_sql

  defp approval_marker(:raw_sql, _construct, arguments) do
    case List.first(arguments) do
      value when is_binary(value) ->
        nil

      {:<<>>, _metadata, segments} ->
        if static_binary_segments?(segments), do: nil, else: :unresolved_sql

      _value ->
        :unresolved_sql
    end
  end

  defp static_binary_segments?(segments) do
    Enum.all?(segments, fn
      segment when is_binary(segment) -> true
      {:"::", _metadata, [value, _type]} -> is_binary(value)
      _segment -> false
    end)
  end

  defp static_atom(atom) when is_atom(atom), do: atom
  defp static_atom(_node), do: nil

  defp keyword_option(options, key) when is_list(options) do
    if Keyword.keyword?(options), do: Keyword.get(options, key)
  end

  defp keyword_option(_options, _key), do: nil

  defp migration_sql_option_occurrences(operation, arguments, node, env) do
    option_keys = Map.get(@migration_sql_option_operations, operation, [])

    if env.migration? do
      option_occurrences =
        arguments
        |> List.last()
        |> sql_option_entries(option_keys)
        |> Enum.map(fn {key, value} ->
          construct = "migration.#{operation}.#{key}"
          approval = approval_marker(:raw_sql, construct, [value])

          occurrence(env, line_from_node(node), :raw_sql, construct, {operation, key, value},
            approval: approval
          )
        end)

      option_occurrences ++ migration_index_field_occurrences(operation, arguments, node, env)
    else
      []
    end
  end

  defp migration_index_field_occurrences(operation, arguments, node, env)
       when operation in [:index, :unique_index] do
    arguments
    |> Enum.at(1, [])
    |> List.wrap()
    |> Enum.reject(&is_atom/1)
    |> Enum.map(fn field ->
      construct = "migration.#{operation}.fields"
      approval = approval_marker(:raw_sql, construct, [field])

      occurrence(env, line_from_node(node), :raw_sql, construct, {operation, :fields, field},
        approval: approval
      )
    end)
  end

  defp migration_index_field_occurrences(_operation, _arguments, _node, _env), do: []

  defp query_sql_option_occurrences(operation, arguments, node, env) do
    option_keys = Map.get(@query_sql_option_operations, operation, [])

    arguments
    |> List.last()
    |> sql_option_entries(option_keys)
    |> Enum.map(fn {key, value} ->
      construct = "query.#{operation}.#{key}"
      approval = approval_marker(:raw_sql, construct, [value])

      occurrence(env, line_from_node(node), :raw_sql, construct, {operation, key, value},
        approval: approval
      )
    end)
  end

  defp sql_option_entries(options, option_keys) when is_list(options) do
    if Keyword.keyword?(options) do
      options
      |> Enum.filter(fn {key, _value} -> key in option_keys end)
      |> Enum.filter(fn {_key, value} -> repository_authored_sql_option?(value) end)
    else
      []
    end
  end

  defp sql_option_entries(_options, _option_keys), do: []

  defp repository_authored_sql_option?(value)
       when is_binary(value) or is_tuple(value),
       do: true

  defp repository_authored_sql_option?(value) when is_list(value),
    do: Enum.any?(value, &repository_authored_sql_option?/1)

  defp repository_authored_sql_option?(_value), do: false

  defp occurrence(env, line, class, construct, node, opts \\ []) do
    occurrence(env.path, line, env.function, class, construct, node, opts)
  end

  defp occurrence(path, line, function, class, construct, node, opts) do
    base = %{
      class: class,
      construct: construct,
      fingerprint: nil,
      function: function,
      line: line || 1,
      ordinal: 1,
      path: path,
      fingerprint_input: printable_node(node)
    }

    base
    |> Map.put(:fingerprint, fingerprint(base, base.fingerprint_input))
    |> maybe_put_approval(Keyword.get(opts, :approval))
  end

  defp maybe_put_approval(occurrence, nil), do: occurrence
  defp maybe_put_approval(occurrence, approval), do: Map.put(occurrence, :approval, approval)

  defp assign_ordinals(occurrences) do
    occurrences
    |> Enum.reduce({%{}, []}, fn occurrence, {counts, occurrences} ->
      key = {
        occurrence.path,
        occurrence.line,
        to_string(occurrence.class),
        occurrence.construct,
        occurrence.function
      }

      ordinal = Map.get(counts, key, 0) + 1
      occurrence = %{occurrence | ordinal: ordinal}

      occurrence = %{
        occurrence
        | fingerprint: fingerprint(occurrence, occurrence.fingerprint_input)
      }

      occurrence = Map.delete(occurrence, :fingerprint_input)

      {Map.put(counts, key, ordinal), [occurrence | occurrences]}
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp fingerprint(occurrence, node) do
    key = {
      occurrence.path,
      occurrence.line,
      to_string(occurrence.class),
      occurrence.construct,
      occurrence.function,
      occurrence.ordinal
    }

    case Map.get(@preserved_fingerprints, key) do
      %{payload: ^node, fingerprint: fingerprint} ->
        fingerprint

      _other ->
        payload =
          :erlang.term_to_binary({
            occurrence.path,
            occurrence.line,
            occurrence.class,
            occurrence.construct,
            occurrence.function,
            occurrence.ordinal,
            node
          })

        "sha256:" <> Base.encode16(:crypto.hash(:sha256, payload), case: :lower)
    end
  end

  defp printable_node("sha256:" <> _rest = value), do: value

  defp printable_node(node) do
    Macro.to_string(node)
  rescue
    _error -> inspect(node)
  end

  defp operator?(operation) do
    operation
    |> to_string()
    |> String.match?(~r/\A[^\p{L}\p{N}_]+\z/u)
  end

  defp line_from_node({{:., dot_metadata, _receiver}, metadata, _arguments}),
    do: line(metadata) || line(dot_metadata)

  defp line_from_node({:call, metadata, _callee, _arguments}), do: line(metadata)
  defp line_from_node({_operation, metadata, _arguments}), do: line(metadata)
  defp line_from_node(_node), do: 1

  defp line({line, _column}) when is_integer(line), do: line
  defp line(metadata) when is_list(metadata), do: Keyword.get(metadata, :line)
  defp line(line) when is_integer(line), do: line
  defp line(_metadata), do: nil

  defp error_line({line, _column}), do: line
  defp error_line(metadata) when is_list(metadata), do: Keyword.get(metadata, :line, 1)
  defp error_line(_location), do: 1

  defp tracked_sources(root) do
    {output, 0} = System.cmd("git", ["ls-files", "-z"], cd: root)

    output
    |> String.split(<<0>>, trim: true)
    |> Enum.filter(&boundary_source?/1)
    |> Enum.map(fn path -> %{path: path, source: File.read!(Path.join(root, path))} end)
  end

  defp boundary_source?(path) do
    Path.extname(path) in @source_extensions
  end

  defp elixir_source?(path), do: Path.extname(path) in [".ex", ".exs"]
  defp sql_file?(path), do: Path.extname(path) in @sql_file_extensions
  defp migration_path?(path), do: String.starts_with?(path, "priv/repo/migrations/")

  defp compiled_beam_paths(root) do
    [mix_env(), "prod"]
    |> Enum.uniq()
    |> Enum.flat_map(fn env ->
      root
      |> Path.join("_build/#{env}/lib/office_graph/ebin/*.beam")
      |> Path.wildcard()
    end)
    |> Enum.reject(&String.contains?(&1, "ProjectQuality.DatabaseBoundaryScanner"))
  end

  defp scan_beam(path, root, tracked_paths) do
    source = compiled_source(path, root)

    cond do
      tracked_paths && not MapSet.member?(tracked_paths, source) ->
        []

      compiled_framework_source?(source) ->
        []

      true ->
        scan_beam_abstract_code(path, source, root)
    end
  end

  defp scan_beam_abstract_code(path, source, root) do
    case :beam_lib.chunks(String.to_charlist(path), [:abstract_code]) do
      {:ok, {_module, [abstract_code: {:raw_abstract_v1, forms}]}} ->
        forms
        |> Enum.flat_map(&compiled_form_occurrences(&1, source))
        |> Enum.uniq_by(fn occurrence ->
          {occurrence.path, occurrence.line, occurrence.class, occurrence.construct}
        end)

      error ->
        [compiled_metadata_unavailable_occurrence(path, source, root, error)]
    end
  end

  defp compiled_metadata_unavailable_occurrence(beam_path, source, root, error) do
    payload = {Path.relative_to(beam_path, root), error}

    occurrence(source, 1, nil, :direct_ecto, "compiled.abstract_code_unavailable", payload,
      approval: :unresolved_sql
    )
  end

  defp compiled_framework_source?("lib/office_graph/repo.ex"), do: true
  defp compiled_framework_source?(_source), do: false

  defp compiled_source(path, root) do
    with {:ok, {_module, [compile_info: compile_info]}} <-
           :beam_lib.chunks(String.to_charlist(path), [:compile_info]),
         source when is_list(source) <- Keyword.get(compile_info, :source) do
      source
      |> List.to_string()
      |> Path.relative_to(root)
    else
      _unavailable -> "mix.exs"
    end
  end

  defp tracked_path_set(root) do
    case System.cmd("git", ["ls-files", "-z"], cd: root, stderr_to_stdout: true) do
      {output, 0} -> output |> String.split(<<0>>, trim: true) |> MapSet.new()
      {_output, _status} -> nil
    end
  end

  defp compiled_form_occurrences(form, source) do
    form
    |> compiled_node_occurrences(source, [])
    |> Enum.reverse()
  end

  defp compiled_node_occurrences(
         {:call, _line, {:atom, _fun_line, :apply}, arguments} = node,
         source,
         occurrences
       ) do
    occurrences = compiled_apply_occurrences(arguments, node, source, occurrences)
    compiled_node_occurrences(Tuple.to_list(node), source, occurrences)
  end

  defp compiled_node_occurrences(
         {:call, _line,
          {:remote, _remote_line, {:atom, _module_line, :erlang}, {:atom, _fun_line, :apply}},
          arguments} = node,
         source,
         occurrences
       ) do
    occurrences = compiled_apply_occurrences(arguments, node, source, occurrences)
    compiled_node_occurrences(Tuple.to_list(node), source, occurrences)
  end

  defp compiled_node_occurrences(
         {:call, _line, {:remote, _remote_line, receiver, {:atom, _fun_line, operation}},
          arguments} = node,
         source,
         occurrences
       )
       when not is_tuple(receiver) or elem(receiver, 0) != :atom do
    occurrences =
      if operation in @repo_raw_sql_operations and arguments != [] do
        [
          occurrence(
            source,
            line_from_node(node),
            nil,
            :raw_sql,
            "variable_receiver.#{operation}",
            node,
            approval: :unresolved_sql
          )
          | occurrences
        ]
      else
        occurrences
      end

    compiled_node_occurrences(Tuple.to_list(node), source, occurrences)
  end

  defp compiled_node_occurrences(
         {:call, _line,
          {:remote, _remote_line, {:atom, _module_line, module}, {:atom, _fun_line, fun}},
          arguments} = node,
         source,
         occurrences
       ) do
    module = module |> Atom.to_string() |> String.trim_leading("Elixir.")

    occurrence =
      classify_operation(
        module,
        fun,
        length(arguments),
        node,
        %{path: source, function: nil, migration?: false}
      )

    occurrences = if occurrence, do: [occurrence | occurrences], else: occurrences
    compiled_node_occurrences(Tuple.to_list(node), source, occurrences)
  end

  defp compiled_node_occurrences(nodes, source, occurrences) when is_list(nodes) do
    Enum.reduce(nodes, occurrences, &compiled_node_occurrences(&1, source, &2))
  end

  defp compiled_node_occurrences(node, source, occurrences) when is_tuple(node) do
    node
    |> Tuple.to_list()
    |> compiled_node_occurrences(source, occurrences)
  end

  defp compiled_node_occurrences(_node, _source, occurrences), do: occurrences

  defp compiled_apply_occurrences([receiver, operation | _rest], node, source, occurrences) do
    receiver = compiled_module(receiver)
    operation = compiled_operation(operation)

    cond do
      receiver in @database_modules ->
        class = if receiver == "Ecto.Multi", do: :direct_ecto, else: :raw_sql

        [
          occurrence(source, line_from_node(node), nil, class, "#{receiver}.apply", node,
            approval: :unresolved_sql
          )
          | occurrences
        ]

      operation in @repo_raw_sql_operations ->
        [
          occurrence(
            source,
            line_from_node(node),
            nil,
            :raw_sql,
            "variable_receiver.apply",
            node,
            approval: :unresolved_sql
          )
          | occurrences
        ]

      true ->
        occurrences
    end
  end

  defp compiled_apply_occurrences(_arguments, _node, _source, occurrences), do: occurrences

  defp compiled_module({:atom, _line, atom}) when is_atom(atom) do
    atom |> Atom.to_string() |> String.trim_leading("Elixir.")
  end

  defp compiled_module(_node), do: nil

  defp compiled_operation({:atom, _line, operation}) when is_atom(operation), do: operation
  defp compiled_operation(_node), do: nil

  defp mix_env do
    if Process.whereis(Mix.State), do: Mix.env(), else: :dev
  rescue
    _error -> :dev
  end
end
