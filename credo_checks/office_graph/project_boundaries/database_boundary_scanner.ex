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
    :start_link,
    :stream,
    :stop,
    :transaction,
    :transaction!,
    :transact,
    :update,
    :update!,
    :update_all
  ]
  @generated_canonical_repo_static_calls MapSet.new([
                                           {"aggregate/3", "Ecto.Repo.Queryable", :aggregate, 4},
                                           {"aggregate/3", "Ecto.Repo.Queryable", :aggregate, 5},
                                           {"aggregate/4", "Ecto.Repo.Queryable", :aggregate, 5},
                                           {"all/2", "Ecto.Repo.Queryable", :all, 3},
                                           {"all_by/3", "Ecto.Repo.Queryable", :all_by, 4},
                                           {"delete/2", "Ecto.Repo.Schema", :delete, 4},
                                           {"delete!/2", "Ecto.Repo.Schema", :delete!, 4},
                                           {"delete_all/2", "Ecto.Repo.Queryable", :delete_all,
                                            3},
                                           {"disconnect_all/2", "Ecto.Adapters.SQL",
                                            :disconnect_all, 3},
                                           {"exists?/2", "Ecto.Repo.Queryable", :exists?, 3},
                                           {"explain/3", "Ecto.Adapters.SQL", :explain, 4},
                                           {"get/3", "Ecto.Repo.Queryable", :get, 4},
                                           {"get!/3", "Ecto.Repo.Queryable", :get!, 4},
                                           {"get_by/3", "Ecto.Repo.Queryable", :get_by, 4},
                                           {"get_by!/3", "Ecto.Repo.Queryable", :get_by!, 4},
                                           {"in_transaction?/0", "Ecto.Repo.Transaction",
                                            :in_transaction?, 1},
                                           {"config/0", "Ecto.Repo.Supervisor", :init_config, 4},
                                           {"start_link/1", "Ecto.Repo.Supervisor", :start_link,
                                            4},
                                           {"aggregate/3", "Ecto.Repo.Supervisor", :tuplet, 2},
                                           {"aggregate/4", "Ecto.Repo.Supervisor", :tuplet, 2},
                                           {"all/2", "Ecto.Repo.Supervisor", :tuplet, 2},
                                           {"all_by/3", "Ecto.Repo.Supervisor", :tuplet, 2},
                                           {"delete/2", "Ecto.Repo.Supervisor", :tuplet, 2},
                                           {"delete!/2", "Ecto.Repo.Supervisor", :tuplet, 2},
                                           {"delete_all/2", "Ecto.Repo.Supervisor", :tuplet, 2},
                                           {"exists?/2", "Ecto.Repo.Supervisor", :tuplet, 2},
                                           {"get/3", "Ecto.Repo.Supervisor", :tuplet, 2},
                                           {"get!/3", "Ecto.Repo.Supervisor", :tuplet, 2},
                                           {"get_by/3", "Ecto.Repo.Supervisor", :tuplet, 2},
                                           {"get_by!/3", "Ecto.Repo.Supervisor", :tuplet, 2},
                                           {"insert/2", "Ecto.Repo.Schema", :insert, 4},
                                           {"insert!/2", "Ecto.Repo.Schema", :insert!, 4},
                                           {"insert_all/3", "Ecto.Repo.Schema", :insert_all, 5},
                                           {"insert_or_update/2", "Ecto.Repo.Schema",
                                            :insert_or_update, 4},
                                           {"insert_or_update!/2", "Ecto.Repo.Schema",
                                            :insert_or_update!, 4},
                                           {"insert/2", "Ecto.Repo.Supervisor", :tuplet, 2},
                                           {"insert!/2", "Ecto.Repo.Supervisor", :tuplet, 2},
                                           {"insert_all/3", "Ecto.Repo.Supervisor", :tuplet, 2},
                                           {"insert_or_update/2", "Ecto.Repo.Supervisor", :tuplet,
                                            2},
                                           {"insert_or_update!/2", "Ecto.Repo.Supervisor",
                                            :tuplet, 2},
                                           {"load/2", "Ecto.Repo.Schema", :load, 3},
                                           {"one/2", "Ecto.Repo.Queryable", :one, 3},
                                           {"one!/2", "Ecto.Repo.Queryable", :one!, 3},
                                           {"one/2", "Ecto.Repo.Supervisor", :tuplet, 2},
                                           {"one!/2", "Ecto.Repo.Supervisor", :tuplet, 2},
                                           {"preload/3", "Ecto.Repo.Supervisor", :tuplet, 2},
                                           {"query/3", "Ecto.Adapters.SQL", :query, 4},
                                           {"query!/3", "Ecto.Adapters.SQL", :query!, 4},
                                           {"query_many/3", "Ecto.Adapters.SQL", :query_many, 4},
                                           {"query_many!/3", "Ecto.Adapters.SQL", :query_many!,
                                            4},
                                           {"reload/2", "Ecto.Repo.Queryable", :reload, 3},
                                           {"reload!/2", "Ecto.Repo.Queryable", :reload!, 3},
                                           {"reload/2", "Ecto.Repo.Supervisor", :tuplet, 2},
                                           {"reload!/2", "Ecto.Repo.Supervisor", :tuplet, 2},
                                           {"rollback/1", "Ecto.Repo.Transaction", :rollback, 2},
                                           {"stream/2", "Ecto.Repo.Queryable", :stream, 3},
                                           {"stream/2", "Ecto.Repo.Supervisor", :tuplet, 2},
                                           {"transact/2", "Ecto.Repo.Transaction", :transact, 4},
                                           {"transact/2", "Ecto.Repo.Supervisor", :tuplet, 2},
                                           {"update/2", "Ecto.Repo.Schema", :update, 4},
                                           {"update!/2", "Ecto.Repo.Schema", :update!, 4},
                                           {"update_all/3", "Ecto.Repo.Queryable", :update_all,
                                            4},
                                           {"update/2", "Ecto.Repo.Supervisor", :tuplet, 2},
                                           {"update!/2", "Ecto.Repo.Supervisor", :tuplet, 2},
                                           {"update_all/3", "Ecto.Repo.Supervisor", :tuplet, 2}
                                         ])
  @generated_canonical_repo_dynamic_calls MapSet.new([
                                            {"checked_out?/0", :checked_out?, 1},
                                            {"checkout/2", :checkout, 3}
                                          ])
  @canonical_repo_use_line 6
  @ecto_sql_raw_sql_operations [:execute, :query, :query!, :query_many, :query_many!, :stream]
  @ecto_sql_direct_operations [:checkout, :disconnect_all, :explain]
  @postgres_adapter_storage_operations [
    :storage_down,
    :storage_status,
    :storage_up,
    :structure_dump,
    :structure_load
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
    | @ecto_migrator_operations ++ @postgres_adapter_storage_operations
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
    add: {2, [:generated]},
    add_if_not_exists: {2, [:generated]},
    constraint: {2, [:check, :exclude, :where]},
    index: {2, [:where]},
    modify: {2, [:generated]},
    table: {1, [:options]},
    unique_index: {2, [:where]}
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
    "Ecto.Adapters.Postgres",
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
  @private_persistence_modules [
    "Ecto.Adapters.Postgres.Connection",
    "Ecto.Migration.Runner",
    "Ecto.Repo.Queryable",
    "Ecto.Repo.Schema",
    "Ecto.Repo.Supervisor",
    "Ecto.Repo.Transaction"
  ]
  @mix_shell_modules ["Mix.Shell", "Mix.Shell.IO", "Mix.Shell.Process", "Mix.Shell.Quiet"]
  @process_execution_modules ["Port", "System", "erlang", "os" | @mix_shell_modules]
  @process_execution_operations [
    {"Port", :open},
    {"System", :cmd},
    {"System", :shell},
    {"erlang", :open_port},
    {"os", :cmd}
    | Enum.map(@mix_shell_modules, &{&1, :cmd})
  ]
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
  @command_dispatch_executables [
    "ash",
    "bash",
    "busybox",
    "cmd",
    "cmd.exe",
    "csh",
    "dash",
    "docker",
    "elvish",
    "elixir",
    "erl",
    "env",
    "fish",
    "ksh",
    "mix",
    "mksh",
    "node",
    "nu",
    "perl",
    "powershell",
    "powershell.exe",
    "python",
    "python3",
    "pwsh",
    "ruby",
    "sh",
    "tcsh",
    "xargs",
    "xonsh",
    "zsh"
  ]
  @mfa_process_operations [
    :hibernate,
    :spawn,
    :spawn_link,
    :spawn_monitor,
    :spawn_opt,
    :spawn_request
  ]
  @mfa_rpc_operations [
    :async_call,
    :block_call,
    :call,
    :cast,
    :eval_everywhere,
    :multicall,
    :parallel_eval,
    :pmap
  ]
  @mfa_erpc_operations [:call, :cast, :multicall, :multicast, :send_request]
  @mfa_task_operations [:async, :async_stream, :start, :start_link]
  @mfa_task_supervisor_operations [
    :async,
    :async_nolink,
    :async_stream,
    :async_stream_nolink,
    :start_child
  ]
  @mfa_supervisor_operations [:start_child]
  @mfa_elixir_supervisor_operations [:start_child, :start_link]
  @mfa_proc_lib_operations [
    :hibernate,
    :spawn,
    :spawn_link,
    :spawn_opt,
    :start,
    :start_link,
    :start_monitor
  ]
  @mfa_scheduled_timer_operations [:apply_after, :apply_interval, :apply_repeatedly]
  @mfa_timer_operations [:tc | @mfa_scheduled_timer_operations]
  @dynamic_dispatch_operations %{
    "DynamicSupervisor" => @mfa_supervisor_operations,
    "Function" => [:capture],
    "Process" => [:spawn],
    "Supervisor" => @mfa_elixir_supervisor_operations,
    "Task" => @mfa_task_operations,
    "Task.Supervisor" => @mfa_task_supervisor_operations,
    "erpc" => @mfa_erpc_operations,
    "proc_lib" => @mfa_proc_lib_operations,
    "rpc" => @mfa_rpc_operations,
    "supervisor" => @mfa_supervisor_operations,
    "timer" => @mfa_timer_operations
  }
  @dynamic_dispatch_modules Map.keys(@dynamic_dispatch_operations)
  @mfa_dispatch_operations Enum.uniq(
                             @mfa_process_operations ++
                               @mfa_rpc_operations ++
                               @mfa_erpc_operations ++
                               @mfa_task_operations ++
                               @mfa_task_supervisor_operations ++
                               @mfa_elixir_supervisor_operations ++
                               @mfa_proc_lib_operations ++
                               @mfa_timer_operations
                           )
  @migration_callback_attributes [
    :after_compile,
    :after_verify,
    :before_compile,
    :on_definition,
    :on_load
  ]
  @reflection_modules [
    "Code",
    "Config.Reader",
    "EEx",
    "IEx.Helpers",
    "Kernel.ParallelCompiler",
    "Macro",
    "Mix.Task",
    "Mix.Tasks.Eval",
    "Mix.Tasks.Run",
    "Module",
    "c",
    "code",
    "compile",
    "erl_eval",
    "file"
  ]
  @reflection_operations %{
    "Code" => [
      :compile_file,
      :compile_quoted,
      :compile_string,
      :eval_file,
      :eval_quoted,
      :eval_quoted_with_env,
      :eval_string,
      :load_file,
      :require_file
    ],
    "Config.Reader" => [:eval!, :load, :read!, :read_imports!],
    "EEx" => [
      :compile_file,
      :compile_string,
      :eval_file,
      :eval_string,
      :function_from_file,
      :function_from_string
    ],
    "IEx.Helpers" => [:c, :r, :recompile],
    "Kernel.ParallelCompiler" => [
      :compile,
      :compile_to_path,
      :files,
      :files_to_path,
      :require
    ],
    "Macro" => [:compile_apply, :expand, :expand_once],
    "Mix.Task" => [:rerun, :run],
    "Mix.Tasks.Eval" => [:run],
    "Mix.Tasks.Run" => [:run],
    "Module" => [:create, :eval_quoted],
    "c" => [:appcall, :c, :erlangrc, :l, :lc, :lc_batch, :nc, :nl],
    "code" => [
      :atomic_load,
      :ensure_loaded,
      :ensure_modules_loaded,
      :finish_loading,
      :load_abs,
      :load_binary,
      :load_file,
      :load_native_partial,
      :prepare_loading
    ],
    "compile" => [:file, :forms, :noenv_file, :noenv_forms],
    "erl_eval" => [:eval_str, :expr, :expr_list, :exprs, :match_clause],
    "file" => [:eval, :path_eval, :path_script, :script]
  }
  @reviewed_runtime_compiler_fixtures [
    {"test/office_graph/project_quality/database_boundary_gate_test.exs", "compile_file!/2"},
    {"test/office_graph/project_quality/database_boundary_scanner_test.exs", "compile_file!/2"},
    {"test/office_graph/project_quality/project_boundaries_credo_check_test.exs",
     "compile_file!/2"}
  ]
  @allowed_dependency_macro_modules [
    "Absinthe.Relay.Schema",
    "Absinthe.Relay.Schema.Notation",
    "Absinthe.Schema",
    "Absinthe.Schema.Notation",
    "Application",
    "Ash.Domain",
    "Ash.Policy.SimpleCheck",
    "Ash.Query",
    "Ash.Resource",
    "Ash.Resource.Actions.Implementation",
    "Ash.Resource.Change",
    "Ash.TypedStruct",
    "AshGraphql",
    "AshGraphql.Type",
    "AshJsonApi.Router",
    "AshPostgres.Repo",
    "Boundary",
    "Config",
    "Credo.Check",
    "Ecto",
    "Ecto.Changeset",
    "Ecto.Migration",
    "Ecto.Query",
    "Ecto.Repo",
    "ExUnit.Assertions",
    "ExUnit.Case",
    "ExUnit.CaseTemplate",
    "GenServer",
    "Logger",
    "Mix.Project",
    "Oban.Testing",
    "Oban.Worker",
    "Phoenix.Channel",
    "Phoenix.ConnTest",
    "Phoenix.Controller",
    "Phoenix.Endpoint",
    "Phoenix.Router",
    "Phoenix.VerifiedRoutes",
    "Plug.Conn",
    "Splode.Error",
    "Supervisor",
    "Telemetry.Metrics"
  ]
  @canonical_verification_fingerprints %{
    "bin/verify" => "sha256:4895bc9e15a8389b6fadf4b2913247b5a076d4de9c36943295cda211fe143b2f",
    "bin/verify-migration-baseline" =>
      "sha256:e3e7fba601c6a331cbc7b62acc48e5b8c49ebe6c3a6b48366a5c3a332ee75bd5"
  }
  @terminal_dump_command_fingerprints MapSet.new([
                                        "sha256:0f2ffcc70cdc09bb5b0e1c696f7b9b632c4dfb6bc8925e213d3a921ab2f53a86",
                                        "sha256:4704301d94f355eeae64b6589e8b52f5668037b55e4a856dc8618d4166eff83f"
                                      ])
  @sql_payload_positions %{
    "Ecto.Adapters.SQL.execute" => nil,
    "Ecto.Adapters.SQL.query" => 1,
    "Ecto.Adapters.SQL.query!" => 1,
    "Ecto.Adapters.SQL.query_many" => 1,
    "Ecto.Adapters.SQL.query_many!" => 1,
    "Ecto.Adapters.SQL.stream" => 1,
    "Postgrex.execute" => nil,
    "Postgrex.execute!" => nil,
    "Postgrex.prepare" => 2,
    "Postgrex.prepare!" => 2,
    "Postgrex.prepare_execute" => 2,
    "Postgrex.prepare_execute!" => 2,
    "Postgrex.query" => 1,
    "Postgrex.query!" => 1,
    "Postgrex.stream" => nil
  }
  @sql_file_extensions [".pgsql", ".psql", ".sql"]
  @tracked_config_reader_paths ["config/config.exs", "config/runtime.exs"]

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
    scan_sources(tracked_sources(root),
      root: root,
      compiled_source_paths: compiled_source_path_set(root)
    )
  end

  @spec scan_sources([map()], keyword()) :: [map()]
  def scan_sources(sources, opts \\ []) do
    root = Keyword.get(opts, :root, File.cwd!())
    compiled_source_paths = Keyword.get(opts, :compiled_source_paths, MapSet.new())
    project_modules = tracked_project_modules(sources, root)

    sources
    |> Enum.flat_map(&scan_source(&1, root, compiled_source_paths, project_modules))
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

  defp scan_source(%{path: path, source: source}, root, compiled_source_paths, project_modules) do
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
        scan_elixir_source(path, source, root, compiled_source_paths, project_modules)

      true ->
        []
    end
  end

  defp scan_source(%{path: path}, root, compiled_source_paths, project_modules) do
    source = root |> Path.join(path) |> File.read!()
    scan_source(%{path: path, source: source}, root, compiled_source_paths, project_modules)
  end

  defp tracked_project_modules(sources, root) do
    Enum.reduce(sources, MapSet.new(), fn %{path: path} = source, modules ->
      if elixir_source?(path) do
        contents = Map.get_lazy(source, :source, fn -> File.read!(Path.join(root, path)) end)

        case Code.string_to_quoted(contents, file: path, columns: true) do
          {:ok, ast} -> MapSet.union(modules, defined_module_names(ast))
          {:error, _reason} -> modules
        end
      else
        modules
      end
    end)
  end

  defp defined_module_names(ast) do
    {_ast, modules} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:defmodule, _metadata, [module | _body]} = node, modules ->
          module = literal_module_name(module)
          {node, if(module, do: MapSet.put(modules, module), else: modules)}

        node, modules ->
          {node, modules}
      end)

    modules
  end

  defp literal_module_name({:__aliases__, _metadata, parts}) when is_list(parts),
    do: Enum.map_join(parts, ".", &to_string/1)

  defp literal_module_name(module) when is_atom(module),
    do: module |> Atom.to_string() |> canonical_module_name()

  defp literal_module_name(_module), do: nil

  defp scan_elixir_source(path, source, root, compiled_source_paths, project_modules) do
    case Code.string_to_quoted(source, file: path, columns: true) do
      {:ok, ast} ->
        env = %{
          aliases: %{},
          ambiguous_expansion_depth: 0,
          approved_migration_loops: approved_migration_loops(path, ast),
          compiled_source?: MapSet.member?(compiled_source_paths, path),
          function: nil,
          imports: %{},
          local_definitions: MapSet.new(),
          migration?: migration_path?(path),
          module: nil,
          path: path,
          project_modules: project_modules,
          quote_depth: 0,
          query_dsl?: false,
          repository_module?: false,
          root: root
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
    module = module_name(module, env)

    module_env = %{
      env
      | aliases: %{},
        imports: %{},
        local_definitions: local_definitions(body),
        migration?: migration_path?(env.path),
        module: module,
        repository_module?: module == "OfficeGraph.Repo"
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

    {_child_env, occurrences} =
      arguments
      |> function_default_expressions()
      |> scan_node(child_env, occurrences)

    {_child_env, occurrences} = scan_node(body, child_env, occurrences)

    if body == nil do
      scan_children(node, env, occurrences)
    else
      {_line, _metadata} = {line(metadata), metadata}
      {env, occurrences}
    end
  end

  defp scan_node({:@, metadata, [{name, _name_metadata, [value]}]} = node, env, occurrences) do
    occurrences =
      if name in @migration_callback_attributes and migration_execution_context?(env) do
        [
          occurrence(env, line(metadata), :direct_ecto, "migration.compile_callback", node,
            approval: :unresolved_sql
          )
          | occurrences
        ]
      else
        occurrences
      end

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

    occurrences =
      case dependency_macro_occurrence(:import, arguments, env) do
        nil -> occurrences
        occurrence -> [occurrence | occurrences]
      end

    {env, occurrences ++ import_occurrences}
  end

  defp scan_node({:require, _metadata, arguments}, env, occurrences) when is_list(arguments) do
    occurrences =
      case dependency_macro_occurrence(:require, arguments, env) do
        nil -> occurrences
        occurrence -> [occurrence | occurrences]
      end

    {env, occurrences}
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
    occurrences =
      case dependency_macro_occurrence(:use, [target], env) do
        nil -> occurrences
        occurrence -> [occurrence | occurrences]
      end

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
        occurrences =
          if migration_execution_context?(env) do
            [
              occurrence(env, line_from_node(node), :direct_ecto, "migration.use_macro", node,
                approval: :unresolved_sql
              )
              | occurrences
            ]
          else
            occurrences
          end

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

  defp scan_node({{:., dot_metadata, [_callback]}, metadata, arguments} = node, env, occurrences)
       when is_list(arguments) do
    occurrences =
      if migration_execution_context?(env) do
        [
          occurrence(
            env,
            line(dot_metadata) || line(metadata),
            :direct_ecto,
            "migration.helper_call",
            node,
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

    classified_occurrence = classify_remote_call(receiver, operation, arguments, node, env)

    occurrences =
      case classified_occurrence do
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

    scan_call_children(
      node,
      child_env,
      occurrences,
      is_nil(classified_occurrence) and opaque_remote_call?(receiver_name)
    )
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

    classified_occurrence = classify_local_call(operation, arguments, node, env)

    occurrences =
      case classified_occurrence do
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

    scan_call_children(
      node,
      child_env,
      occurrences,
      is_nil(classified_occurrence) and opaque_local_call?(operation)
    )
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

  defp scan_call_children(node, env, occurrences, false),
    do: scan_children(node, env, occurrences)

  defp scan_call_children(node, env, occurrences, true) do
    child_env = %{env | ambiguous_expansion_depth: env.ambiguous_expansion_depth + 1}
    {_child_env, occurrences} = scan_children(node, child_env, occurrences)
    {env, occurrences}
  end

  defp opaque_remote_call?(receiver),
    do:
      receiver not in (@database_modules ++
                         @private_persistence_modules ++
                         @process_execution_modules ++
                         @reflection_modules)

  defp opaque_local_call?(operation) do
    operation == :|> or
      (operation not in @syntax_operations and not operator?(operation))
  end

  defp classify_remote_call(receiver, :apply, [target, operation | _rest] = arguments, node, env) do
    case receiver_name(receiver, env) do
      receiver when receiver in ["Kernel", "erlang"] ->
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
        if MapSet.member?(env.local_definitions, {operation, arity}) do
          nil
        else
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

  defp classify_operation("Ecto.Adapters.Postgres", operation, _arity, node, env)
       when operation in @postgres_adapter_storage_operations do
    occurrence(
      env,
      line_from_node(node),
      :direct_ecto,
      "Ecto.Adapters.Postgres.#{operation}",
      node,
      approval: :unresolved_sql
    )
  end

  defp classify_operation("Ecto.Migrator", operation, _arity, node, env)
       when operation in @ecto_migrator_operations do
    occurrence(env, line_from_node(node), :direct_ecto, "Ecto.Migrator.#{operation}", node,
      approval: :unresolved_sql
    )
  end

  defp classify_operation(receiver, operation, _arity, node, env)
       when {receiver, operation} in @process_execution_operations do
    case process_command_status(receiver, operation, node, env) do
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

  defp classify_operation("Postgrex.Notifications", operation, _arity, node, env) do
    occurrence(
      env,
      line_from_node(node),
      :direct_ecto,
      "Postgrex.Notifications.#{operation}",
      node,
      approval: :unresolved_sql
    )
  end

  defp classify_operation("Postgrex.SimpleConnection", operation, _arity, node, env) do
    occurrence(
      env,
      line_from_node(node),
      :direct_ecto,
      "Postgrex.SimpleConnection.#{operation}",
      node,
      approval: :unresolved_sql
    )
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

  defp classify_operation(receiver, operation, arity, node, env)
       when receiver in @reflection_modules do
    if operation in Map.fetch!(@reflection_operations, receiver) and
         not trusted_reflection_call?(receiver, operation, node, env) do
      occurrence(
        env,
        line_from_node(node),
        :direct_ecto,
        "reflection.#{receiver}.#{operation}",
        node,
        approval:
          if(reviewed_runtime_compiler_fixture?(receiver, operation, arity, env),
            do: nil,
            else: :unresolved_sql
          )
      )
    end
  end

  defp classify_operation(receiver, :apply, _arity, node, env)
       when receiver in @database_modules do
    class = dynamic_dispatch_class(receiver)

    occurrence(env, line_from_node(node), class, "#{receiver}.apply", node,
      approval: :unresolved_sql
    )
  end

  defp classify_operation(receiver, operation, _arity, node, env) do
    if private_persistence_module?(receiver) do
      occurrence(
        env,
        line_from_node(node),
        :direct_ecto,
        "#{receiver}.#{operation}",
        node,
        approval: :unresolved_sql
      )
    end
  end

  defp reviewed_runtime_compiler_fixture?("Kernel.ParallelCompiler", :compile_to_path, 3, env) do
    {env.path, occurrence_function(env.function)} in @reviewed_runtime_compiler_fixtures
  end

  defp reviewed_runtime_compiler_fixture?(_receiver, _operation, _arity, _env), do: false

  defp trusted_reflection_call?("Config.Reader", operation, node, env)
       when operation in [:read!, :read_imports!] do
    node
    |> call_arguments()
    |> List.first()
    |> tracked_config_reader_path?(env)
  end

  defp trusted_reflection_call?(_receiver, _operation, _node, _env), do: false

  defp tracked_config_reader_path?(
         {{:., _dot_metadata, [path_module, :expand]}, _metadata,
          [path, {:__DIR__, _dir_metadata, context}]},
         env
       )
       when is_atom(context) or is_nil(context) do
    case {module_name(path_module, env), static_command_literal(path)} do
      {"Path", path} when is_binary(path) ->
        source_directory = env.root |> Path.join(env.path) |> Path.dirname()
        resolved_path = Path.expand(path, source_directory)

        Enum.any?(@tracked_config_reader_paths, fn tracked_path ->
          resolved_path == Path.expand(tracked_path, env.root)
        end)

      _untrusted_path ->
        false
    end
  end

  defp tracked_config_reader_path?(_path, _env), do: false

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
      {:hibernate, [target, target_operation, _arguments]} ->
        [{target, target_operation}]

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

  defp mfa_dispatch_targets("Process", :spawn, [target, target_operation, _arguments, _options]),
    do: [{target, target_operation}]

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

  defp mfa_dispatch_targets("rpc", operation, arguments)
       when operation in @mfa_rpc_operations do
    case {operation, arguments} do
      {operation, [_node, target, target_operation, _arguments | _options]}
      when operation in [:async_call, :block_call, :call, :cast] ->
        [{target, target_operation}]

      {:multicall, [target, target_operation, _arguments]} ->
        [{target, target_operation}]

      {:multicall, [first, second, third, _fourth]} ->
        [{first, second}, {second, third}]

      {:multicall, [_nodes, target, target_operation, _arguments, _timeout]} ->
        [{target, target_operation}]

      {:eval_everywhere, [target, target_operation, _arguments]} ->
        [{target, target_operation}]

      {:eval_everywhere, [_nodes, target, target_operation, _arguments]} ->
        [{target, target_operation}]

      {:parallel_eval, [calls]} ->
        parallel_eval_targets(calls)

      {:pmap, [function_spec, _extra_arguments, _list]} ->
        [mfa_function_spec_target(function_spec)]

      _other ->
        []
    end
  end

  defp mfa_dispatch_targets("erpc", operation, arguments)
       when operation in @mfa_erpc_operations do
    case {operation, arguments} do
      {operation, [_node, target, target_operation, _arguments | _options]}
      when operation in [:call, :cast, :multicall, :multicast, :send_request] ->
        [{target, target_operation}]

      {operation, [_node, function | _options]}
      when operation in [:call, :cast, :multicall, :multicast, :send_request] ->
        [{function, nil}]

      _other ->
        []
    end
  end

  defp mfa_dispatch_targets("timer", operation, [_delay, target, target_operation, _arguments])
       when operation in @mfa_scheduled_timer_operations,
       do: [{target, target_operation}]

  defp mfa_dispatch_targets("timer", :tc, [target, target_operation, _arguments]),
    do: [{target, target_operation}]

  defp mfa_dispatch_targets("timer", :tc, [_unit, target, target_operation, _arguments]),
    do: [{target, target_operation}]

  defp mfa_dispatch_targets("proc_lib", operation, arguments)
       when operation in @mfa_proc_lib_operations do
    case {operation, arguments} do
      {operation, [target, target_operation, _arguments]}
      when operation in [:hibernate, :spawn, :spawn_link, :start, :start_link, :start_monitor] ->
        [{target, target_operation}]

      {operation, [_node, target, target_operation, _arguments]}
      when operation in [:spawn, :spawn_link] ->
        [{target, target_operation}]

      {:spawn_opt, [target, target_operation, _arguments, _options]} ->
        [{target, target_operation}]

      {:spawn_opt, [_node, target, target_operation, _arguments, _options]} ->
        [{target, target_operation}]

      {operation, [target, target_operation, _arguments, _timeout]}
      when operation in [:start, :start_link, :start_monitor] ->
        [{target, target_operation}]

      {operation, [target, target_operation, _arguments, _timeout, _options]}
      when operation in [:start, :start_link, :start_monitor] ->
        [{target, target_operation}]

      _other ->
        []
    end
  end

  defp mfa_dispatch_targets(receiver, :start_child, [_supervisor, child_spec])
       when receiver in ["DynamicSupervisor", "Supervisor", "supervisor"] do
    child_spec_start_targets(child_spec)
  end

  defp mfa_dispatch_targets("Supervisor", :start_link, [children, _options]) do
    child_specs_start_targets(children)
  end

  defp mfa_dispatch_targets(_receiver, _operation, _arguments), do: []

  defp parallel_eval_targets(calls) when is_list(calls),
    do: Enum.map(calls, &mfa_call_target/1)

  defp parallel_eval_targets({:cons, _annotation, call, rest}),
    do: [mfa_call_target(call) | parallel_eval_targets(rest)]

  defp parallel_eval_targets({nil, _annotation}), do: []
  defp parallel_eval_targets(calls), do: [{calls, nil}]

  defp mfa_call_target({:{}, _metadata, [target, operation, _arguments]}),
    do: {target, operation}

  defp mfa_call_target({:tuple, _annotation, [target, operation, _arguments]}),
    do: {target, operation}

  defp mfa_call_target(call), do: {call, nil}

  defp mfa_function_spec_target({target, operation}), do: {target, operation}

  defp mfa_function_spec_target({:{}, _metadata, [target, operation]}),
    do: {target, operation}

  defp mfa_function_spec_target({:tuple, _annotation, [target, operation]}),
    do: {target, operation}

  defp mfa_function_spec_target(function_spec), do: {function_spec, nil}

  defp child_specs_start_targets(child_specs) when is_list(child_specs),
    do: Enum.flat_map(child_specs, &child_spec_start_targets/1)

  defp child_specs_start_targets({:cons, _annotation, child_spec, rest}) do
    rest_targets = child_specs_start_targets(rest)

    case child_spec_start_targets(child_spec) do
      [] -> rest_targets
      [target] -> [target | rest_targets]
    end
  end

  defp child_specs_start_targets({nil, _annotation}), do: []
  defp child_specs_start_targets(_child_specs), do: []

  defp child_spec_start_targets({:%{}, _metadata, entries}) when is_list(entries) do
    case List.keyfind(entries, :start, 0) do
      {:start, start_mfa} -> [mfa_call_target(start_mfa)]
      nil -> []
    end
  end

  defp child_spec_start_targets({:map, _annotation, fields}) when is_list(fields) do
    Enum.find_value(fields, [], fn
      {kind, _field_annotation, {:atom, _key_annotation, :start}, start_mfa}
      when kind in [:map_field_assoc, :map_field_exact] ->
        [mfa_call_target(start_mfa)]

      _field ->
        nil
    end)
  end

  defp child_spec_start_targets(
         {{:., _dot_metadata, [{:__aliases__, _alias_metadata, [:Supervisor]}, :child_spec]},
          _metadata, [child_spec, _overrides]}
       ),
       do: child_spec_start_targets(child_spec)

  defp child_spec_start_targets(
         {:call, _annotation,
          {:remote, _remote_annotation, {:atom, _module_annotation, Supervisor},
           {:atom, _operation_annotation, :child_spec}}, [child_spec, _overrides]}
       ),
       do: child_spec_start_targets(child_spec)

  defp child_spec_start_targets({module, _argument}), do: [{module, nil}]

  defp child_spec_start_targets({:tuple, _annotation, [module, _argument]}),
    do: [{module, nil}]

  defp child_spec_start_targets({:__aliases__, _metadata, parts} = module) when is_list(parts),
    do: [{module, nil}]

  defp child_spec_start_targets({:atom, _annotation, _module} = module),
    do: [{module, nil}]

  defp child_spec_start_targets(_child_spec), do: []

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

      is_nil(resolved_receiver) and is_nil(resolved_operation) ->
        occurrence(env, line_from_node(node), :raw_sql, "dynamic_dispatch.#{kind}", node,
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
    if uncompiled_elixir_source?(env) and receiver_name(receiver, env) == nil and
         not variable_receiver?(receiver) and
         not dynamic_module_receiver?(receiver, env) and
         database_operation_arity?(operation, length(call_arguments(node))) do
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

  defp uncompiled_elixir_source?(%{path: path, compiled_source?: compiled_source?}),
    do: source_extension(path) == ".exs" or not compiled_source?

  defp dependency_macro_occurrence(kind, [target | _options], env) do
    module = module_name(target, env)

    if not (kind == :use and env.migration?) and opaque_dependency_macro_module?(module, env) do
      occurrence(
        env,
        line_from_node(target),
        :direct_ecto,
        "dependency_macro.#{kind}",
        {kind, target},
        approval: :unresolved_sql
      )
    end
  end

  defp dependency_macro_occurrence(_kind, _arguments, _env), do: nil

  defp opaque_dependency_macro_module?(module, env) when is_binary(module) do
    module not in @allowed_dependency_macro_modules and
      module not in @database_modules and
      module not in @private_persistence_modules and
      module not in @process_execution_modules and
      module not in @reflection_modules and
      module not in @dynamic_dispatch_modules and
      not project_module?(module, env)
  end

  defp opaque_dependency_macro_module?(_module, _env), do: true

  defp project_module?(module, env),
    do: MapSet.member?(env.project_modules, module)

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
        module = IO.iodata_to_binary([prefix, ".", suffix])
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

    if module in @database_modules or private_persistence_module?(module) or
         module in @dynamic_dispatch_modules or
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

  defp imported_operation?("Ecto.Adapters.Postgres", operation),
    do: operation in @postgres_adapter_storage_operations

  defp imported_operation?("DBConnection", operation),
    do:
      operation in @db_connection_raw_sql_operations or
        operation in @db_connection_direct_operations

  defp imported_operation?("Postgrex", operation),
    do: operation in @postgrex_raw_sql_operations or operation in @postgrex_direct_operations

  defp imported_operation?("Postgrex.Notifications", _operation), do: true
  defp imported_operation?("Postgrex.SimpleConnection", _operation), do: true

  defp imported_operation?("Ecto.Multi", operation), do: operation in @multi_operations
  defp imported_operation?("Ecto.Migrator", operation), do: operation in @ecto_migrator_operations

  defp imported_operation?(module, operation) when module in @dynamic_dispatch_modules,
    do: operation in Map.fetch!(@dynamic_dispatch_operations, module)

  defp imported_operation?("Port", operation), do: operation == :open
  defp imported_operation?("System", operation), do: operation in [:cmd, :shell]
  defp imported_operation?("erlang", operation), do: operation == :open_port
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

  defp imported_operation?(module, _operation), do: private_persistence_module?(module)

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

      name =
        [Map.get(env.aliases, first, first) | rest] |> Enum.join(".") |> canonical_module_name()

      env.aliases |> Map.get(name, name) |> canonical_module_name()
    end
  end

  defp module_name({:__MODULE__, _metadata, _context}, env), do: env.module

  defp module_name(atom, _env) when is_atom(atom) do
    atom
    |> Atom.to_string()
    |> canonical_module_name()
  end

  defp module_name(_node, _env), do: nil

  defp canonical_module_name(module), do: String.trim_leading(module, "Elixir.")

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

  defp function_default_expressions([{:when, _metadata, [head | _guards]} | _rest]),
    do: function_default_expressions([head])

  defp function_default_expressions([{_name, _metadata, arguments} | _rest])
       when is_list(arguments) do
    Enum.flat_map(arguments, fn
      {:\\, _metadata, [_argument, default]} -> [default]
      _argument -> []
    end)
  end

  defp function_default_expressions(_arguments), do: []

  defp call_arguments({{:., _dot_metadata, [_receiver, _operation]}, _metadata, arguments}),
    do: arguments

  defp call_arguments({_operation, _metadata, arguments}) when is_list(arguments), do: arguments

  defp call_arguments({:call, _metadata, _callee, arguments}) when is_list(arguments),
    do: arguments

  defp call_arguments(_node), do: []

  defp process_command_status(receiver, operation, node, env) do
    arguments = call_arguments(node)

    if (receiver == "Port" and operation == :open) or
         (receiver == "erlang" and operation == :open_port) do
      :dynamic
    else
      process_command_status(receiver, operation, arguments, node, env)
    end
  end

  defp process_command_status(receiver, operation, arguments, node, env) do
    command_arguments =
      case {receiver, operation, arguments} do
        {"System", :cmd, [executable, args | _options]} -> [executable, args]
        {"System", :shell, [command | _options]} -> [command]
        {"os", :cmd, [command | _options]} -> [command]
        {"Mix.Shell", :cmd, [_shell, command | _options]} -> [command]
        {receiver, :cmd, [command | _options]} when receiver in @mix_shell_modules -> [command]
        _call -> []
      end

    {literals, _dynamic?} = command_literals(command_arguments)
    executable = arguments |> List.first() |> command_literals() |> elem(0) |> List.first()

    cond do
      Enum.any?(literals, &database_cli_reference?/1) ->
        :database_cli

      reviewed_process_command?(receiver, operation, node) or
        canonical_terminal_dump_command?(receiver, operation, node, env) or
          canonical_verification_command?(receiver, operation, node, env) ->
        :safe

      is_nil(executable) ->
        :dynamic

      command_dispatch_executable?(executable) ->
        :dynamic

      receiver == "os" ->
        :dynamic

      operation == :shell ->
        :dynamic

      true ->
        :dynamic
    end
  end

  defp command_literals(nodes) when is_list(nodes) do
    if Enum.all?(nodes, &is_integer/1) do
      {[List.to_string(nodes)], false}
    else
      {reversed_literals, dynamic?} =
        Enum.reduce(nodes, {[], false}, fn node, {literals, dynamic?} ->
          {node_literals, node_dynamic?} = command_literals(node)
          {Enum.reverse(node_literals, literals), dynamic? or node_dynamic?}
        end)

      {Enum.reverse(reversed_literals), dynamic?}
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
    {reversed_literals, dynamic?} =
      Enum.reduce(elements, {[], false}, fn
        {:bin_element, _element_metadata, value, _size, _type}, {literals, dynamic?} ->
          {element_literals, element_dynamic?} = command_literals(value)
          {Enum.reverse(element_literals, literals), dynamic? or element_dynamic?}

        _element, {literals, _dynamic?} ->
          {literals, true}
      end)

    {Enum.reverse(reversed_literals), dynamic?}
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

  defp reviewed_process_command?("System", :cmd, node) do
    case call_arguments(node) do
      [executable, arguments | _options] ->
        case static_command_literal(executable) do
          "git" -> reviewed_git_arguments?(arguments)
          "pg_dump" -> pg_dump_read_only_arguments?(arguments)
          "docker" -> docker_read_only_arguments?(arguments)
          _executable -> false
        end

      _arguments ->
        false
    end
  end

  defp reviewed_process_command?(_receiver, _operation, _node), do: false

  defp reviewed_git_arguments?(arguments) do
    case command_argument_nodes(arguments) do
      [operation, option] ->
        {static_argument_literal(operation), static_argument_literal(option)} in [
          {"init", "--quiet"},
          {"ls-files", "-z"}
        ]

      [operation, option, separator, _path] ->
        case {
          static_argument_literal(operation),
          static_argument_literal(option),
          static_argument_literal(separator)
        } do
          {"add", "--intent-to-add", "--"} -> true
          {"mv", "--", _source} -> true
          _arguments -> false
        end

      _arguments ->
        false
    end
  end

  defp pg_dump_read_only_arguments?(arguments) do
    argument_nodes = command_argument_nodes(arguments)

    argument_nodes == ["--version"] or
      (is_list(argument_nodes) and
         Enum.any?(argument_nodes, &(static_argument_literal(&1) == "--schema-only")))
  end

  defp canonical_verification_command?(
         "System",
         :cmd,
         node,
         %{path: "test/office_graph/project_quality_gate_test.exs", root: root}
       ) do
    case call_arguments(node) do
      [executable, arguments | _options] ->
        static_command_literal(executable) == "sh" and
          static_command_arguments(arguments) in [
            ["bin/verify"],
            ["bin/verify", "--print-environment"]
          ] and canonical_verification_sources_match?(root)

      _arguments ->
        false
    end
  end

  defp canonical_verification_command?(_receiver, _operation, _node, _env), do: false

  defp canonical_terminal_dump_command?(
         "System",
         :cmd,
         node,
         %{
           path: "test/support/office_graph/migration_conformance_support.ex",
           function: function
         }
       ) do
    occurrence_function(function) == "dump_terminal_inventory!/0" and
      MapSet.member?(@terminal_dump_command_fingerprints, sha256(printable_node(node)))
  end

  defp canonical_terminal_dump_command?(_receiver, _operation, _node, _env), do: false

  defp canonical_verification_sources_match?(root) do
    Enum.all?(@canonical_verification_fingerprints, fn {path, expected} ->
      case File.read(Path.join(root, path)) do
        {:ok, source} -> sha256(source) == expected
        {:error, _reason} -> false
      end
    end)
  end

  defp sha256(value),
    do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, value), case: :lower)

  defp docker_read_only_arguments?(arguments) do
    docker_pg_dump_arguments?(arguments) or
      static_command_arguments(arguments) in [
        ["compose", "config", "--format", "json"],
        ["ps", "--format", "{{.id}} {{.ports}}"]
      ]
  end

  defp docker_pg_dump_arguments?(arguments) do
    case command_argument_nodes(arguments) do
      [exec, env_flag, _env, _container, pg_dump | rest] ->
        static_command_literal(exec) == "exec" and
          static_command_literal(env_flag) in ["-e", "--env"] and
          static_command_literal(pg_dump) == "pg_dump" and
          Enum.any?(rest, &(static_argument_literal(&1) == "--schema-only"))

      [exec, _container, pg_dump | rest] ->
        static_command_literal(exec) == "exec" and
          static_command_literal(pg_dump) == "pg_dump" and
          Enum.any?(rest, &(static_argument_literal(&1) == "--schema-only"))

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

  defp static_command_arguments(arguments) do
    case command_argument_nodes(arguments) do
      arguments when is_list(arguments) ->
        literals = Enum.map(arguments, &static_argument_literal/1)
        if Enum.all?(literals, &is_binary/1), do: literals

      :dynamic ->
        nil
    end
  end

  defp static_argument_literal(node) do
    case command_literals(node) do
      {[literal], false} -> String.downcase(literal)
      _literal -> nil
    end
  end

  defp static_command_literal(node) do
    case command_literals(node) do
      {[literal], false} -> literal
      _literal -> nil
    end
  end

  defp command_dispatch_executable?(literal) do
    literal
    |> Path.basename()
    |> String.downcase()
    |> then(&(&1 in @command_dispatch_executables))
  end

  defp private_persistence_module?(module), do: module in @private_persistence_modules

  defp local_definitions(body), do: collect_local_definitions(body, MapSet.new())

  defp collect_local_definitions({:defmodule, _metadata, _arguments}, definitions),
    do: definitions

  defp collect_local_definitions({kind, _metadata, arguments} = node, definitions)
       when kind in [:def, :defp, :defmacro, :defmacrop] and is_list(arguments) do
    definitions =
      arguments
      |> function_signatures()
      |> Enum.reduce(definitions, &MapSet.put(&2, &1))

    node
    |> Tuple.to_list()
    |> collect_local_definitions(definitions)
  end

  defp collect_local_definitions(nodes, definitions) when is_list(nodes),
    do: Enum.reduce(nodes, definitions, &collect_local_definitions/2)

  defp collect_local_definitions(node, definitions) when is_tuple(node) do
    node
    |> Tuple.to_list()
    |> collect_local_definitions(definitions)
  end

  defp collect_local_definitions(_node, definitions), do: definitions

  defp function_signatures([{:when, _metadata, [head | _guards]} | _rest]),
    do: function_signatures([head])

  defp function_signatures([{name, _metadata, arguments} | _rest])
       when is_atom(name) and is_list(arguments) do
    for arity <- minimum_arity(arguments)..length(arguments), do: {name, arity}
  end

  defp function_signatures([{name, _metadata, context} | _rest])
       when is_atom(name) and is_atom(context),
       do: [{name, 0}]

  defp function_signatures(_arguments), do: []

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
      {:ok, nil} -> []
      {:ok, position} -> [Enum.at(arguments, position)]
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
    if env.migration? do
      option_occurrences =
        case Map.fetch(@migration_sql_option_operations, operation) do
          {:ok, {position, option_keys}} ->
            migration_sql_option_entries(
              operation,
              Enum.fetch(arguments, position),
              option_keys,
              node,
              env
            )

          :error ->
            []
        end

      option_occurrences ++ migration_index_field_occurrences(operation, arguments, node, env)
    else
      []
    end
  end

  defp migration_sql_option_entries(operation, {:ok, options}, option_keys, node, env)
       when is_list(options) do
    if Keyword.keyword?(options) do
      options
      |> sql_option_entries(option_keys)
      |> Enum.map(fn {key, value} ->
        construct = "migration.#{operation}.#{key}"
        approval = approval_marker(:raw_sql, construct, [value])

        occurrence(env, line_from_node(node), :raw_sql, construct, {operation, key, value},
          approval: approval
        )
      end)
    else
      [unresolved_migration_options(operation, options, node, env)]
    end
  end

  defp migration_sql_option_entries(operation, {:ok, options}, _option_keys, node, env),
    do: [unresolved_migration_options(operation, options, node, env)]

  defp migration_sql_option_entries(_operation, :error, _option_keys, _node, _env), do: []

  defp unresolved_migration_options(operation, options, node, env) do
    occurrence(
      env,
      line_from_node(node),
      :raw_sql,
      "migration.#{operation}.options",
      {operation, :options, options},
      approval: :unresolved_sql
    )
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
    |> Map.put(
      :compiled_match?,
      Map.get(env, :quote_depth, 0) == 0 and Map.get(env, :ambiguous_expansion_depth, 0) == 0
    )
  end

  defp occurrence(path, line, function, class, construct, node, opts) do
    function = occurrence_function(function)

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

  defp occurrence_function({function, _generated?, _line}), do: function
  defp occurrence_function(function), do: function

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
    _error in [ArgumentError, FunctionClauseError, Protocol.UndefinedError] -> inspect(node)
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
    elixir_source?(path) or sql_file?(path)
  end

  defp elixir_source?(path), do: source_extension(path) in [".ex", ".exs"]

  defp sql_file?(path) do
    basename = path |> Path.basename() |> String.downcase()

    Enum.any?(@sql_file_extensions, fn extension ->
      String.ends_with?(basename, extension) or String.contains?(basename, extension <> ".")
    end)
  end

  defp source_extension(path), do: path |> Path.extname() |> String.downcase()
  defp migration_path?(path), do: String.starts_with?(path, "priv/repo/migrations/")

  defp compiled_beam_paths(root) do
    [mix_env(), "test", "prod"]
    |> Enum.uniq()
    |> Enum.reduce({[], []}, fn env, {paths, missing_environments} ->
      environment_paths =
        root
        |> Path.join("_build/#{env}/lib/office_graph/ebin/*.beam")
        |> Path.wildcard()
        |> Enum.reject(
          &(Path.basename(&1) ==
              "Elixir.OfficeGraph.ProjectQuality.DatabaseBoundaryScanner.beam")
        )

      if environment_paths == [] do
        {paths, [env | missing_environments]}
      else
        {Enum.reverse(environment_paths, paths), missing_environments}
      end
    end)
    |> then(fn {paths, missing_environments} ->
      {Enum.reverse(paths), Enum.reverse(missing_environments)}
    end)
  end

  defp compiled_source_path_set(root) do
    {paths, _missing_environments} = compiled_beam_paths(root)

    paths
    |> Enum.map(&compiled_source(&1, root))
    |> MapSet.new()
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

    if tracked_paths && not MapSet.member?(tracked_paths, source),
      do: [],
      else: scan_beam_abstract_code(path, source, root)
  end

  defp scan_beam_abstract_code(path, source, root) do
    case :beam_lib.chunks(String.to_charlist(path), [:abstract_code]) do
      {:ok, {_module, [abstract_code: {:raw_abstract_v1, forms}]}} ->
        behaviours = compiled_behaviours(forms)
        Enum.flat_map(forms, &compiled_form_occurrences(&1, source, behaviours))

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

  defp compiled_form_occurrences(
         {:function, annotation, name, arity, _clauses} = form,
         source,
         behaviours
       ) do
    function = {"#{name}/#{arity}", :erl_anno.generated(annotation), line(annotation)}

    if generated_non_persistence_callback?(form, behaviours) do
      form
      |> compiled_node_occurrences(source, function, [])
      |> Enum.reject(&(&1.construct == "dynamic_dispatch.apply"))
      |> Enum.reverse()
    else
      form
      |> compiled_node_occurrences(source, function, [])
      |> Enum.reverse()
    end
  end

  defp compiled_form_occurrences(form, source, _behaviours) do
    form
    |> compiled_node_occurrences(source, nil, [])
    |> Enum.reverse()
  end

  defp compiled_behaviours(forms) do
    forms
    |> Enum.flat_map(fn
      {:attribute, _annotation, :behaviour, behaviour} -> [behaviour]
      _form -> []
    end)
    |> MapSet.new()
  end

  defp generated_non_persistence_callback?(
         {:function, annotation, :cast_input_array, 2, _clauses},
         behaviours
       ) do
    :erl_anno.generated(annotation) and MapSet.member?(behaviours, Ash.Type)
  end

  defp generated_non_persistence_callback?(_form, _behaviours), do: false

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
      if compiled_unresolved_receiver_operation?(receiver, operation, arguments) and
           not generated_canonical_repo_dynamic_api?(
             source,
             function,
             operation,
             length(arguments)
           ) do
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
      if generated_canonical_repo_api?(
           source,
           function,
           module,
           fun,
           length(arguments)
         ) do
        nil
      else
        classify_operation(
          module,
          fun,
          length(arguments),
          node,
          %{path: source, function: function, migration?: false}
        )
      end

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
         operation in @expression_receiver_direct_operations or
         operation in @zero_arity_variable_operations)
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

      is_nil(receiver) and is_nil(operation) ->
        [
          occurrence(
            source,
            line_from_node(node),
            function,
            :raw_sql,
            "dynamic_dispatch.#{kind}",
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

  defp generated_canonical_repo_api?(
         "lib/office_graph/repo.ex",
         {function, generated?, line},
         module,
         operation,
         arity
       ),
       do:
         canonical_repo_generated_context?(generated?, line) and
           MapSet.member?(
             @generated_canonical_repo_static_calls,
             {function, module, operation, arity}
           )

  defp generated_canonical_repo_api?(_source, _function, _module, _operation, _arity),
    do: false

  defp generated_canonical_repo_dynamic_api?(
         "lib/office_graph/repo.ex",
         {function, generated?, line},
         operation,
         arity
       ),
       do:
         canonical_repo_generated_context?(generated?, line) and
           MapSet.member?(@generated_canonical_repo_dynamic_calls, {function, operation, arity})

  defp generated_canonical_repo_dynamic_api?(_source, _function, _operation, _arity),
    do: false

  defp canonical_repo_generated_context?(true, _line), do: true
  defp canonical_repo_generated_context?(false, @canonical_repo_use_line), do: true
  defp canonical_repo_generated_context?(_generated?, _line), do: false

  defp mix_env do
    if Process.whereis(Mix.State), do: Mix.env(), else: :dev
  end
end
