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
    :disconnect_all,
    :explain,
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
    :insert_or_update,
    :insert_or_update!,
    :load,
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
  @ecto_sql_raw_sql_operations [
    :execute,
    :execute_ddl,
    :into,
    :query,
    :query!,
    :query_many,
    :query_many!,
    :reduce,
    :stream
  ]
  @ecto_sql_direct_operations [
    :checked_out?,
    :checkout,
    :disconnect_all,
    :explain,
    :in_transaction?,
    :insert_all,
    :rollback,
    :table_exists?,
    :to_sql,
    :transaction
  ]
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
  @postgrex_direct_operations [
    :call,
    :child_spec,
    :close,
    :close!,
    :listen,
    :listen!,
    :parameters,
    :rollback,
    :start_link,
    :transaction,
    :unlisten,
    :unlisten!
  ]
  @db_connection_raw_sql_operations [
    :execute,
    :execute!,
    :prepare,
    :prepare!,
    :prepare_execute,
    :prepare_execute!,
    :prepare_stream,
    :reduce,
    :stream
  ]
  @db_connection_direct_operations [
    :close,
    :close!,
    :child_spec,
    :get_connection_metrics,
    :disconnect_all,
    :rollback,
    :run,
    :start_link,
    :status,
    :transaction
  ]
  @ecto_migrator_operations [
    :down,
    :migrated_versions,
    :migrations,
    :run,
    :start_link,
    :up,
    :with_repo
  ]
  @postgres_adapter_operations [
    :execute,
    :lock_for_migrations,
    :storage_down,
    :storage_status,
    :storage_up,
    :structure_dump,
    :structure_load
  ]
  @private_database_modules [
    "DBConnection.Holder",
    "Ecto.Migration.Runner",
    "Ecto.Repo.Queryable",
    "Ecto.Repo.Registry",
    "Ecto.Repo.Schema",
    "Ecto.Repo.Supervisor",
    "Ecto.Repo.Transaction"
  ]
  @multi_operations [
    :all,
    :delete,
    :delete_all,
    :exists?,
    :insert,
    :insert_all,
    :insert_or_update,
    :merge,
    :one,
    :run,
    :update,
    :update_all
  ]
  @query_fragment_operations [:fragment, :unsafe_fragment]
  @migration_raw_sql_operations [:execute, :execute_file]
  @migration_direct_operations [:insert, :repo]
  @migration_control_flow [
    :&&,
    :and,
    :case,
    :cond,
    :if,
    :or,
    :receive,
    :try,
    :unless,
    :with,
    :||
  ]
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
                      "Ecto.Adapters.Postgres",
                      "Ecto.Adapters.Postgres.Connection",
                      "Ecto.Adapters.SQL",
                      "Ecto.Migration",
                      "Ecto.Migrator",
                      "Ecto.Multi",
                      "Ecto.Query",
                      "Ecto.Query.API",
                      "OfficeGraph.Repo",
                      "Postgrex",
                      "Postgrex.Notifications",
                      "Postgrex.ReplicationConnection",
                      "Postgrex.SimpleConnection"
                    ] ++ @private_database_modules
  @sql_file_pattern ~r/\.(?:pgsql|psql|sql)(?:\.(?:eex|heex|leex))?\z/i
  @database_client_pattern ~r/(?:\A|&&|\|\||[;|]|\$\(|`)\s*(?:(?:if|then|do|while|until|env|command|exec|sudo)\s+|!\s+)*(?:[A-Za-z_][A-Za-z0-9_]*=\S+\s+)*(?:\S*\/)?(?<client>clusterdb|createdb|createuser|dropdb|dropuser|pgbench|pg_dump|pg_restore|psql|reindexdb|vacuumdb)(?=\s|[;&|)`]|\z)/
  @javascript_script_extensions [".cjs", ".js", ".mjs", ".ts"]
  @javascript_database_client_pattern ~r/(?:\A|[\n=({,;]\s*)(?:await\s+)?(?<call>(?:[A-Za-z_$][A-Za-z0-9_$]*\.)?(?:exec|execFile|execFileSync|execSync|spawn|spawnSync))\s*\(\s*["'`](?:[^"'`\s]*\/)?(?<client>clusterdb|createdb|createuser|dropdb|dropuser|pgbench|pg_dump|pg_restore|psql|reindexdb|vacuumdb)(?=\s|["'`])/
  @javascript_block_comment_or_string_pattern ~r{("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`)|(/\*.*?\*/)}s

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

      script_source?(path, source) ->
        scan_script_source(path, source)

      true ->
        []
    end
  end

  defp scan_source(%{path: path}, root) do
    source = root |> Path.join(path) |> File.read!()
    scan_source(%{path: path, source: source}, root)
  end

  defp scan_script_source(path, source) do
    if javascript_script_source?(path) do
      scan_javascript_source(path, source)
    else
      source
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {line, line_number} ->
        for client <- shell_database_clients(line) do
          occurrence(
            path,
            line_number,
            nil,
            :raw_sql,
            "script.database_client.#{client}",
            line,
            approval: :unresolved_sql
          )
        end
      end)
    end
  end

  defp scan_javascript_source(path, source) do
    source = mask_javascript_comments(source)

    for [{call_start, _call_length}, {client_start, client_length}] <-
          Regex.scan(@javascript_database_client_pattern, source,
            capture: ["call", "client"],
            return: :index
          ) do
      client = binary_part(source, client_start, client_length)
      invocation = binary_part(source, call_start, client_start + client_length - call_start)
      line = source |> binary_part(0, call_start) |> newline_count() |> Kernel.+(1)

      occurrence(path, line, nil, :raw_sql, "script.database_client.#{client}", invocation,
        approval: :unresolved_sql
      )
    end
  end

  defp scan_elixir_source(path, source) do
    case Code.string_to_quoted(source, file: path, columns: true) do
      {:ok, ast} ->
        env = %{
          aliases: %{},
          ash_postgres_context: nil,
          ash_postgres?: false,
          function: nil,
          imports: %{},
          local_functions: MapSet.new(),
          migration?: migration_path?(path),
          module: nil,
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

  defp scan_node({:defmodule, _metadata, [module, [do: body]]}, env, occurrences) do
    module_env = %{
      env
      | aliases: %{},
        ash_postgres_context: nil,
        ash_postgres?: false,
        imports: %{},
        local_functions: declared_functions(body),
        module: declared_module(module, env)
    }

    {_module_env, occurrences} = scan_node(body, module_env, occurrences)
    {env, occurrences}
  end

  defp scan_node({kind, _metadata, arguments} = node, env, occurrences)
       when kind in [:def, :defp, :defmacro, :defmacrop] and is_list(arguments) do
    {name, arity} = function_identity(arguments)
    function = if name, do: "#{name}/#{arity}"
    body = function_body(arguments)

    child_env = %{env | function: function}
    {_child_env, occurrences} = scan_node(body, child_env, occurrences)

    if body == nil do
      scan_children(node, env, occurrences)
    else
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

  defp scan_node({:use, _metadata, arguments}, env, occurrences) do
    env =
      if ash_postgres_resource_use?(arguments, env),
        do: %{env | ash_postgres?: true},
        else: env

    scan_node(arguments, env, occurrences)
  end

  defp scan_node(
         {:custom_indexes, _metadata, [[do: body]]},
         %{ash_postgres?: true} = env,
         occurrences
       ) do
    child_env = %{env | ash_postgres_context: :custom_indexes}
    {_child_env, occurrences} = scan_node(body, child_env, occurrences)
    {env, occurrences}
  end

  defp scan_node({:quote, _metadata, arguments}, env, occurrences) when is_list(arguments) do
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

    quoted_body =
      Enum.find_value(arguments, fn
        options when is_list(options) ->
          if Keyword.keyword?(options), do: Keyword.get(options, :do)

        _argument ->
          nil
      end)

    scan_node(evaluated_arguments ++ quoted_evaluations(quoted_body), env, occurrences)
  end

  defp scan_node({{:., _metadata, [callee]}, call_metadata, arguments} = node, env, occurrences)
       when is_list(arguments) do
    occurrences =
      if migration_entrypoint?(env) do
        [
          occurrence(env, line(call_metadata), :direct_ecto, "migration.helper_call", node,
            approval: :unresolved_sql
          )
          | occurrences
        ]
      else
        occurrences
      end

    scan_children({callee, arguments}, env, occurrences)
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
      prepend_classification(
        occurrences,
        classify_remote_call(receiver, operation, arguments, node, env)
      )

    scan_children(node, env, occurrences)
  end

  defp scan_node({operation, metadata, nil} = node, env, occurrences)
       when is_atom(operation) do
    occurrences =
      if migration_helper_escape?(operation, [], env) and
           MapSet.member?(env.local_functions, {operation, 0}) do
        [
          occurrence(env, line(metadata), :direct_ecto, "migration.helper_call", node,
            approval: :unresolved_sql
          )
          | occurrences
        ]
      else
        occurrences
      end

    {env, occurrences}
  end

  defp scan_node({operation, metadata, arguments} = node, env, occurrences)
       when is_atom(operation) and is_list(arguments) do
    occurrences =
      prepend_classification(occurrences, classify_local_call(operation, arguments, node, env))

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

  defp prepend_classification(occurrences, nil), do: occurrences

  defp prepend_classification(occurrences, classified) when is_list(classified),
    do: classified ++ occurrences

  defp prepend_classification(occurrences, classified), do: [classified | occurrences]

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

  defp quoted_evaluations({operation, _metadata, [argument]})
       when operation in [:unquote, :unquote_splicing],
       do: [argument]

  defp quoted_evaluations(node) when is_tuple(node) do
    node |> Tuple.to_list() |> Enum.flat_map(&quoted_evaluations/1)
  end

  defp quoted_evaluations(nodes) when is_list(nodes),
    do: Enum.flat_map(nodes, &quoted_evaluations/1)

  defp quoted_evaluations(_node), do: []

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
      classify_operation(receiver, operation, arity, node, env) ||
        classify_migration_remote_helper(receiver, operation, node, env)
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
       when receiver in [
              "Postgrex",
              "Postgrex.Notifications",
              "Postgrex.ReplicationConnection",
              "Postgrex.SimpleConnection"
            ] and
              operation in @postgrex_direct_operations do
    occurrence(env, line_from_node(node), :direct_ecto, "#{receiver}.#{operation}", node)
  end

  defp classify_operation(receiver, operation, _arity, node, env)
       when receiver in [
              "Postgrex.Notifications",
              "Postgrex.ReplicationConnection",
              "Postgrex.SimpleConnection"
            ] and
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

  defp classify_operation("Ecto.Adapters.Postgres", operation, _arity, node, env)
       when operation in @postgres_adapter_operations do
    occurrence(
      env,
      line_from_node(node),
      :direct_ecto,
      "Ecto.Adapters.Postgres.#{operation}",
      node
    )
  end

  defp classify_operation("Ecto.Adapters.Postgres.Connection", operation, _arity, node, env)
       when operation in [:execute, :execute_ddl, :prepare_execute, :query] do
    construct = "Ecto.Adapters.Postgres.Connection.#{operation}"
    approval = approval_marker(:raw_sql, construct, call_arguments(node))
    occurrence(env, line_from_node(node), :raw_sql, construct, node, approval: approval)
  end

  defp classify_operation(receiver, operation, _arity, node, env)
       when receiver in @private_database_modules do
    occurrence(env, line_from_node(node), :direct_ecto, "#{receiver}.#{operation}", node)
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

  defp classify_operation("Ecto.Migration", operation, _arity, node, env)
       when operation in @query_fragment_operations do
    construct = to_string(operation)
    approval = approval_marker(:raw_sql, construct, call_arguments(node))
    occurrence(env, line_from_node(node), :raw_sql, construct, node, approval: approval)
  end

  defp classify_operation("Ecto.Migration", operation, _arity, node, env)
       when operation in @migration_direct_operations do
    occurrence(env, line_from_node(node), :direct_ecto, "migration.#{operation}", node)
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
       when receiver == "Ecto.Query" do
    approval = if static_literal?(value), do: nil, else: :unresolved_sql
    occurrence(env, line_from_node(node), :raw_sql, "query.lock", node, approval: approval)
  end

  defp classify_sql_bearing_call(receiver, operation, arguments, node, env)
       when receiver == "Ecto.Query" and operation in [:from, :join] do
    classify_sql_options("query.#{operation}", arguments, [:hints, :lock], node, env)
  end

  defp classify_sql_bearing_call(_receiver, operation, arguments, node, env)
       when operation in [
              :add,
              :add_if_not_exists,
              :constraint,
              :index,
              :modify,
              :table,
              :unique_index
            ] and env.migration? do
    [
      classify_sql_options(
        "migration.#{operation}_options",
        arguments,
        migration_sql_option_keys(operation),
        node,
        env
      ),
      classify_migration_index_fields(operation, arguments, node, env)
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      occurrences -> occurrences
    end
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
         :index,
         arguments,
         node,
         %{ash_postgres?: true, ash_postgres_context: :custom_indexes} = env
       ) do
    [
      classify_sql_options("ash_postgres.custom_index", arguments, [:where], node, env),
      classify_ash_postgres_index_fields(arguments, node, env)
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      occurrences -> occurrences
    end
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

  defp classify_migration_index_fields(operation, arguments, node, env)
       when operation in [:index, :unique_index] do
    classify_index_fields(
      Enum.at(arguments, 1),
      "migration.index_expression",
      node,
      env
    )
  end

  defp classify_migration_index_fields(_operation, _arguments, _node, _env), do: nil

  defp classify_ash_postgres_index_fields(arguments, node, env) do
    classify_index_fields(
      List.first(arguments),
      "ash_postgres.custom_index_expression",
      node,
      env
    )
  end

  defp classify_index_fields(fields, construct, node, env) do
    case fields do
      fields when is_list(fields) ->
        raw_fields = Enum.reject(fields, &safe_migration_index_field?/1)

        if raw_fields == [] do
          nil
        else
          approval =
            if Enum.all?(raw_fields, &static_migration_index_expression?/1),
              do: nil,
              else: :unresolved_sql

          occurrence(env, line_from_node(node), :raw_sql, construct, node, approval: approval)
        end

      field when is_atom(field) ->
        nil

      _dynamic_fields ->
        occurrence(env, line_from_node(node), :raw_sql, construct, node,
          approval: :unresolved_sql
        )
    end
  end

  defp migration_sql_option_keys(operation)
       when operation in [:add, :add_if_not_exists, :modify],
       do: [:generated]

  defp migration_sql_option_keys(:constraint), do: [:check, :exclude]
  defp migration_sql_option_keys(:table), do: [:modifiers, :options]

  defp migration_sql_option_keys(operation) when operation in [:index, :unique_index],
    do: [:options, :where]

  defp safe_migration_index_field?(field) when is_atom(field), do: true

  defp safe_migration_index_field?({direction, field})
       when direction in [
              :asc,
              :asc_nulls_first,
              :asc_nulls_last,
              :desc,
              :desc_nulls_first,
              :desc_nulls_last
            ] and is_atom(field),
       do: true

  defp safe_migration_index_field?(_field), do: false

  defp static_migration_index_expression?(field) when is_binary(field), do: true

  defp static_migration_index_expression?({direction, field})
       when direction in [
              :asc,
              :asc_nulls_first,
              :asc_nulls_last,
              :desc,
              :desc_nulls_first,
              :desc_nulls_last
            ] and is_binary(field),
       do: true

  defp static_migration_index_expression?(_field), do: false

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

  defp classify_migration_remote_helper("Ecto.Migration", operation, node, env) do
    if migration_entrypoint?(env) and operation not in @allowed_migration_locals do
      occurrence(env, line_from_node(node), :direct_ecto, "migration.helper_call", node,
        approval: :unresolved_sql
      )
    end
  end

  defp classify_migration_remote_helper(nil, _operation, node, env) do
    if migration_entrypoint?(env) do
      occurrence(env, line_from_node(node), :direct_ecto, "migration.helper_call", node,
        approval: :unresolved_sql
      )
    end
  end

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

  defp apply_alias([target, options], env) do
    aliases =
      target
      |> alias_modules(env)
      |> Enum.reduce(env.aliases, fn module, aliases ->
        case alias_name_for(module, options) do
          alias_name when is_binary(alias_name) -> Map.put(aliases, alias_name, module)
          _invalid -> aliases
        end
      end)

    {%{env | aliases: aliases}, []}
  end

  defp apply_alias([target], env), do: apply_alias([target, []], env)

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
      name = parts |> Enum.map_join(".", &to_string/1) |> String.trim_leading("Elixir.")
      resolve_alias(name, env.aliases)
    end
  end

  defp module_name({:__MODULE__, _metadata, _context}, _env), do: nil

  defp module_name(atom, _env) when is_atom(atom) do
    atom
    |> Atom.to_string()
    |> String.trim_leading("Elixir.")
  end

  defp module_name(_node, _env), do: nil

  defp declared_module({:__aliases__, _metadata, parts} = module, %{module: parent})
       when is_list(parts) and parts != [] and is_binary(parent) do
    case module_name(module, %{aliases: %{}}) do
      name when is_binary(name) -> parent <> "." <> name
      _invalid -> nil
    end
  end

  defp declared_module(module, env), do: module_name(module, env)

  defp alias_modules(
         {{:., _metadata, [prefix, :{}]}, _call_metadata, suffixes},
         env
       )
       when is_list(suffixes) do
    with prefix when is_binary(prefix) <- module_name(prefix, env) do
      Enum.flat_map(suffixes, fn suffix ->
        case module_name(suffix, env) do
          suffix when is_binary(suffix) -> [prefix <> "." <> suffix]
          _invalid -> []
        end
      end)
    else
      _invalid -> []
    end
  end

  defp alias_modules(target, env) do
    case module_name(target, env) do
      module when is_binary(module) -> [module]
      _invalid -> []
    end
  end

  defp resolve_alias(name, aliases) do
    case Map.fetch(aliases, name) do
      {:ok, resolved} ->
        resolved

      :error ->
        case String.split(name, ".", parts: 2) do
          [first, rest] -> Map.get(aliases, first, first) <> "." <> rest
          [first] -> Map.get(aliases, first, first)
        end
    end
  end

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

  defp function_identity([{:when, _metadata, [signature | _guards]} | rest]),
    do: function_identity([signature | rest])

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

  defp declared_functions({:__block__, _metadata, expressions}) when is_list(expressions) do
    MapSet.new(expressions, &declared_function/1)
    |> MapSet.delete(nil)
  end

  defp declared_functions(node) do
    case declared_function(node) do
      nil -> MapSet.new()
      function -> MapSet.new([function])
    end
  end

  defp declared_function({kind, _metadata, arguments})
       when kind in [:def, :defp, :defmacro, :defmacrop] and is_list(arguments) do
    case function_identity(arguments) do
      {nil, _arity} -> nil
      function -> function
    end
  end

  defp declared_function(_node), do: nil

  defp call_arguments({{:., _dot_metadata, [_receiver, _operation]}, _metadata, arguments}),
    do: arguments

  defp call_arguments({_operation, _metadata, arguments}) when is_list(arguments), do: arguments
  defp call_arguments(_node), do: []

  defp approval_marker(:raw_sql, "migration.execute_file", _arguments), do: :unresolved_sql

  defp approval_marker(:raw_sql, construct, arguments) do
    if construct
       |> sql_payloads(arguments)
       |> then(&(&1 != [] and Enum.all?(&1, fn value -> static_sql_literal?(value) end))) do
      nil
    else
      :unresolved_sql
    end
  end

  defp static_sql_literal?(value) when is_binary(value), do: true

  defp static_sql_literal?({:<<>>, _metadata, segments}),
    do: static_binary_segments?(segments)

  defp static_sql_literal?(_value), do: false

  defp sql_payloads("migration.execute", arguments), do: arguments

  defp sql_payloads(construct, arguments)
       when construct in [
              "Ecto.Adapters.SQL.query",
              "Ecto.Adapters.SQL.query!",
              "Ecto.Adapters.SQL.query_many",
              "Ecto.Adapters.SQL.query_many!",
              "Ecto.Adapters.SQL.stream",
              "Postgrex.query",
              "Postgrex.query!",
              "Postgrex.stream",
              "Ecto.Adapters.Postgres.Connection.query"
            ] do
    [Enum.at(arguments, 1)]
  end

  defp sql_payloads(construct, arguments)
       when construct in [
              "Postgrex.prepare",
              "Postgrex.prepare!",
              "Postgrex.prepare_execute",
              "Postgrex.prepare_execute!",
              "Ecto.Adapters.Postgres.Connection.prepare_execute"
            ] do
    [Enum.at(arguments, 2)]
  end

  defp sql_payloads("Ecto.Adapters.Postgres.Connection.execute_ddl", arguments),
    do: [List.first(arguments)]

  defp sql_payloads(construct, _arguments)
       when construct in [
              "Ecto.Adapters.SQL.execute",
              "Ecto.Adapters.SQL.execute_ddl",
              "Ecto.Adapters.SQL.into",
              "Ecto.Adapters.SQL.reduce",
              "Postgrex.execute",
              "Postgrex.execute!",
              "Ecto.Adapters.Postgres.Connection.execute"
            ],
       do: []

  defp sql_payloads(_construct, arguments), do: [List.first(arguments)]

  defp static_binary_segments?(segments) do
    Enum.all?(segments, fn
      segment when is_binary(segment) -> true
      {:"::", _metadata, [value, _type]} -> is_binary(value)
      _segment -> false
    end)
  end

  defp ash_postgres_resource_use?([resource, options], env) when is_list(options) do
    module_name(resource, env) == "Ash.Resource" and
      options
      |> Keyword.get(:data_layer)
      |> module_name(env) == "AshPostgres.DataLayer"
  end

  defp ash_postgres_resource_use?(_arguments, _env), do: false

  defp static_atom(atom) when is_atom(atom), do: atom
  defp static_atom(_node), do: nil

  defp keyword_option(options, key) when is_list(options) do
    if Keyword.keyword?(options), do: Keyword.get(options, key)
  end

  defp keyword_option(_options, _key), do: nil

  defp occurrence(env, line, class, construct, node, opts \\ []) do
    opts =
      opts
      |> Keyword.put(:preserve_fingerprint?, env.preserve_uuidv7?)
      |> Keyword.put_new(:caller, env.module || "unknown")
      |> Keyword.put_new(:arity, call_arity(node))

    occurrence(env.path, line, env.function, class, construct, node, opts)
  end

  defp occurrence(path, line, function, class, construct, node, opts) do
    base = %{
      arity: Keyword.get(opts, :arity),
      caller: Keyword.get(opts, :caller),
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

  defp call_arity({{:., _metadata, _receiver}, _call_metadata, arguments})
       when is_list(arguments),
       do: length(arguments)

  defp call_arity({_operation, _metadata, arguments}) when is_list(arguments),
    do: length(arguments)

  defp call_arity(_node), do: nil

  defp tracked_sources(root) do
    {output, 0} = System.cmd("git", ["ls-files", "-z"], cd: root)

    output
    |> String.split(<<0>>, trim: true)
    |> Enum.flat_map(&tracked_source(&1, root))
  end

  defp tracked_source(path, root) do
    full_path = Path.join(root, path)

    if boundary_source_path?(path) or shell_shebang_file?(full_path) do
      [%{path: path, source: File.read!(full_path)}]
    else
      []
    end
  end

  defp boundary_source_path?(path),
    do: elixir_source?(path) or sql_file?(path) or script_source_path?(path)

  defp elixir_source?(path), do: String.downcase(Path.extname(path)) in [".ex", ".exs"]
  defp sql_file?(path), do: Regex.match?(@sql_file_pattern, path)

  defp script_source?(path, source) do
    script_source_path?(path) or shell_shebang?(source)
  end

  defp script_source_path?(path),
    do:
      String.starts_with?(path, "bin/") or
        String.downcase(Path.extname(path)) in [".bash", ".sh", ".zsh"] or
        javascript_script_source?(path)

  defp shell_shebang_file?(path) do
    case File.open(path, [:read, :binary], &IO.binread(&1, :line)) do
      {:ok, line} when is_binary(line) -> shell_shebang?(line)
      _unreadable_or_empty -> false
    end
  end

  defp shell_shebang?(source) do
    case source |> :binary.split("\n") |> List.first() do
      "#!" <> command ->
        command
        |> String.split()
        |> Enum.any?(&(Path.basename(&1) in ["bash", "dash", "ksh", "sh", "zsh"]))

      _no_shebang ->
        false
    end
  end

  defp javascript_script_source?(path) do
    String.downcase(Path.extname(path)) in @javascript_script_extensions and
      "scripts" in Path.split(path)
  end

  defp shell_database_clients(line) do
    for [client] <- Regex.scan(@database_client_pattern, line, capture: :all_names), do: client
  end

  defp mask_javascript_comments(source) do
    source
    |> then(
      &Regex.replace(@javascript_block_comment_or_string_pattern, &1, fn
        full, _string, "" -> full
        _full, "", comment -> String.replace(comment, ~r/[^\n]/, " ")
      end)
    )
    |> String.split("\n", trim: false)
    |> Enum.map_join("\n", fn line ->
      if line |> String.trim_leading() |> String.starts_with?("//") do
        String.duplicate(" ", String.length(line))
      else
        line
      end
    end)
  end

  defp newline_count(value) do
    value
    |> :binary.matches("\n")
    |> length()
  end

  defp migration_path?(path), do: String.starts_with?(path, "priv/repo/migrations/")

  defp approved_uuidv7_context?(path, source) do
    case Map.fetch(@approved_uuidv7_migration_hashes, path) do
      {:ok, expected_hash} -> sha256(source) == expected_hash
      :error -> false
    end
  end

  defp sha256(value), do: Base.encode16(:crypto.hash(:sha256, value), case: :lower)
end
