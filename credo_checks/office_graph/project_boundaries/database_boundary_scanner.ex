defmodule OfficeGraph.ProjectQuality.DatabaseBoundaryScanner do
  @moduledoc """
  Finds explicit low-level database primitives without interpreting project code.

  Project source and pinned dependencies are trusted to participate in static
  governance. This scanner records direct source evidence; it does not treat
  generic runtime execution as database access or expand dataflow, callbacks,
  helper bodies, SQL bodies, or macro output.
  """

  @repo_raw_sql_operations [:query, :query!, :query_many, :query_many!]
  @repo_direct_operations [
    :aggregate,
    :all,
    :all_by,
    :checked_out?,
    :checkout,
    :delete,
    :delete!,
    :delete_all,
    :exists?,
    :get,
    :get!,
    :get_by,
    :get_by!,
    :get_dynamic_repo,
    :in_transaction?,
    :insert,
    :insert!,
    :insert_all,
    :one,
    :one!,
    :preload,
    :preload!,
    :put_dynamic_repo,
    :reload,
    :reload!,
    :rollback,
    :start_link,
    :stop,
    :stream,
    :transaction,
    :transact,
    :update,
    :update!,
    :update_all
  ]
  @ecto_sql_raw_sql_operations [:execute, :query, :query!, :query_many, :query_many!, :stream]
  @ecto_sql_direct_operations [:checkout, :disconnect_all, :explain]
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
  @postgrex_direct_operations [:close, :close!, :rollback, :start_link, :transaction]
  @db_connection_raw_sql_operations [
    :execute,
    :execute!,
    :prepare,
    :prepare!,
    :prepare_execute,
    :prepare_execute!,
    :prepare_stream,
    :stream
  ]
  @db_connection_direct_operations [
    :close,
    :close!,
    :disconnect_all,
    :rollback,
    :run,
    :start_link,
    :transaction
  ]
  @ecto_migrator_operations [:down, :run, :up, :with_repo]
  @multi_operations [
    :all,
    :delete,
    :delete_all,
    :exists?,
    :insert,
    :insert_all,
    :merge,
    :one,
    :run,
    :update,
    :update_all
  ]
  @query_fragment_operations [:fragment, :unsafe_fragment]
  @migration_raw_sql_operations [:execute, :execute_file]
  @migration_direct_operations [:insert]
  @migration_control_flow [:case, :cond, :if, :receive, :try, :with]
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
    :modify,
    :references,
    :remove,
    :remove_if_exists,
    :rename,
    :table,
    :unique_index
  ]
  @database_modules [
    "DBConnection",
    "Ecto.Adapters.SQL",
    "Ecto.Migration",
    "Ecto.Migrator",
    "Ecto.Multi",
    "Ecto.Query",
    "Ecto.Query.API",
    "OfficeGraph.Repo",
    "Postgrex",
    "Postgrex.Notifications",
    "Postgrex.SimpleConnection"
  ]
  @sql_file_pattern ~r/\.(?:pgsql|psql|sql)(?:\.(?:eex|heex|leex))?\z/i

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
  @approved_uuidv7_migration_hashes %{
    "priv/repo/migrations/20260729233957_initial.exs" =>
      "9bc5e6aee67201982320a35c4a985fdc12dbfa03695117035fb244020a203233",
    "priv/repo/migrations/20260730005539_integrate_workos_enterprise_identity.exs" =>
      "cec2b703b975559c23619f5529b158f10de899216562cb3e716c4af0b3586b76"
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
  def scan_compiled(root \\ File.cwd!(), opts \\ []),
    do: OfficeGraph.ProjectQuality.DatabaseDependencyAudit.scan(root, opts)

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
            []
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
          ash_postgres?:
            String.contains?(source, "use Ash.Resource") and
              String.contains?(source, "AshPostgres.DataLayer"),
          function: nil,
          imports: %{},
          migration?: migration_path?(path),
          path: path,
          preserve_uuidv7?: approved_uuidv7_context?(path, source)
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

  defp scan_node({:quote, _metadata, arguments}, env, occurrences) do
    evaluated_arguments =
      Enum.flat_map(arguments, fn
        options when is_list(options) ->
          if Keyword.keyword?(options) do
            options |> Keyword.delete(:do) |> Keyword.values()
          else
            []
          end

        _argument ->
          []
      end)

    scan_node(evaluated_arguments, env, occurrences)
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
         {{:., _dot_metadata, [receiver, operation]}, _metadata, arguments} = node,
         env,
         occurrences
       )
       when is_atom(operation) and is_list(arguments) do
    occurrences =
      case classify_remote_call(receiver, operation, arguments, node, env) do
        nil -> occurrences
        occurrence -> [occurrence | occurrences]
      end

    scan_children(node, env, occurrences)
  end

  defp scan_node({operation, metadata, arguments} = node, env, occurrences)
       when is_atom(operation) and is_list(arguments) do
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

    scan_children(node, env, occurrences)
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

  defp classify_remote_call(receiver, operation, arguments, node, env) do
    receiver = receiver_name(receiver, env)

    classify_operation(receiver, operation, length(arguments), node, env) ||
      classify_sql_bearing_call(receiver, operation, arguments, node, env) ||
      classify_migration_remote_helper(receiver, operation, node, env)
  end

  defp classify_local_call(:apply, [receiver, operation | _rest], node, env) do
    classify_apply(receiver, operation, node, env)
  end

  defp classify_local_call(operation, arguments, node, env) do
    arity = length(arguments)
    imported_receiver = imported_receiver(env, operation, arity)

    with nil <- classify_migration_local(operation, arguments, node, env),
         nil <- classify_sql_bearing_call(imported_receiver, operation, arguments, node, env),
         receiver when not is_nil(receiver) <- imported_receiver do
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
        if env.migration? do
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

  defp classify_operation(receiver, operation, _arity, node, env)
       when receiver in ["Postgrex", "Postgrex.Notifications", "Postgrex.SimpleConnection"] and
              operation in @postgrex_direct_operations do
    occurrence(env, line_from_node(node), :direct_ecto, "#{receiver}.#{operation}", node)
  end

  defp classify_operation(receiver, operation, _arity, node, env)
       when receiver in ["Postgrex.Notifications", "Postgrex.SimpleConnection"] and
              operation in @postgrex_raw_sql_operations do
    construct = "#{receiver}.#{operation}"
    approval = approval_marker(:raw_sql, construct, call_arguments(node))
    occurrence(env, line_from_node(node), :raw_sql, construct, node, approval: approval)
  end

  defp classify_operation("DBConnection", operation, _arity, node, env)
       when operation in @db_connection_raw_sql_operations do
    construct = "DBConnection.#{operation}"
    occurrence(env, line_from_node(node), :raw_sql, construct, node, approval: :unresolved_sql)
  end

  defp classify_operation("DBConnection", operation, _arity, node, env)
       when operation in @db_connection_direct_operations do
    occurrence(env, line_from_node(node), :direct_ecto, "DBConnection.#{operation}", node)
  end

  defp classify_operation("Ecto.Migrator", operation, _arity, node, env)
       when operation in @ecto_migrator_operations do
    occurrence(env, line_from_node(node), :direct_ecto, "Ecto.Migrator.#{operation}", node)
  end

  defp classify_operation("Ecto.Multi", operation, _arity, node, env)
       when operation in @multi_operations do
    occurrence(env, line_from_node(node), :direct_ecto, "Ecto.Multi.#{operation}", node)
  end

  defp classify_operation(receiver, operation, _arity, node, env)
       when receiver in ["Ecto.Query", "Ecto.Query.API"] and
              operation in @query_fragment_operations do
    construct = to_string(operation)
    approval = approval_marker(:raw_sql, construct, call_arguments(node))
    occurrence(env, line_from_node(node), :raw_sql, construct, node, approval: approval)
  end

  defp classify_operation("Ecto.Migration", operation, _arity, node, env)
       when operation in @migration_raw_sql_operations do
    construct = "migration.#{operation}"
    approval = approval_marker(:raw_sql, construct, call_arguments(node))
    occurrence(env, line_from_node(node), :raw_sql, construct, node, approval: approval)
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
      receiver_name == "Ecto.Query" ->
        nil

      receiver_name in @database_modules and is_atom(operation_name) and
          not is_nil(operation_name) ->
        classify_operation(receiver_name, operation_name, 0, node, env)

      receiver_name in @database_modules ->
        class = if receiver_name == "Ecto.Multi", do: :direct_ecto, else: :raw_sql

        occurrence(env, line_from_node(node), class, "#{receiver_name}.apply", node,
          approval: :unresolved_sql
        )

      true ->
        nil
    end
  end

  defp classify_sql_bearing_call(receiver, :lock, [_query, value], node, env)
       when receiver == "Ecto.Query" and is_binary(value) do
    occurrence(env, line_from_node(node), :raw_sql, "query.lock", node)
  end

  defp classify_sql_bearing_call(receiver, operation, arguments, node, env)
       when receiver == "Ecto.Query" and operation in [:from, :join] do
    classify_sql_options("query.#{operation}", arguments, [:hints, :lock], node, env)
  end

  defp classify_sql_bearing_call(_receiver, operation, arguments, node, env)
       when operation in [:constraint, :index, :table, :unique_index] and env.migration? do
    classify_sql_options(
      "migration.#{operation}_options",
      arguments,
      [:options, :where],
      node,
      env
    )
  end

  defp classify_sql_bearing_call(_receiver, operation, arguments, node, env)
       when operation in [
              :base_filter_sql,
              :calculations_to_sql,
              :create_table_options,
              :identity_wheres_to_sql
            ] do
    if env.ash_postgres?,
      do: classify_sql_setting("ash_postgres.#{operation}", arguments, node, env)
  end

  defp classify_sql_bearing_call(
         _receiver,
         :custom_index,
         arguments,
         node,
         %{ash_postgres?: true} = env
       ) do
    classify_sql_options("ash_postgres.custom_index", arguments, [:where], node, env) ||
      classify_sql_setting("ash_postgres.custom_index_fields", [List.first(arguments)], node, env)
  end

  defp classify_sql_bearing_call(
         _receiver,
         :check_constraint,
         arguments,
         node,
         %{ash_postgres?: true} = env
       ) do
    classify_sql_options("ash_postgres.check_constraint", arguments, [:check], node, env)
  end

  defp classify_sql_bearing_call(_receiver, _operation, _arguments, _node, _env), do: nil

  defp classify_sql_options(construct, arguments, keys, node, env) do
    values =
      arguments
      |> Enum.filter(&is_list/1)
      |> Enum.filter(&Keyword.keyword?/1)
      |> Enum.flat_map(fn options ->
        for key <- keys, Keyword.has_key?(options, key), do: Keyword.fetch!(options, key)
      end)

    if values == [] do
      nil
    else
      approval = if Enum.all?(values, &static_literal?/1), do: nil, else: :unresolved_sql
      occurrence(env, line_from_node(node), :raw_sql, construct, node, approval: approval)
    end
  end

  defp classify_sql_setting(construct, arguments, node, env) do
    if arguments == [] do
      nil
    else
      approval = if Enum.all?(arguments, &static_literal?/1), do: nil, else: :unresolved_sql
      occurrence(env, line_from_node(node), :raw_sql, construct, node, approval: approval)
    end
  end

  defp static_literal?(value) when is_atom(value) or is_binary(value) or is_number(value),
    do: true

  defp static_literal?(values) when is_list(values) do
    Enum.all?(values, fn
      {key, value} when is_atom(key) -> static_literal?(value)
      value -> static_literal?(value)
    end)
  end

  defp static_literal?({:{}, _metadata, values}), do: Enum.all?(values, &static_literal?/1)
  defp static_literal?(_value), do: false

  defp classify_migration_remote_helper("Oban.Migrations", operation, _node, env)
       when operation in [:up, :down] and env.preserve_uuidv7?,
       do: nil

  defp classify_migration_remote_helper("Ecto.Migration", _operation, _node, _env), do: nil

  defp classify_migration_remote_helper(receiver, _operation, node, env)
       when is_binary(receiver) do
    if migration_entrypoint?(env) do
      occurrence(env, line_from_node(node), :direct_ecto, "migration.helper_call", node,
        approval: :unresolved_sql
      )
    end
  end

  defp classify_migration_remote_helper(_receiver, _operation, _node, _env), do: nil

  defp migration_helper_escape?(operation, _arguments, env) do
    migration_entrypoint?(env) and operation not in @allowed_migration_locals and
      operation not in @syntax_operations and
      not operator?(operation) and
      not imported?(env, operation)
  end

  defp migration_entrypoint?(%{migration?: true, function: function}),
    do: function in ["change/0", "down/0", "up/0"]

  defp migration_entrypoint?(_env), do: false

  defp approved_uuidv7_loop?({:for, _metadata, arguments}, env) do
    env.preserve_uuidv7? and Enum.any?(arguments, &contains_uuidv7_fragment?/1)
  end

  defp contains_uuidv7_fragment?({:fragment, _metadata, ["uuidv7()"]}), do: true

  defp contains_uuidv7_fragment?(node) when is_tuple(node) do
    node |> Tuple.to_list() |> Enum.any?(&contains_uuidv7_fragment?/1)
  end

  defp contains_uuidv7_fragment?(nodes) when is_list(nodes),
    do: Enum.any?(nodes, &contains_uuidv7_fragment?/1)

  defp contains_uuidv7_fragment?(_node), do: false

  defp apply_alias([target], env), do: apply_alias([target, []], env)

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

  defp receiver_name(receiver, env), do: module_name(receiver, env)

  defp module_name({:__aliases__, _metadata, parts}, env) do
    if Enum.all?(parts, &is_atom/1) do
      name = Enum.map_join(parts, ".", &to_string/1)
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

  defp occurrence(env, line, class, construct, node, opts \\ []) do
    opts = Keyword.put(opts, :preserve_fingerprint?, env.preserve_uuidv7?)
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
      fingerprint_input: printable_node(node),
      preserve_fingerprint?: Keyword.get(opts, :preserve_fingerprint?, false)
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

      occurrence = Map.drop(occurrence, [:fingerprint_input, :preserve_fingerprint?])

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
      %{payload: ^node, fingerprint: fingerprint} when occurrence.preserve_fingerprint? ->
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
            printable_node(node)
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
    elixir_source?(path) or sql_file?(path)
  end

  defp elixir_source?(path), do: String.downcase(Path.extname(path)) in [".ex", ".exs"]
  defp sql_file?(path), do: Regex.match?(@sql_file_pattern, path)
  defp migration_path?(path), do: String.starts_with?(path, "priv/repo/migrations/")

  defp approved_uuidv7_context?(path, source) do
    case Map.fetch(@approved_uuidv7_migration_hashes, path) do
      {:ok, expected_hash} -> sha256(source) == expected_hash
      :error -> false
    end
  end

  defp sha256(value), do: Base.encode16(:crypto.hash(:sha256, value), case: :lower)
end
