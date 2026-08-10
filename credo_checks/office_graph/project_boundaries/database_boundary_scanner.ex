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
    :one,
    :one!,
    :preload,
    :preload!,
    :put_dynamic_repo,
    :reload,
    :reload!,
    :rollback,
    :stream,
    :stop,
    :transaction,
    :transaction!,
    :transact,
    :update,
    :update!,
    :update_all
  ]
  @ecto_sql_raw_sql_operations [:execute, :query, :query!, :query_many, :query_many!, :stream]
  @ecto_sql_direct_operations [:checkout, :disconnect_all, :explain]
  @ecto_migrator_operations [
    :down,
    :migrated_versions,
    :migrations,
    :run,
    :start_link,
    :up,
    :with_repo
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
    :child_spec,
    :close,
    :close!,
    :connection_module,
    :disconnect_all,
    :get_connection_metrics,
    :register_as_pool,
    :rollback,
    :run,
    :start_link,
    :status,
    :transaction
  ]
  @expression_receiver_direct_operations [
    :checkout,
    :close,
    :close!,
    :delete,
    :delete!,
    :delete_all,
    :disconnect_all,
    :insert,
    :insert!,
    :insert_all,
    :insert_or_update,
    :insert_or_update!,
    :put_dynamic_repo,
    :rollback,
    :start_link,
    :stop,
    :transact,
    :transaction,
    :transaction!,
    :update,
    :update!,
    :update_all
    | @ecto_migrator_operations
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
    :child_spec,
    :close,
    :close!,
    :parameters,
    :rollback,
    :start_link,
    :transaction
  ]
  @zero_arity_variable_operations [:checked_out?, :get_dynamic_repo, :in_transaction?, :stop]
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
    "Oban.Migrations" => [{"down/0", :down}, {"up/0", :up}]
  }
  @repository_use_modules ["AshPostgres.Repo", "Ecto.Repo"]
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
    :timestamps,
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
    "Postgrex"
  ]
  @process_execution_modules ["System", "os"]
  @database_cli_executables [
    "clusterdb",
    "createdb",
    "createuser",
    "dropdb",
    "dropuser",
    "initdb",
    "pg_ctl",
    "pg_restore",
    "pgbench",
    "postgres",
    "psql",
    "reindexdb",
    "vacuumdb"
  ]
  @command_dispatch_executables ["bash", "docker", "env", "sh", "xargs", "zsh"]
  @dynamic_dispatch_modules ["Function", "Task", "Task.Supervisor"]
  @mfa_process_operations [:spawn, :spawn_link, :spawn_monitor, :spawn_opt, :spawn_request]
  @mfa_task_operations [:async, :async_stream, :start, :start_link]
  @mfa_task_supervisor_operations [
    :async,
    :async_nolink,
    :async_stream,
    :async_stream_nolink,
    :start_child
  ]
  @mfa_dispatch_operations Enum.uniq(
                             @mfa_process_operations ++
                               @mfa_task_operations ++
                               @mfa_task_supervisor_operations
                           )
  @reflection_modules ["Code", "Module"]
  @reflection_operations %{
    "Code" => [
      :compile_file,
      :compile_quoted,
      :compile_string,
      :eval_file,
      :eval_quoted,
      :eval_string,
      :require_file
    ],
    "Module" => [:create, :eval_quoted]
  }
  @sql_payload_positions %{
    "Ecto.Adapters.SQL.execute" => [],
    "Ecto.Adapters.SQL.query" => [1],
    "Ecto.Adapters.SQL.query!" => [1],
    "Ecto.Adapters.SQL.query_many" => [1],
    "Ecto.Adapters.SQL.query_many!" => [1],
    "Ecto.Adapters.SQL.stream" => [1],
    "Postgrex.execute" => [],
    "Postgrex.execute!" => [],
    "Postgrex.prepare" => [2],
    "Postgrex.prepare!" => [2],
    "Postgrex.prepare_execute" => [2],
    "Postgrex.prepare_execute!" => [2],
    "Postgrex.query" => [1],
    "Postgrex.query!" => [1],
    "Postgrex.stream" => []
  }
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

  @approved_uuidv7_loops %{
    "priv/repo/migrations/20260729233957_initial.exs" => %{
      attribute: :uuid_v7_primary_keys,
      fingerprint: "sha256:3d364d9192867f0617ae65e12790893e1b49b57e1a4d9bb8d8e2b8133c72c41d"
    },
    "priv/repo/migrations/20260730005539_integrate_workos_enterprise_identity.exs" => %{
      attribute: :uuid_v7_primary_key_tables,
      fingerprint: "sha256:bc9767a4f23cb90fcf3812abc2df4971b150500ae0c913b96dbd3173e7e93827"
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
    {paths, tracked_paths, missing_environments} =
      case Keyword.fetch(opts, :paths) do
        {:ok, paths} ->
          {paths, nil, []}

        :error ->
          {paths, missing_environments} = compiled_beam_paths(root)
          {paths, tracked_path_set(root), missing_environments}
      end

    compiled_occurrences =
      paths
      |> Enum.map(fn path -> {Path.basename(path), scan_beam(path, root, tracked_paths)} end)
      |> merge_compiled_beam_scans()

    (compiled_occurrences ++
       Enum.map(missing_environments, &compiled_environment_missing_occurrence/1))
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
          approved_migration_loops: approved_migration_loops(path, ast),
          function: nil,
          imports: %{},
          migration?: migration_path?(path),
          path: path,
          quote_depth: 0,
          query_dsl?: false,
          repository_module?: false
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
        imports: %{},
        migration?: migration_path?(env.path),
        repository_module?: module_name(module, env) == "OfficeGraph.Repo"
    }

    {_module_env, occurrences} = scan_node(body, module_env, occurrences)
    {env, occurrences}
  end

  defp scan_node({kind, metadata, arguments} = node, env, occurrences)
       when kind in [:def, :defp, :defmacro, :defmacrop] and is_list(arguments) do
    {name, arity, guarded?} = function_identity(arguments)
    function = if name, do: "#{name}/#{arity}"
    body = function_body(arguments)

    child_env = %{env | function: function}

    occurrences =
      if guarded? and migration_entrypoint?(child_env) do
        [
          occurrence(child_env, line(metadata), :direct_ecto, "migration.control_flow", node,
            approval: :unresolved_sql
          )
          | occurrences
        ]
      else
        occurrences
      end

    {_child_env, occurrences} = scan_node(body, child_env, occurrences)

    if body == nil do
      scan_children(node, env, occurrences)
    else
      {_line, _metadata} = {line(metadata), metadata}
      {env, occurrences}
    end
  end

  defp scan_node({:@, _metadata, [{_name, _name_metadata, [value]}]}, env, occurrences) do
    scan_node(value, env, occurrences)
  end

  defp scan_node({:__block__, _metadata, expressions}, env, occurrences)
       when is_list(expressions) do
    scan_expressions(expressions, env, occurrences)
  end

  defp scan_node({:quote, _metadata, arguments}, env, occurrences)
       when is_list(arguments) do
    quoted_env = %{env | quote_depth: env.quote_depth + 1}
    {_quoted_env, occurrences} = scan_node(arguments, quoted_env, occurrences)
    {env, occurrences}
  end

  defp scan_node({operation, _metadata, arguments}, %{quote_depth: depth} = env, occurrences)
       when operation in [:unquote, :unquote_splicing] and depth > 0 and is_list(arguments) do
    unquoted_env = %{env | quote_depth: depth - 1}
    {_unquoted_env, occurrences} = scan_node(arguments, unquoted_env, occurrences)
    {env, occurrences}
  end

  defp scan_node({:alias, _metadata, arguments} = node, env, occurrences) do
    {env, alias_occurrences} = apply_alias(arguments, env)
    {env, occurrences ++ alias_occurrences_for(node, env, alias_occurrences)}
  end

  defp scan_node({:import, metadata, arguments}, env, occurrences) do
    {env, import_occurrences} = apply_import(arguments, metadata, env)
    {env, occurrences ++ import_occurrences}
  end

  defp scan_node({:defdelegate, _metadata, arguments} = node, env, occurrences)
       when is_list(arguments) do
    occurrences =
      case classify_defdelegate(arguments, node, env) do
        nil -> occurrences
        occurrence -> [occurrence | occurrences]
      end

    scan_children(node, env, occurrences)
  end

  defp scan_node({:use, _metadata, [target | _options]} = node, env, occurrences) do
    case module_name(target, env) do
      "Ecto.Migration" ->
        {%{env | migration?: true}, occurrences}

      repository_module when repository_module in @repository_use_modules ->
        occurrences =
          if env.repository_module? do
            occurrences
          else
            [
              occurrence(
                env,
                line_from_node(node),
                :direct_ecto,
                "#{repository_module}.use",
                node,
                approval: :unresolved_sql
              )
              | occurrences
            ]
          end

        {%{env | repository_module?: true}, occurrences}

      _module ->
        scan_children(node, env, occurrences)
    end
  end

  defp scan_node({:for, metadata, arguments} = node, env, occurrences)
       when is_list(arguments) do
    occurrences =
      if migration_execution_context?(env) and not approved_uuidv7_loop?(node, env) do
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
      if migration_execution_context?(env) do
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
      case classify_expression_receiver(receiver, operation, node, env) do
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
    {_child_env, occurrences} =
      node
      |> Tuple.to_list()
      |> scan_node(env, occurrences)

    {env, occurrences}
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

  defp classify_remote_call(receiver, :capture, [target, operation, _arity], node, env) do
    if receiver_name(receiver, env) == "Function" do
      classify_dynamic_dispatch(target, operation, :capture, node, env)
    end
  end

  defp classify_remote_call(receiver, :make_fun, [target, operation, _arity], node, env) do
    if receiver_name(receiver, env) == "erlang" do
      classify_dynamic_dispatch(target, operation, :capture, node, env)
    end
  end

  defp classify_remote_call(receiver, operation, arguments, node, env)
       when operation in @mfa_dispatch_operations do
    resolved_receiver = receiver_name(receiver, env)

    classify_mfa_dispatch(resolved_receiver, operation, arguments, node, env) ||
      classify_operation(resolved_receiver, operation, length(arguments), node, env)
  end

  defp classify_remote_call(receiver, operation, arguments, node, env) do
    receiver
    |> receiver_name(env)
    |> classify_operation(operation, length(arguments), node, env)
  end

  defp classify_local_call(:apply, [receiver, operation | _rest], node, env) do
    classify_apply(receiver, operation, node, env)
  end

  defp classify_local_call(:capture, [receiver, operation, _arity], node, env) do
    if imported_receiver(env, :capture, 3) == "Function" do
      classify_dynamic_dispatch(receiver, operation, :capture, node, env)
    end
  end

  defp classify_local_call(operation, arguments, node, env)
       when operation in @mfa_dispatch_operations do
    receiver = imported_receiver(env, operation, length(arguments)) || "Kernel"

    classify_mfa_dispatch(receiver, operation, arguments, node, env) ||
      classify_local_database_call(operation, arguments, node, env)
  end

  defp classify_local_call(operation, arguments, node, env) do
    classify_local_database_call(operation, arguments, node, env)
  end

  defp classify_local_database_call(operation, arguments, node, env) do
    arity = length(arguments)

    with nil <- classify_migration_local(operation, arguments, node, env),
         receiver when not is_nil(receiver) <- local_database_receiver(env, operation, arity) do
      classify_operation(receiver, operation, arity, node, env)
    end
  end

  defp local_database_receiver(%{repository_module?: true}, operation, _arity)
       when operation in @repo_raw_sql_operations or operation in @repo_direct_operations,
       do: "OfficeGraph.Repo"

  defp local_database_receiver(env, operation, arity),
    do: imported_receiver(env, operation, arity)

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
        approval = approval_marker(:raw_sql, to_string(operation), arguments)

        occurrence(env, line_from_node(node), :raw_sql, to_string(operation), node,
          approval: approval
        )

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

  defp classify_operation("DBConnection", operation, _arity, node, env)
       when operation in @db_connection_raw_sql_operations do
    occurrence(
      env,
      line_from_node(node),
      :raw_sql,
      "DBConnection.#{operation}",
      node,
      approval: :unresolved_sql
    )
  end

  defp classify_operation("DBConnection", operation, _arity, node, env)
       when operation in @db_connection_direct_operations do
    occurrence(env, line_from_node(node), :direct_ecto, "DBConnection.#{operation}", node)
  end

  defp classify_operation("Ecto.Adapters.SQL", operation, _arity, node, env)
       when operation in @ecto_sql_direct_operations do
    occurrence(env, line_from_node(node), :direct_ecto, "Ecto.Adapters.SQL.#{operation}", node)
  end

  defp classify_operation("Ecto.Migrator", operation, _arity, node, env)
       when operation in @ecto_migrator_operations do
    occurrence(env, line_from_node(node), :direct_ecto, "Ecto.Migrator.#{operation}", node,
      approval: :unresolved_sql
    )
  end

  defp classify_operation(receiver, operation, _arity, node, env)
       when receiver in @process_execution_modules and
              ((receiver == "System" and operation in [:cmd, :shell]) or
                 (receiver == "os" and operation == :cmd)) do
    case process_command_status(receiver, operation, node) do
      :database_cli ->
        occurrence(env, line_from_node(node), :raw_sql, "process.database_cli", node,
          approval: :unresolved_sql
        )

      :dynamic ->
        occurrence(env, line_from_node(node), :raw_sql, "process.dynamic_command", node,
          approval: :unresolved_sql
        )

      :safe ->
        nil
    end
  end

  defp classify_operation("Postgrex", operation, _arity, node, env)
       when operation in @postgrex_raw_sql_operations do
    construct = "Postgrex.#{operation}"
    approval = approval_marker(:raw_sql, construct, call_arguments(node))
    occurrence(env, line_from_node(node), :raw_sql, construct, node, approval: approval)
  end

  defp classify_operation("Postgrex", operation, _arity, node, env)
       when operation in @postgrex_direct_operations do
    occurrence(env, line_from_node(node), :direct_ecto, "Postgrex.#{operation}", node)
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

  defp classify_operation("Ecto.Migration.repo()", operation, _arity, node, env)
       when operation in @repo_direct_operations do
    occurrence(env, line_from_node(node), :direct_ecto, "Repo.#{operation}", node)
  end

  defp classify_operation(receiver, operation, _arity, node, env)
       when receiver in @reflection_modules do
    if operation in Map.fetch!(@reflection_operations, receiver) do
      occurrence(
        env,
        line_from_node(node),
        :direct_ecto,
        "reflection.#{receiver}.#{operation}",
        node,
        approval: :unresolved_sql
      )
    end
  end

  defp classify_operation(receiver, operation, _arity, node, env)
       when receiver in @database_modules and operation == :apply do
    class = dynamic_dispatch_class(receiver)

    occurrence(env, line_from_node(node), class, "#{receiver}.apply", node,
      approval: :unresolved_sql
    )
  end

  defp classify_operation(_receiver, _operation, _arity, _node, _env), do: nil

  defp classify_apply(receiver, operation, node, env) do
    classify_dynamic_dispatch(receiver, operation, :apply, node, env)
  end

  defp classify_mfa_dispatch(receiver, operation, arguments, node, env) do
    receiver
    |> mfa_dispatch_targets(operation, arguments)
    |> Enum.find_value(fn {target, target_operation} ->
      classify_dynamic_dispatch(target, target_operation, operation, node, env)
    end)
  end

  defp mfa_dispatch_targets(receiver, operation, arguments)
       when receiver in ["Kernel", "erlang"] and operation in @mfa_process_operations do
    case {operation, arguments} do
      {operation, [target, target_operation, _arguments]}
      when operation in [:spawn, :spawn_link, :spawn_monitor, :spawn_request] ->
        [{target, target_operation}]

      {operation, [_node, target, target_operation, _arguments]}
      when operation in [:spawn, :spawn_link, :spawn_monitor, :spawn_request] ->
        [{target, target_operation}]

      {:spawn_opt, [target, target_operation, _arguments, _options]} ->
        [{target, target_operation}]

      {:spawn_opt, [_node, target, target_operation, _arguments, _options]} ->
        [{target, target_operation}]

      {:spawn_request, [_node, target, target_operation, _arguments, _options]} ->
        [{target, target_operation}]

      _other ->
        []
    end
  end

  defp mfa_dispatch_targets("Task", operation, arguments)
       when operation in @mfa_task_operations do
    case {operation, arguments} do
      {operation, [target, target_operation, _arguments]}
      when operation in [:async, :start, :start_link] ->
        [{target, target_operation}]

      {:async_stream, [_enumerable, target, target_operation, _arguments | _options]} ->
        [{target, target_operation}]

      _other ->
        []
    end
  end

  defp mfa_dispatch_targets("Task.Supervisor", operation, arguments)
       when operation in @mfa_task_supervisor_operations do
    case {operation, arguments} do
      {operation, [_supervisor, target, target_operation, _arguments | _options]}
      when operation in [:async, :async_nolink, :start_child] ->
        [{target, target_operation}]

      {operation, [_supervisor, _enumerable, target, target_operation, _arguments | _options]}
      when operation in [:async_stream, :async_stream_nolink] ->
        [{target, target_operation}]

      _other ->
        []
    end
  end

  defp mfa_dispatch_targets(_receiver, _operation, _arguments), do: []

  defp classify_dynamic_dispatch(receiver, operation, kind, node, env) do
    resolved_receiver = receiver_name(receiver, env)
    resolved_operation = static_atom(operation)

    cond do
      resolved_receiver in @database_modules ->
        class = dynamic_dispatch_class(resolved_receiver)

        occurrence(env, line_from_node(node), class, "#{resolved_receiver}.#{kind}", node,
          approval: :unresolved_sql
        )

      database_operation?(resolved_operation) ->
        class = if raw_sql_operation?(resolved_operation), do: :raw_sql, else: :direct_ecto

        occurrence(env, line_from_node(node), class, "variable_receiver.#{kind}", node,
          approval: :unresolved_sql
        )

      database_shaped_variable_receiver?(receiver) ->
        occurrence(env, line_from_node(node), :raw_sql, "variable_receiver.#{kind}", node,
          approval: :unresolved_sql
        )

      true ->
        nil
    end
  end

  defp classify_defdelegate([head, options], node, env) when is_list(options) do
    {name, arity, _guarded?} = function_identity([head])
    operation = keyword_option(options, :as) || name

    with operation when is_atom(operation) <- operation,
         target when not is_nil(target) <- options |> keyword_option(:to) |> module_name(env) do
      classify_operation(target, operation, arity, node, env)
    end
  end

  defp classify_defdelegate(_arguments, _node, _env), do: nil

  defp migration_helper_escape?(operation, _arguments, env) do
    migration_execution_context?(env) and operation not in @allowed_migration_locals and
      operation not in @syntax_operations and
      not operator?(operation) and
      not imported?(env, operation)
  end

  defp migration_execution_context?(%{migration?: true, function: nil}), do: true
  defp migration_execution_context?(env), do: migration_entrypoint?(env)

  defp migration_entrypoint?(%{migration?: true, function: function}),
    do: function in ["after_begin/0", "before_commit/0", "change/0", "down/0", "up/0"]

  defp migration_entrypoint?(_env), do: false

  defp remote_migration_helper_escape?(receiver, operation, env) do
    if migration_execution_context?(env) do
      case receiver_name(receiver, env) do
        receiver when receiver in @database_modules ->
          false

        receiver when is_binary(receiver) ->
          not (migration_entrypoint?(env) and
                 {env.function, operation} in Map.get(
                   @allowed_external_migration_helpers,
                   receiver,
                   []
                 ))

        nil ->
          true
      end
    else
      false
    end
  end

  defp approved_uuidv7_loop?(node, env),
    do: MapSet.member?(env.approved_migration_loops, printable_node(node))

  defp approved_migration_loops(path, ast) do
    case Map.fetch(@approved_uuidv7_loops, path) do
      {:ok, %{attribute: attribute, fingerprint: expected_fingerprint}} ->
        {attribute_node, loops} = migration_attribute_and_loops(ast, attribute)

        loops
        |> Enum.filter(fn loop ->
          uuidv7_loop_fingerprint(attribute_node, loop) == expected_fingerprint
        end)
        |> Enum.map(&printable_node/1)
        |> MapSet.new()

      :error ->
        MapSet.new()
    end
  end

  defp migration_attribute_and_loops(ast, attribute) do
    {_ast, result} =
      Macro.prewalk(ast, {nil, []}, fn
        {:@, _metadata, [{name, _name_metadata, arguments}]} = node, {_attribute_node, loops}
        when name == attribute and is_list(arguments) and length(arguments) == 1 ->
          {node, {node, loops}}

        {:for, _metadata, _arguments} = node, {attribute_node, loops} ->
          loops = if references_attribute?(node, attribute), do: [node | loops], else: loops
          {node, {attribute_node, loops}}

        node, result ->
          {node, result}
      end)

    result
  end

  defp references_attribute?(node, attribute) do
    {_node, found?} =
      Macro.prewalk(node, false, fn
        {:@, _metadata, [{name, _name_metadata, context}]} = child, _found?
        when name == attribute and is_atom(context) ->
          {child, true}

        child, found? ->
          {child, found?}
      end)

    found?
  end

  defp uuidv7_loop_fingerprint(attribute_node, loop) do
    payload = {printable_node(attribute_node), printable_node(loop)}

    "sha256:" <>
      Base.encode16(:crypto.hash(:sha256, :erlang.term_to_binary(payload)), case: :lower)
  end

  defp dynamic_module_receiver?({{:., _metadata, [module, operation]}, _, _}, env)
       when operation in [:concat, :safe_concat],
       do: module_name(module, env) == "Module"

  defp dynamic_module_receiver?(_receiver, _env), do: false

  defp classify_variable_receiver(receiver, operation, node, env) do
    if variable_receiver_database_operation?(
         receiver,
         operation,
         length(call_arguments(node))
       ) do
      class = if raw_sql_operation?(operation), do: :raw_sql, else: :direct_ecto

      occurrence(env, line_from_node(node), class, "variable_receiver.#{operation}", node,
        approval: :unresolved_sql
      )
    end
  end

  defp classify_expression_receiver(receiver, operation, node, env) do
    if uncompiled_elixir_source?(env.path) and receiver_name(receiver, env) == nil and
         not variable_receiver?(receiver) and
         not dynamic_module_receiver?(receiver, env) and call_arguments(node) != [] and
         database_operation?(operation) do
      class = if raw_sql_operation?(operation), do: :raw_sql, else: :direct_ecto

      occurrence(env, line_from_node(node), class, "expression_receiver.#{operation}", node,
        approval: :unresolved_sql
      )
    end
  end

  defp variable_receiver?({name, _metadata, context})
       when is_atom(name) and is_atom(context),
       do: true

  defp variable_receiver?(_receiver), do: false

  defp database_shaped_variable_receiver?({name, _metadata, context})
       when is_atom(name) and is_atom(context),
       do: database_shaped_variable_name?(name)

  defp database_shaped_variable_receiver?(_receiver), do: false

  defp uncompiled_elixir_source?(path), do: Path.extname(path) == ".exs"

  defp variable_receiver_database_operation?({name, _metadata, context}, operation, arity)
       when is_atom(name) and is_atom(context) do
    (arity > 0 and
       (operation in @repo_raw_sql_operations or operation in @repo_direct_operations)) or
      (database_shaped_variable_name?(name) and database_operation_arity?(operation, arity))
  end

  defp variable_receiver_database_operation?(_receiver, _operation, _arity), do: false

  defp database_shaped_variable_name?(name) do
    name =
      name
      |> to_string()
      |> String.trim_leading("_")
      |> String.split("@", parts: 2)
      |> hd()

    name in [
      "adapter",
      "conn",
      "connection",
      "db",
      "migrator",
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
        "_migrator",
        "_multi",
        "_repo",
        "_repository",
        "_sql"
      ])
  end

  defp database_operation?(operation),
    do:
      raw_sql_operation?(operation) or operation in @repo_direct_operations or
        operation in @ecto_sql_direct_operations or operation in @db_connection_direct_operations or
        operation in @postgrex_direct_operations or operation in @multi_operations or
        operation in @ecto_migrator_operations

  defp database_operation_arity?(operation, arity) when arity > 0,
    do: database_operation?(operation)

  defp database_operation_arity?(operation, 0),
    do: operation in @zero_arity_variable_operations

  defp database_operation_arity?(_operation, _arity), do: false

  defp raw_sql_operation?(operation),
    do:
      operation in @repo_raw_sql_operations or operation in @ecto_sql_raw_sql_operations or
        operation in @db_connection_raw_sql_operations or
        operation in @postgrex_raw_sql_operations or operation in @migration_raw_sql_operations or
        operation in @query_fragment_operations

  defp dynamic_dispatch_class(receiver)
       when receiver in ["Ecto.Migrator", "Ecto.Multi"],
       do: :direct_ecto

  defp dynamic_dispatch_class(_receiver), do: :raw_sql

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

    if module in @database_modules or module in @dynamic_dispatch_modules or
         module in @reflection_modules or module in @process_execution_modules do
      imported = imported_operations(module, options)

      imports =
        Enum.reduce(imported, env.imports, fn
          :all, imports -> Map.put(imports, {:all, module}, module)
          operation, imports -> Map.put(imports, operation, module)
        end)

      occurrences =
        if imported == [:all] and module != "Ecto.Query" and
             module not in @dynamic_dispatch_modules do
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

      mode when mode in [:functions, :macros] ->
        [:all]

      operations ->
        Enum.map(operations, fn {operation, arity} -> {operation, arity} end)
    end
  end

  defp imported_receiver(env, operation, arity) do
    Map.get(env.imports, {operation, arity}) ||
      Enum.find_value(env.imports, fn
        {{:all, module}, imported_module} when imported_module == module ->
          if imported_operation?(module, operation), do: module

        _entry ->
          nil
      end)
  end

  defp imported?(env, operation) do
    Enum.any?(env.imports, fn
      {{^operation, _arity}, _module} ->
        true

      {{:all, module}, imported_module} when imported_module == module ->
        imported_operation?(module, operation)

      _entry ->
        false
    end)
  end

  defp imported_operation?("OfficeGraph.Repo", operation),
    do: operation in @repo_raw_sql_operations or operation in @repo_direct_operations

  defp imported_operation?("Ecto.Adapters.SQL", operation),
    do: operation in @ecto_sql_raw_sql_operations or operation in @ecto_sql_direct_operations

  defp imported_operation?("DBConnection", operation),
    do:
      operation in @db_connection_raw_sql_operations or
        operation in @db_connection_direct_operations

  defp imported_operation?("Postgrex", operation),
    do: operation in @postgrex_raw_sql_operations or operation in @postgrex_direct_operations

  defp imported_operation?("Ecto.Multi", operation), do: operation in @multi_operations
  defp imported_operation?("Ecto.Migrator", operation), do: operation in @ecto_migrator_operations
  defp imported_operation?("Function", operation), do: operation == :capture
  defp imported_operation?("System", operation), do: operation in [:cmd, :shell]
  defp imported_operation?("os", operation), do: operation == :cmd

  defp imported_operation?(module, operation) when module in ["Ecto.Query", "Ecto.Query.API"],
    do:
      operation in @query_fragment_operations or
        Map.has_key?(@query_sql_option_operations, operation)

  defp imported_operation?("Ecto.Migration", operation),
    do:
      operation in @migration_raw_sql_operations or operation in @migration_direct_operations or
        operation in @query_fragment_operations

  defp imported_operation?(module, operation) when module in @reflection_modules,
    do: operation in Map.fetch!(@reflection_operations, module)

  defp imported_operation?(_module, _operation), do: false

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

  defp function_identity([{:when, _metadata, [head | _guards]} | _rest]) do
    {name, arity, _guarded?} = function_identity([head])
    {name, arity, true}
  end

  defp function_identity([{name, _metadata, arguments} | _rest])
       when is_atom(name) and is_list(arguments),
       do: {name, minimum_arity(arguments), false}

  defp function_identity([{name, _metadata, context} | _rest])
       when is_atom(name) and is_atom(context),
       do: {name, 0, false}

  defp function_identity(_arguments), do: {nil, 0, false}

  defp minimum_arity(arguments) do
    Enum.count(arguments, fn
      {:\\, _metadata, [_argument, _default]} -> false
      _argument -> true
    end)
  end

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

  defp call_arguments({:call, _metadata, _callee, arguments}) when is_list(arguments),
    do: arguments

  defp call_arguments(_node), do: []

  defp process_command_status(receiver, operation, node) do
    arguments = call_arguments(node)

    command_arguments =
      case {receiver, operation, arguments} do
        {"System", :cmd, [executable, args | _options]} -> [executable, args]
        {"System", :shell, [command | _options]} -> [command]
        {"os", :cmd, [command | _options]} -> [command]
        _call -> []
      end

    {literals, dynamic?} = command_literals(command_arguments)
    executable = arguments |> List.first() |> command_literals() |> elem(0) |> List.first()

    cond do
      Enum.any?(literals, &database_cli_reference?/1) ->
        :database_cli

      read_only_pg_dump_command?(receiver, operation, node) ->
        :safe

      is_nil(executable) ->
        :dynamic

      command_dispatch_executable?(executable) and dynamic? ->
        :dynamic

      receiver == "os" and dynamic? ->
        :dynamic

      operation == :shell and dynamic? ->
        :dynamic

      true ->
        :safe
    end
  end

  defp command_literals(nodes) when is_list(nodes) do
    if Enum.all?(nodes, &is_integer/1) do
      {[List.to_string(nodes)], false}
    else
      Enum.reduce(nodes, {[], false}, fn node, {literals, dynamic?} ->
        {node_literals, node_dynamic?} = command_literals(node)
        {literals ++ node_literals, dynamic? or node_dynamic?}
      end)
    end
  end

  defp command_literals(value) when is_binary(value), do: {[value], false}
  defp command_literals({nil, _metadata}), do: {[], false}

  defp command_literals({:cons, _metadata, head, tail}) do
    {head_literals, head_dynamic?} = command_literals(head)
    {tail_literals, tail_dynamic?} = command_literals(tail)
    {head_literals ++ tail_literals, head_dynamic? or tail_dynamic?}
  end

  defp command_literals({:string, _metadata, characters}) when is_list(characters),
    do: {[List.to_string(characters)], false}

  defp command_literals({:bin, _metadata, elements}) when is_list(elements) do
    Enum.reduce(elements, {[], false}, fn
      {:bin_element, _element_metadata, value, _size, _type}, {literals, dynamic?} ->
        {element_literals, element_dynamic?} = command_literals(value)
        {literals ++ element_literals, dynamic? or element_dynamic?}

      _element, {literals, _dynamic?} ->
        {literals, true}
    end)
  end

  defp command_literals({:<<>>, _metadata, segments}) when is_list(segments) do
    if static_binary_segments?(segments) do
      value =
        Enum.map_join(segments, fn
          segment when is_binary(segment) -> segment
          {:"::", _segment_metadata, [segment, _type]} -> segment
        end)

      {[value], false}
    else
      {[], true}
    end
  end

  defp command_literals({:sigil_c, _metadata, [{:<<>>, _, segments}, []]}) do
    command_literals({:<<>>, [], segments})
  end

  defp command_literals(_node), do: {[], true}

  defp database_cli_reference?(literal) do
    literal
    |> command_words()
    |> Enum.any?(&(&1 in @database_cli_executables))
  end

  defp read_only_pg_dump_command?("System", :cmd, node) do
    case call_arguments(node) do
      [executable, arguments | _options] ->
        case static_command_literal(executable) do
          "pg_dump" -> true
          "docker" -> docker_pg_dump_arguments?(arguments)
          _executable -> false
        end

      _arguments ->
        false
    end
  end

  defp read_only_pg_dump_command?(_receiver, _operation, _node), do: false

  defp docker_pg_dump_arguments?(arguments) do
    case command_argument_nodes(arguments) do
      [exec, env_flag, _env, _container, pg_dump | _rest] ->
        static_command_literal(exec) == "exec" and
          static_command_literal(env_flag) in ["-e", "--env"] and
          static_command_literal(pg_dump) == "pg_dump"

      [exec, _container, pg_dump | _rest] ->
        static_command_literal(exec) == "exec" and
          static_command_literal(pg_dump) == "pg_dump"

      _arguments ->
        false
    end
  end

  defp command_argument_nodes(arguments) when is_list(arguments), do: arguments
  defp command_argument_nodes({nil, _metadata}), do: []

  defp command_argument_nodes({:cons, _metadata, head, tail}) do
    case command_argument_nodes(tail) do
      :dynamic -> :dynamic
      tail -> [head | tail]
    end
  end

  defp command_argument_nodes(_arguments), do: :dynamic

  defp static_command_literal(node) do
    case command_literals(node) do
      {[literal], false} -> literal |> Path.basename() |> String.downcase()
      _literal -> nil
    end
  end

  defp command_dispatch_executable?(literal) do
    literal
    |> Path.basename()
    |> String.downcase()
    |> then(&(&1 in @command_dispatch_executables))
  end

  defp command_words(literal) do
    literal
    |> String.downcase()
    |> String.split(~r/[^a-z0-9_\.\/-]+/, trim: true)
    |> Enum.map(&Path.basename/1)
  end

  defp approval_marker(:raw_sql, construct, _arguments)
       when construct in ["migration.execute_file", "Ecto.Migration.execute_file"],
       do: :unresolved_sql

  defp approval_marker(:raw_sql, construct, arguments) do
    payloads = sql_payload_arguments(construct, arguments)

    if payloads != [] and Enum.all?(payloads, &static_sql_payload?/1) do
      nil
    else
      :unresolved_sql
    end
  end

  defp sql_payload_arguments(construct, arguments)
       when construct in ["migration.execute", "Ecto.Migration.execute"],
       do: arguments

  defp sql_payload_arguments(construct, arguments) do
    case Map.fetch(@sql_payload_positions, construct) do
      {:ok, positions} -> Enum.map(positions, &Enum.at(arguments, &1))
      :error -> Enum.take(arguments, 1)
    end
  end

  defp static_sql_payload?(payload) do
    case payload do
      value when is_binary(value) ->
        true

      {:<<>>, _metadata, segments} ->
        static_binary_segments?(segments)

      _value ->
        false
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
    env.path
    |> occurrence(line, env.function, class, construct, node, opts)
    |> Map.put(:compiled_match?, Map.get(env, :quote_depth, 0) == 0)
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

  defp line({line, _column}) when is_integer(line), do: line
  defp line(metadata) when is_list(metadata), do: Keyword.get(metadata, :line)
  defp line(line) when is_integer(line), do: line
  defp line(_metadata), do: nil

  defp error_line(metadata), do: Keyword.get(metadata, :line, 1)

  defp tracked_sources(root) do
    {output, 0} = System.cmd("git", ["ls-files", "-z"], cd: root)

    output
    |> String.split(<<0>>, trim: true)
    |> Enum.filter(&boundary_source?/1)
    |> Enum.flat_map(fn path ->
      case File.read(Path.join(root, path)) do
        {:ok, source} -> [%{path: path, source: source}]
        {:error, :enoent} -> []
        {:error, reason} -> raise File.Error, reason: reason, action: "read file", path: path
      end
    end)
  end

  defp boundary_source?(path) do
    Path.extname(path) in @source_extensions
  end

  defp elixir_source?(path), do: Path.extname(path) in [".ex", ".exs"]
  defp sql_file?(path), do: Path.extname(path) in @sql_file_extensions
  defp migration_path?(path), do: String.starts_with?(path, "priv/repo/migrations/")

  defp compiled_beam_paths(root) do
    [mix_env(), "test", "prod"]
    |> Enum.uniq()
    |> Enum.reduce({[], []}, fn env, {paths, missing_environments} ->
      environment_paths =
        root
        |> Path.join("_build/#{env}/lib/office_graph/ebin/*.beam")
        |> Path.wildcard()
        |> Enum.reject(&String.contains?(&1, "ProjectQuality.DatabaseBoundaryScanner"))

      if environment_paths == [] do
        {paths, [env | missing_environments]}
      else
        {paths ++ environment_paths, missing_environments}
      end
    end)
    |> then(fn {paths, missing_environments} ->
      {paths, Enum.reverse(missing_environments)}
    end)
  end

  defp compiled_environment_missing_occurrence(environment) do
    occurrence(
      "mix.exs",
      1,
      nil,
      :direct_ecto,
      "compiled.environment_missing",
      {:missing_environment, environment},
      approval: :unresolved_sql
    )
  end

  defp scan_beam(path, root, tracked_paths) do
    source = compiled_source(path, root)

    cond do
      tracked_paths && not MapSet.member?(tracked_paths, source) ->
        []

      true ->
        scan_beam_abstract_code(path, source, root)
    end
  end

  defp scan_beam_abstract_code(path, source, root) do
    case :beam_lib.chunks(String.to_charlist(path), [:abstract_code]) do
      {:ok, {_module, [abstract_code: {:raw_abstract_v1, forms}]}} ->
        Enum.flat_map(forms, &compiled_form_occurrences(&1, source))

      error ->
        [compiled_metadata_unavailable_occurrence(path, source, root, error)]
    end
  end

  defp merge_compiled_beam_scans(beam_scans) do
    beam_scans
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.flat_map(fn {_beam, environment_scans} ->
      environment_scans
      |> Enum.reduce(%{}, fn occurrences, maximums ->
        occurrences
        |> Enum.group_by(&compiled_occurrence_identity/1)
        |> Enum.reduce(maximums, fn {identity, occurrences}, maximums ->
          count = length(occurrences)
          representative = hd(occurrences)

          Map.update(maximums, identity, {count, representative}, fn
            {existing_count, _existing} when count > existing_count ->
              {count, representative}

            existing ->
              existing
          end)
        end)
      end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.flat_map(fn {_identity, {count, occurrence}} ->
        List.duplicate(occurrence, count)
      end)
    end)
  end

  defp compiled_occurrence_identity(occurrence) do
    {
      occurrence.path,
      occurrence.line,
      occurrence.class,
      occurrence.construct,
      occurrence.function,
      occurrence.fingerprint_input,
      Map.get(occurrence, :approval)
    }
  end

  defp compiled_metadata_unavailable_occurrence(beam_path, source, root, error) do
    payload = {Path.relative_to(beam_path, root), error}

    occurrence(source, 1, nil, :direct_ecto, "compiled.abstract_code_unavailable", payload,
      approval: :unresolved_sql
    )
  end

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

  defp compiled_form_occurrences({:function, _annotation, name, arity, _clauses} = form, source) do
    if generated_canonical_repo_form?(form, source) do
      []
    else
      form
      |> compiled_node_occurrences(source, "#{name}/#{arity}", [])
      |> Enum.reverse()
    end
  end

  defp compiled_form_occurrences(form, source) do
    form
    |> compiled_node_occurrences(source, nil, [])
    |> Enum.reverse()
  end

  defp generated_canonical_repo_form?(
         {:function, annotation, _name, _arity, _clauses},
         "lib/office_graph/repo.ex"
       ),
       do: :erl_anno.generated(annotation)

  defp generated_canonical_repo_form?(_form, _source), do: false

  defp compiled_node_occurrences(
         {:call, _line, {:atom, _fun_line, :apply}, arguments} = node,
         source,
         function,
         occurrences
       ) do
    occurrences = compiled_apply_occurrences(arguments, node, source, function, occurrences)
    compiled_node_occurrences(Tuple.to_list(node), source, function, occurrences)
  end

  defp compiled_node_occurrences(
         {:call, _line,
          {:remote, _remote_line, {:atom, _module_line, :erlang}, {:atom, _fun_line, :apply}},
          arguments} = node,
         source,
         function,
         occurrences
       ) do
    occurrences = compiled_apply_occurrences(arguments, node, source, function, occurrences)
    compiled_node_occurrences(Tuple.to_list(node), source, function, occurrences)
  end

  defp compiled_node_occurrences(
         {:call, _line,
          {:remote, _remote_line, {:atom, _module_line, :erlang}, {:atom, _fun_line, :make_fun}},
          arguments} = node,
         source,
         function,
         occurrences
       ) do
    occurrences = compiled_capture_occurrences(arguments, node, source, function, occurrences)
    compiled_node_occurrences(Tuple.to_list(node), source, function, occurrences)
  end

  defp compiled_node_occurrences(
         {:call, _line, {:remote, _remote_line, receiver, {:atom, _fun_line, operation}},
          arguments} = node,
         source,
         function,
         occurrences
       )
       when not is_tuple(receiver) or elem(receiver, 0) != :atom do
    occurrences =
      if compiled_unresolved_receiver_operation?(receiver, operation, arguments) do
        class = if raw_sql_operation?(operation), do: :raw_sql, else: :direct_ecto

        receiver_kind =
          if compiled_variable_receiver?(receiver), do: "variable", else: "expression"

        [
          occurrence(
            source,
            line_from_node(node),
            function,
            class,
            "#{receiver_kind}_receiver.#{operation}",
            node,
            approval: :unresolved_sql
          )
          | occurrences
        ]
      else
        occurrences
      end

    compiled_node_occurrences(Tuple.to_list(node), source, function, occurrences)
  end

  defp compiled_node_occurrences(
         {:call, _line,
          {:remote, _remote_line, {:atom, _module_line, module}, {:atom, _fun_line, fun}},
          arguments} = node,
         source,
         function,
         occurrences
       ) do
    module = module |> Atom.to_string() |> String.trim_leading("Elixir.")

    occurrences =
      compiled_mfa_dispatch_occurrences(
        module,
        fun,
        arguments,
        node,
        source,
        function,
        occurrences
      )

    occurrence =
      classify_operation(
        module,
        fun,
        length(arguments),
        node,
        %{path: source, function: function, migration?: false}
      )

    occurrences = if occurrence, do: [occurrence | occurrences], else: occurrences
    compiled_node_occurrences(Tuple.to_list(node), source, function, occurrences)
  end

  defp compiled_node_occurrences(nodes, source, function, occurrences) when is_list(nodes) do
    Enum.reduce(nodes, occurrences, &compiled_node_occurrences(&1, source, function, &2))
  end

  defp compiled_node_occurrences(node, source, function, occurrences) when is_tuple(node) do
    node
    |> Tuple.to_list()
    |> compiled_node_occurrences(source, function, occurrences)
  end

  defp compiled_node_occurrences(_node, _source, _function, occurrences), do: occurrences

  defp compiled_unresolved_receiver_operation?(receiver, operation, arguments) do
    arity = length(arguments)

    database_operation_arity?(operation, arity) and
      (raw_sql_operation?(operation) or compiled_variable_receiver?(receiver) or
         operation in @expression_receiver_direct_operations)
  end

  defp compiled_apply_occurrences(
         [receiver, operation | _rest],
         node,
         source,
         function,
         occurrences
       ) do
    compiled_dynamic_dispatch_occurrences(
      receiver,
      operation,
      :apply,
      node,
      source,
      function,
      occurrences
    )
  end

  defp compiled_apply_occurrences(_arguments, _node, _source, _function, occurrences),
    do: occurrences

  defp compiled_capture_occurrences(
         [receiver, operation, _arity],
         node,
         source,
         function,
         occurrences
       ) do
    compiled_dynamic_dispatch_occurrences(
      receiver,
      operation,
      :capture,
      node,
      source,
      function,
      occurrences
    )
  end

  defp compiled_capture_occurrences(_arguments, _node, _source, _function, occurrences),
    do: occurrences

  defp compiled_mfa_dispatch_occurrences(
         receiver,
         operation,
         arguments,
         node,
         source,
         function,
         occurrences
       ) do
    receiver
    |> mfa_dispatch_targets(operation, arguments)
    |> Enum.reduce(occurrences, fn {target, target_operation}, occurrences ->
      compiled_dynamic_dispatch_occurrences(
        target,
        target_operation,
        operation,
        node,
        source,
        function,
        occurrences
      )
    end)
  end

  defp compiled_dynamic_dispatch_occurrences(
         receiver_node,
         operation_node,
         kind,
         node,
         source,
         function,
         occurrences
       ) do
    receiver = compiled_module(receiver_node)
    operation = compiled_operation(operation_node)

    cond do
      receiver in @database_modules ->
        class = dynamic_dispatch_class(receiver)

        [
          occurrence(source, line_from_node(node), function, class, "#{receiver}.#{kind}", node,
            approval: :unresolved_sql
          )
          | occurrences
        ]

      database_operation?(operation) ->
        class = if raw_sql_operation?(operation), do: :raw_sql, else: :direct_ecto

        [
          occurrence(
            source,
            line_from_node(node),
            function,
            class,
            "variable_receiver.#{kind}",
            node,
            approval: :unresolved_sql
          )
          | occurrences
        ]

      compiled_database_shaped_variable?(receiver_node) ->
        [
          occurrence(
            source,
            line_from_node(node),
            function,
            :raw_sql,
            "variable_receiver.#{kind}",
            node,
            approval: :unresolved_sql
          )
          | occurrences
        ]

      true ->
        occurrences
    end
  end

  defp compiled_module({:atom, _line, atom}) when is_atom(atom) do
    atom |> Atom.to_string() |> String.trim_leading("Elixir.")
  end

  defp compiled_module(_node), do: nil

  defp compiled_variable_receiver?({:var, _line, name}) when is_atom(name), do: true
  defp compiled_variable_receiver?(_receiver), do: false

  defp compiled_database_shaped_variable?({:var, _line, name}) when is_atom(name),
    do: database_shaped_variable_name?(name)

  defp compiled_database_shaped_variable?(_receiver), do: false

  defp compiled_operation({:atom, _line, operation}) when is_atom(operation), do: operation
  defp compiled_operation(_node), do: nil

  defp mix_env do
    if Process.whereis(Mix.State), do: Mix.env(), else: :dev
  rescue
    _error -> :dev
  end
end
