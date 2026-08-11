defmodule OfficeGraph.ProjectQuality.DatabaseBoundaryScannerTest do
  use ExUnit.Case, async: false

  alias OfficeGraph.ProjectQuality.DatabaseBoundaryScanner

  test "classifies direct repository SQL through an explicit alias" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            alias OfficeGraph.Repo

            def load(id) do
              Repo.query!("SELECT * FROM examples WHERE id = $1", [id])
            end
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.path == "lib/example.ex"
    assert occurrence.function == "load/1"
    assert occurrence.line == 5
    assert String.starts_with?(occurrence.fingerprint, "sha256:")
    refute Map.has_key?(occurrence, :approval)
  end

  test "classifies imported SQL adapter calls" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            import Ecto.Adapters.SQL, only: [query: 3]

            def load do
              query(OfficeGraph.Repo, "SELECT 1", [])
            end
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Ecto.Adapters.SQL.query"
    assert occurrence.function == "load/0"
    assert occurrence.line == 5
  end

  test "classifies fragments imported from Ecto.Query" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            import Ecto.Query

            def load do
              fragment("pg_sleep(1)")
            end
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "fragment"
    assert occurrence.function == "load/0"
    assert occurrence.line == 5
  end

  test "restores grouped repo aliases and low-level operation names" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            alias OfficeGraph.{Foundation, Repo}

            def list_by(id), do: Repo.all_by(Example, id: id)
            def persist(changeset), do: Repo.insert_or_update(changeset)
            def reload_record(record), do: Repo.reload(record)
            def explain(query), do: Repo.explain(:all, query, [])
            def prepare(conn), do: Postgrex.prepare_execute(conn, "example", "SELECT 1", [])
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.function}) == [
             {:direct_ecto, "Repo.all_by", "list_by/1"},
             {:direct_ecto, "Repo.insert_or_update", "persist/1"},
             {:direct_ecto, "Repo.reload", "reload_record/1"},
             {:direct_ecto, "Repo.explain", "explain/1"},
             {:raw_sql, "Postgrex.prepare_execute", "prepare/1"}
           ]
  end

  test "resolves aliases used as module prefixes" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "test/example_test.exs",
          source: """
          defmodule ExampleTest do
            alias OfficeGraph, as: OG
            alias OG.Repo

            def load, do: Repo.query!("SELECT 1", [])
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.function == "load/0"
  end

  test "normalizes absolute Elixir module aliases" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "scripts/absolute_repo.exs",
          source: ~S|Elixir.OfficeGraph.Repo.query!("SELECT 1", [])|
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert Map.get(occurrence, :approval) == nil
  end

  test "keeps aliases in nested lexical scopes from replacing outer aliases" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "test/example_test.exs",
          source: """
          defmodule ExampleTest do
            alias OfficeGraph.Repo

            def load(enabled?) do
              if enabled? do
                alias Example.NotARepo, as: Repo
                :ok
              end

              Repo.query!("SELECT 1", [])
            end
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.function == "load/1"
  end

  test "supports atom import modes while auditing database imports" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            import Ecto.Query, only: :macros
            import Ecto.Adapters.SQL, only: :functions

            def fragment_query, do: fragment("pg_sleep(1)")
            def adapter_query, do: query(OfficeGraph.Repo, "SELECT 1", [])
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.function}) == [
             {"Ecto.Adapters.SQL.import", nil},
             {"fragment", "fragment_query/0"},
             {"Ecto.Adapters.SQL.query", "adapter_query/0"}
           ]
  end

  test "audits local query fragments when use macros provide the import" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources(
        [
          %{
            path: "lib/example.ex",
            source: """
            defmodule QueryDSL do
              defmacro __using__(_options) do
                quote do
                  import Ecto.Query
                end
              end
            end

            defmodule Example do
              use QueryDSL

              def delayed, do: fragment("pg_sleep(1)")
            end
            """
          }
        ],
        compiled_source_paths: MapSet.new(["lib/example.ex"])
      )

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "fragment"
    assert occurrence.function == "delayed/0"
  end

  test "does not classify inert strings and comments" do
    assert DatabaseBoundaryScanner.scan_sources([
             %{
               path: "lib/example.ex",
               source: """
               defmodule Example do
                 # OfficeGraph.Repo.query!("SELECT 1", [])
                 @doc ~S|execute("CREATE TABLE examples (id uuid)")|
                 def note, do: "insert into examples values (1)"
               end
               """
             }
           ]) == []
  end

  test "rejects unresolved database apply targets" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def dispatch(operation, arguments) do
              apply(OfficeGraph.Repo, operation, arguments)
            end
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "OfficeGraph.Repo.apply"
    assert occurrence.function == "dispatch/2"
    assert occurrence.approval == :unresolved_sql
  end

  test "rejects fully dynamic apply on database-shaped receivers" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "scripts/dynamic_repo.exs",
          source: """
          defmodule DynamicRepoScript do
            def dispatch(repo, operation, arguments), do: apply(repo, operation, arguments)
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "variable_receiver.apply"
    assert occurrence.function == "dispatch/3"
    assert occurrence.approval == :unresolved_sql
  end

  test "rejects fully unresolved dispatch without variable-name heuristics" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "scripts/dynamic_dispatch.exs",
          source: """
          defmodule DynamicDispatchScript do
            def apply_call(target, operation, arguments), do: apply(target, operation, arguments)
            def capture_call(target, operation), do: Function.capture(target, operation, 1)
            def spawn_call(target, operation, arguments), do: spawn(target, operation, arguments)
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.function, &1.approval}) == [
             {"dynamic_dispatch.apply", "apply_call/3", :unresolved_sql},
             {"dynamic_dispatch.capture", "capture_call/2", :unresolved_sql},
             {"dynamic_dispatch.spawn", "spawn_call/3", :unresolved_sql}
           ]
  end

  test "rejects private Ecto persistence execution namespaces" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/private_ecto_escape.ex",
          source: """
          defmodule PrivateEctoEscape do
            alias Ecto.Repo.Queryable, as: Queryable

            def load(repo, query), do: Queryable.all(repo, query, [])
            def insert(repo, schema, fields), do: Ecto.Repo.Schema.insert_all(repo, schema, fields, [])
            def execute(connection, query), do: Ecto.Adapters.Postgres.Connection.execute(connection, query, [])
            def run_migration(repo, migration), do: Ecto.Migration.Runner.run(repo, migration)
            def drop_database(config), do: Ecto.Adapters.Postgres.storage_down(config)
            def load_structure(path, config), do: Ecto.Adapters.Postgres.structure_load(path, config)
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.function}) == [
             {:direct_ecto, "Ecto.Repo.Queryable.all", "load/2"},
             {:direct_ecto, "Ecto.Repo.Schema.insert_all", "insert/3"},
             {:direct_ecto, "Ecto.Adapters.Postgres.Connection.execute", "execute/2"},
             {:direct_ecto, "Ecto.Migration.Runner.run", "run_migration/2"},
             {:direct_ecto, "Ecto.Adapters.Postgres.storage_down", "drop_database/1"},
             {:direct_ecto, "Ecto.Adapters.Postgres.structure_load", "load_structure/2"}
           ]

    assert Enum.all?(occurrences, &(&1.approval == :unresolved_sql))
  end

  test "rejects process ports and dynamic arguments to unknown command wrappers" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "scripts/process_escape.exs",
          source: """
          defmodule ProcessEscapeScript do
            def busybox(command), do: System.cmd("busybox", ["sh", "-c", command])
            def dash, do: System.cmd("dash", ["/tmp/run-db.sh"])
            def fish, do: System.cmd("fish", ["/tmp/run-db.fish"])
            def wrapper, do: System.cmd("/tmp/run-db", [])
            def port(command), do: Port.open({:spawn, command}, [])
            def erlang_port(command), do: :erlang.open_port({:spawn, command}, [])
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.function, &1.approval}) == [
             {"process.dynamic_command", "busybox/1", :unresolved_sql},
             {"process.dynamic_command", "dash/0", :unresolved_sql},
             {"process.dynamic_command", "fish/0", :unresolved_sql},
             {"process.dynamic_command", "wrapper/0", :unresolved_sql},
             {"process.dynamic_command", "port/1", :unresolved_sql},
             {"process.dynamic_command", "erlang_port/1", :unresolved_sql}
           ]
  end

  test "does not classify an unrelated local fragment function" do
    assert DatabaseBoundaryScanner.scan_sources([
             %{
               path: "lib/text_formatter.ex",
               source: """
               defmodule TextFormatter do
                 def fragment(value \\\\ :empty), do: {:text, value}
                 def format, do: fragment()
                 def format(value), do: fragment(value)
               end
               """
             }
           ]) == []
  end

  test "rejects module-function-argument process dispatch to database operations" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "scripts/spawned_repo.exs",
          source: """
          defmodule SpawnedRepoScript do
            import Process, only: [spawn: 4]

            def local(sql), do: spawn(OfficeGraph.Repo, :query!, [sql, []])
            def linked(sql), do: Kernel.spawn_link(OfficeGraph.Repo, :query!, [sql, []])
            def process(sql), do: Process.spawn(OfficeGraph.Repo, :query!, [sql, []], [])
            def imported(sql), do: spawn(OfficeGraph.Repo, :query!, [sql, []], [])
            def tasked(sql), do: Task.start(OfficeGraph.Repo, :query!, [sql, []])

            def supervised(supervisor, sql),
              do: Task.Supervisor.start_child(supervisor, OfficeGraph.Repo, :query!, [sql, []])
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.function, &1.approval}) == [
             {"OfficeGraph.Repo.spawn", "local/1", :unresolved_sql},
             {"OfficeGraph.Repo.spawn_link", "linked/1", :unresolved_sql},
             {"OfficeGraph.Repo.spawn", "process/1", :unresolved_sql},
             {"OfficeGraph.Repo.spawn", "imported/1", :unresolved_sql},
             {"OfficeGraph.Repo.start", "tasked/1", :unresolved_sql},
             {"OfficeGraph.Repo.start_child", "supervised/2", :unresolved_sql}
           ]
  end

  test "rejects RPC module-function-argument dispatch to database operations" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "scripts/rpc_repo.exs",
          source: """
          defmodule RpcRepoScript do
            def call(sql), do: :rpc.call(node(), OfficeGraph.Repo, :query!, [sql, []])
            def async_call(sql), do: :rpc.async_call(node(), OfficeGraph.Repo, :query!, [sql, []])
            def cast(sql), do: :erpc.cast(node(), OfficeGraph.Repo, :query!, [sql, []])
            def multicall(nodes, sql), do: :erpc.multicall(nodes, OfficeGraph.Repo, :query!, [sql, []])
            def multicast(nodes, sql), do: :erpc.multicast(nodes, OfficeGraph.Repo, :query!, [sql, []])
            def request(sql), do: :erpc.send_request(node(), OfficeGraph.Repo, :query!, [sql, []])
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.function, &1.approval}) == [
             {"OfficeGraph.Repo.call", "call/1", :unresolved_sql},
             {"OfficeGraph.Repo.async_call", "async_call/1", :unresolved_sql},
             {"OfficeGraph.Repo.cast", "cast/1", :unresolved_sql},
             {"OfficeGraph.Repo.multicall", "multicall/2", :unresolved_sql},
             {"OfficeGraph.Repo.multicast", "multicast/2", :unresolved_sql},
             {"OfficeGraph.Repo.send_request", "request/1", :unresolved_sql}
           ]
  end

  test "rejects every supported RPC evaluator form that can execute a database MFA" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "scripts/rpc_evaluators.exs",
          source: """
          defmodule RpcEvaluatorScript do
            def everywhere(sql), do: :rpc.eval_everywhere(OfficeGraph.Repo, :query!, [sql, []])
            def everywhere_on(nodes, sql), do: :rpc.eval_everywhere(nodes, OfficeGraph.Repo, :query!, [sql, []])
            def parallel(sql), do: :rpc.parallel_eval([{OfficeGraph.Repo, :query!, [sql, []]}])
            def mapped(sql), do: :rpc.pmap({OfficeGraph.Repo, :query!}, [[]], [sql])
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.function, &1.approval}) == [
             {"OfficeGraph.Repo.eval_everywhere", "everywhere/1", :unresolved_sql},
             {"OfficeGraph.Repo.eval_everywhere", "everywhere_on/2", :unresolved_sql},
             {"OfficeGraph.Repo.parallel_eval", "parallel/1", :unresolved_sql},
             {"OfficeGraph.Repo.pmap", "mapped/1", :unresolved_sql}
           ]
  end

  test "rejects timer module-function-argument dispatch to database operations" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "scripts/timer_repo.exs",
          source: """
          defmodule TimerRepoScript do
            def once(sql), do: :timer.apply_after(1, OfficeGraph.Repo, :query!, [sql, []])
            def interval(sql), do: :timer.apply_interval(1, OfficeGraph.Repo, :query!, [sql, []])
            def repeated(sql), do: :timer.apply_repeatedly(1, OfficeGraph.Repo, :query!, [sql, []])
            def timed(sql), do: :timer.tc(OfficeGraph.Repo, :query!, [sql, []])
            def timed_in(unit, sql), do: :timer.tc(unit, OfficeGraph.Repo, :query!, [sql, []])
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.function, &1.approval}) == [
             {"OfficeGraph.Repo.apply_after", "once/1", :unresolved_sql},
             {"OfficeGraph.Repo.apply_interval", "interval/1", :unresolved_sql},
             {"OfficeGraph.Repo.apply_repeatedly", "repeated/1", :unresolved_sql},
             {"OfficeGraph.Repo.tc", "timed/1", :unresolved_sql},
             {"OfficeGraph.Repo.tc", "timed_in/2", :unresolved_sql}
           ]
  end

  test "rejects proc_lib module-function-argument dispatch to database operations" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "scripts/proc_lib_repo.exs",
          source: """
          defmodule ProcLibRepoScript do
            def spawn(sql), do: :proc_lib.spawn(OfficeGraph.Repo, :query!, [sql, []])
            def spawn_on(node, sql), do: :proc_lib.spawn(node, OfficeGraph.Repo, :query!, [sql, []])
            def linked(sql), do: :proc_lib.spawn_link(OfficeGraph.Repo, :query!, [sql, []])
            def optimized(sql), do: :proc_lib.spawn_opt(OfficeGraph.Repo, :query!, [sql, []], [])
            def start(sql), do: :proc_lib.start(OfficeGraph.Repo, :query!, [sql, []])
            def start_link(sql), do: :proc_lib.start_link(OfficeGraph.Repo, :query!, [sql, []])
            def start_monitor(sql), do: :proc_lib.start_monitor(OfficeGraph.Repo, :query!, [sql, []])
            def hibernate(sql), do: :proc_lib.hibernate(OfficeGraph.Repo, :query!, [sql, []])
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.function, &1.approval}) == [
             {"OfficeGraph.Repo.spawn", "spawn/1", :unresolved_sql},
             {"OfficeGraph.Repo.spawn", "spawn_on/2", :unresolved_sql},
             {"OfficeGraph.Repo.spawn_link", "linked/1", :unresolved_sql},
             {"OfficeGraph.Repo.spawn_opt", "optimized/1", :unresolved_sql},
             {"OfficeGraph.Repo.start", "start/1", :unresolved_sql},
             {"OfficeGraph.Repo.start_link", "start_link/1", :unresolved_sql},
             {"OfficeGraph.Repo.start_monitor", "start_monitor/1", :unresolved_sql},
             {"OfficeGraph.Repo.hibernate", "hibernate/1", :unresolved_sql}
           ]
  end

  test "rejects erlang hibernate module-function-argument dispatch to database operations" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "scripts/hibernate_repo.exs",
          source: """
          defmodule HibernateRepoScript do
            def hibernate(sql), do: :erlang.hibernate(OfficeGraph.Repo, :query!, [sql, []])
          end
          """
        }
      ])

    assert {occurrence.construct, occurrence.function, occurrence.approval} ==
             {"OfficeGraph.Repo.hibernate", "hibernate/1", :unresolved_sql}
  end

  test "rejects opaque runtime execution namespaces and supervisor start MFAs" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "scripts/runtime_execution.exs",
          source: """
          defmodule RuntimeExecutionScript do
            def evaluate(forms), do: :erl_eval.exprs(forms, [])
            def connect(options), do: Postgrex.SimpleConnection.start_link(__MODULE__, [], options)
            def mix_eval(code), do: System.cmd("mix", ["run", "-e", code])

            def supervised(supervisor, sql) do
              Supervisor.start_child(supervisor, %{
                id: :query,
                start: {OfficeGraph.Repo, :query!, [sql, []]}
              })
            end

            def dynamic_supervised(supervisor, sql) do
              DynamicSupervisor.start_child(supervisor, %{
                id: :query,
                start: {OfficeGraph.Repo, :query!, [sql, []]}
              })
            end

            def otp_supervised(supervisor, sql) do
              :supervisor.start_child(supervisor, %{
                id: :query,
                start: {OfficeGraph.Repo, :query!, [sql, []]}
              })
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.function, &1.approval}) == [
             {:direct_ecto, "reflection.erl_eval.exprs", "evaluate/1", :unresolved_sql},
             {:direct_ecto, "Postgrex.SimpleConnection.start_link", "connect/1", :unresolved_sql},
             {:raw_sql, "process.dynamic_command", "mix_eval/1", :unresolved_sql},
             {:raw_sql, "OfficeGraph.Repo.start_child", "supervised/2", :unresolved_sql},
             {:raw_sql, "OfficeGraph.Repo.start_child", "dynamic_supervised/2", :unresolved_sql},
             {:raw_sql, "OfficeGraph.Repo.start_child", "otp_supervised/2", :unresolved_sql}
           ]
  end

  test "rejects opaque dependency macro capabilities in uncompiled sources" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "scripts/dependency_macros.exs",
          source: """
          defmodule DependencyMacroScript do
            require Dependency.QueryMacros
            import Dependency.CommandMacros
            use Dependency.PersistenceDSL

            require Ash.Query
            import Config
            use ExUnit.Case
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.line, &1.approval}) == [
             {"dependency_macro.require", 2, :unresolved_sql},
             {"dependency_macro.import", 3, :unresolved_sql},
             {"dependency_macro.use", 4, :unresolved_sql}
           ]
  end

  test "rejects opaque dependency macros in .ex sources without compiled evidence" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources(
        [
          %{
            path: "scripts/dependency_macros.ex",
            source: "require Dependency.QueryMacros"
          }
        ],
        compiled_source_paths: MapSet.new()
      )

    assert {occurrence.construct, occurrence.line, occurrence.approval} ==
             {"dependency_macro.require", 1, :unresolved_sql}
  end

  test "rejects function captures that target database dispatch" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "scripts/captured_repo.exs",
          source: """
          defmodule CapturedRepoScript do
            import Function, only: [capture: 3]

            def direct, do: Function.capture(OfficeGraph.Repo, :query!, 2)
            def dynamic(repo, operation), do: Function.capture(repo, operation, 2)
            def imported, do: capture(OfficeGraph.Repo, :query!, 2)
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.function, &1.approval}) == [
             {:raw_sql, "OfficeGraph.Repo.capture", "direct/0", :unresolved_sql},
             {:raw_sql, "variable_receiver.capture", "dynamic/2", :unresolved_sql},
             {:raw_sql, "OfficeGraph.Repo.capture", "imported/0", :unresolved_sql}
           ]
  end

  test "rejects database defdelegates in uncompiled sources" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "scripts/delegated_repo.exs",
          source: """
          defmodule DelegatedRepoScript do
            defdelegate query!(sql, params), to: OfficeGraph.Repo
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.function == nil
    assert occurrence.approval == :unresolved_sql
  end

  test "rejects dynamic dispatch even when the receiver variable is not database-shaped" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def kernel_dispatch(sql), do: Kernel.apply(OfficeGraph.Repo, :query, [sql])
            def local_dispatch(target, sql), do: apply(target, :query, [sql])
            def remote_dispatch(target, sql), do: target.query(sql)
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.function, &1.approval}) == [
             {"OfficeGraph.Repo.apply", "kernel_dispatch/1", :unresolved_sql},
             {"variable_receiver.apply", "local_dispatch/2", :unresolved_sql},
             {"variable_receiver.query", "remote_dispatch/2", :unresolved_sql}
           ]
  end

  test "rejects database-shaped variable receivers" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load(repo) do
              repo.query!("SELECT 1", [])
            end
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "variable_receiver.query!"
    assert occurrence.function == "load/1"
    assert occurrence.approval == :unresolved_sql
  end

  test "rejects direct operations on generic variable receivers in source" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "scripts/persist.exs",
          source: """
          defmodule PersistScript do
            def persist(target, changeset), do: target.insert(changeset)
          end
          """
        }
      ])

    assert occurrence.class == :direct_ecto
    assert occurrence.construct == "variable_receiver.insert"
    assert occurrence.function == "persist/2"
    assert occurrence.approval == :unresolved_sql
  end

  test "audits unqualified repository calls authored inside a Repo module" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources(
        [
          %{
            path: "lib/office_graph/repo.ex",
            source: """
            defmodule OfficeGraph.Repo do
              use AshPostgres.Repo, otp_app: :office_graph

              def unsafe(sql), do: query!(sql, [])
            end
            """
          }
        ],
        compiled_source_paths: MapSet.new(["lib/office_graph/repo.ex"])
      )

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.function, &1.approval}) == [
             {:raw_sql, "Repo.query!", "unsafe/1", :unresolved_sql}
           ]
  end

  test "rejects additional Ecto.Repo modules and audits their authored calls" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources(
        [
          %{
            path: "lib/secondary_repo.ex",
            source: """
            defmodule SecondaryRepo do
              use Ecto.Repo, otp_app: :office_graph, adapter: Ecto.Adapters.Postgres

              def unsafe(sql), do: query!(sql, [])
            end
            """
          }
        ],
        compiled_source_paths: MapSet.new(["lib/secondary_repo.ex"])
      )

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.function, &1.approval}) == [
             {:direct_ecto, "Ecto.Repo.use", nil, :unresolved_sql},
             {:raw_sql, "Repo.query!", "unsafe/1", :unresolved_sql}
           ]
  end

  test "rejects database operations on expression receivers" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "scripts/expression_repo.exs",
          source: """
          lookup_repo().query!(sql, [])
          """
        },
        %{
          path: "scripts/expression_repo.EXS",
          source: """
          lookup_repo().query!(sql, [])
          lookup_repo().checked_out?()
          lookup_repo().get_dynamic_repo()
          lookup_repo().in_transaction?()
          lookup_repo().stop()
          """
        },
        %{
          path: "priv/repo/migrations/20260801000000_expression_repo.exs",
          source: """
          defmodule ExpressionRepoMigration do
            use Ecto.Migration

            def up do
              Ecto.Migration.repo().insert(%{id: "1"})
            end
          end
          """
        }
      ])

    assert Enum.map(
             occurrences,
             &{&1.class, &1.construct, &1.function, Map.get(&1, :approval)}
           ) == [
             {:raw_sql, "expression_receiver.query!", nil, :unresolved_sql},
             {:raw_sql, "expression_receiver.query!", nil, :unresolved_sql},
             {:direct_ecto, "expression_receiver.checked_out?", nil, :unresolved_sql},
             {:direct_ecto, "expression_receiver.get_dynamic_repo", nil, :unresolved_sql},
             {:direct_ecto, "expression_receiver.in_transaction?", nil, :unresolved_sql},
             {:direct_ecto, "expression_receiver.stop", nil, :unresolved_sql},
             {:direct_ecto, "Repo.insert", "up/0", nil}
           ]
  end

  test "rejects runtime source evaluation as an unresolved reflection boundary" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "scripts/evaluate.exs",
          source: """
          alias Code, as: RuntimeCode

          RuntimeCode.eval_string(source)
          """
        }
      ])

    assert occurrence.class == :direct_ecto
    assert occurrence.construct == "reflection.Code.eval_string"
    assert occurrence.approval == :unresolved_sql
  end

  test "rejects EEx runtime evaluation as an unresolved reflection boundary" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "scripts/evaluate_template.exs",
          source: """
          defmodule TemplateEvaluator do
            def string(template), do: EEx.eval_string(template, assigns: [])
            def file(path), do: EEx.eval_file(path, assigns: [])
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.function, &1.approval}) == [
             {"reflection.EEx.eval_string", "string/1", :unresolved_sql},
             {"reflection.EEx.eval_file", "file/1", :unresolved_sql}
           ]
  end

  test "rejects environment-returning quoted evaluation and runtime parallel compilation" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "scripts/runtime_compilation.exs",
          source: """
          defmodule RuntimeCompilation do
            def evaluate(quoted, env), do: Code.eval_quoted_with_env(quoted, [], env)
            def compile(files), do: Kernel.ParallelCompiler.compile(files)
            def compile_to_path(files, path), do: Kernel.ParallelCompiler.compile_to_path(files, path)
            def files(files), do: Kernel.ParallelCompiler.files(files)
            def files_to_path(files, path), do: Kernel.ParallelCompiler.files_to_path(files, path)
            def require(files), do: Kernel.ParallelCompiler.require(files)
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.function, &1.approval}) == [
             {"reflection.Code.eval_quoted_with_env", "evaluate/2", :unresolved_sql},
             {"reflection.Kernel.ParallelCompiler.compile", "compile/1", :unresolved_sql},
             {"reflection.Kernel.ParallelCompiler.compile_to_path", "compile_to_path/2",
              :unresolved_sql},
             {"reflection.Kernel.ParallelCompiler.files", "files/1", :unresolved_sql},
             {"reflection.Kernel.ParallelCompiler.files_to_path", "files_to_path/2",
              :unresolved_sql},
             {"reflection.Kernel.ParallelCompiler.require", "require/1", :unresolved_sql}
           ]
  end

  test "rejects file-based runtime code loading as an unresolved reflection boundary" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "scripts/load_runtime_code.exs",
          source: """
          defmodule RuntimeCodeLoader do
            alias Code, as: RuntimeCode
            import Code, only: [compile_file: 1]

            def evaluate(path), do: RuntimeCode.eval_file(path)
            def require_runtime(path), do: Code.require_file(path)
            def compile_runtime(path), do: compile_file(path)
            def load_binary(module, path, beam), do: :code.load_binary(module, path, beam)
            def load_file(module), do: :code.load_file(module)
            def eval_terms(path), do: :file.eval(path)
            def eval_terms(path, bindings), do: :file.eval(path, bindings)
            def script(path), do: :file.script(path)
            def script(path, bindings), do: :file.script(path, bindings)
            def path_eval(path, name), do: :file.path_eval(path, name)
            def path_eval(path, name, bindings), do: :file.path_eval(path, name, bindings)
            def path_script(path, name), do: :file.path_script(path, name)
            def path_script(path, name, bindings), do: :file.path_script(path, name, bindings)
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.function, &1.approval}) == [
             {"reflection.Code.eval_file", "evaluate/1", :unresolved_sql},
             {"reflection.Code.require_file", "require_runtime/1", :unresolved_sql},
             {"reflection.Code.compile_file", "compile_runtime/1", :unresolved_sql},
             {"reflection.code.load_binary", "load_binary/3", :unresolved_sql},
             {"reflection.code.load_file", "load_file/1", :unresolved_sql},
             {"reflection.file.eval", "eval_terms/1", :unresolved_sql},
             {"reflection.file.eval", "eval_terms/2", :unresolved_sql},
             {"reflection.file.script", "script/1", :unresolved_sql},
             {"reflection.file.script", "script/2", :unresolved_sql},
             {"reflection.file.path_eval", "path_eval/2", :unresolved_sql},
             {"reflection.file.path_eval", "path_eval/3", :unresolved_sql},
             {"reflection.file.path_script", "path_script/2", :unresolved_sql},
             {"reflection.file.path_script", "path_script/3", :unresolved_sql}
           ]
  end

  test "rejects file loading even when the target source is independently scanned" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "test/test_helper.exs",
          source: ~S|Code.require_file("credo_checks/project_boundary.ex")|
        },
        %{
          path: "credo_checks/project_boundary.ex",
          source: "defmodule ProjectBoundary do\nend"
        }
      ])

    assert occurrence.construct == "reflection.Code.require_file"
    assert occurrence.approval == :unresolved_sql
  end

  test "rejects aliased dynamic module receivers" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "scripts/dynamic_repo.exs",
          source: """
          alias Module, as: M

          M.concat([OfficeGraph, Repo]).query!(sql, [])
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "dynamic_receiver"
    assert occurrence.approval == :unresolved_sql
  end

  test "tracks use Ecto.Migration outside the migration directory" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "test/support/runtime_migration.exs",
          source: """
          defmodule RuntimeMigration do
            use Ecto.Migration

            def change do
              execute("SELECT 1")
            end
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "migration.execute"
    assert occurrence.function == "change/0"
    refute Map.has_key?(occurrence, :approval)
  end

  test "allows the declarative migration timestamps helper" do
    assert DatabaseBoundaryScanner.scan_sources([
             %{
               path: "priv/repo/migrations/20260801000000_timestamps.exs",
               source: """
               defmodule TimestampsMigration do
                 use Ecto.Migration

                 def change do
                   create table(:examples) do
                     timestamps()
                   end
                 end
               end
               """
             }
           ]) == []
  end

  test "selects static SQL payloads from adapter-specific argument positions" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def adapter_query, do: Ecto.Adapters.SQL.query(OfficeGraph.Repo, "SELECT 1", [])
            def postgrex_query(conn), do: Postgrex.query(conn, "SELECT 2", [])
            def postgrex_prepare(conn), do: Postgrex.prepare(conn, "example", "SELECT 3")
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, Map.get(&1, :approval)}) == [
             {"Ecto.Adapters.SQL.query", nil},
             {"Postgrex.query", nil},
             {"Postgrex.prepare", nil}
           ]
  end

  test "rejects complex migration control flow except the preserved UUIDv7 loop" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "priv/repo/migrations/20260801000000_dynamic_migration.exs",
          source: """
          defmodule DynamicMigration do
            use Ecto.Migration

            def change do
              if System.get_env("CREATE_EXAMPLES") do
                create table(:examples)
              end
            end
          end
          """
        }
      ])
      |> Enum.filter(&(&1.construct == "migration.control_flow"))

    assert occurrence.class == :direct_ecto
    assert occurrence.construct == "migration.control_flow"
    assert occurrence.approval == :unresolved_sql
  end

  test "rejects guarded migration callbacks as control flow and audits their bodies" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "priv/repo/migrations/20260801000000_guarded_callback.exs",
          source: """
          defmodule GuardedCallback do
            use Ecto.Migration

            def up() when @enabled, do: MigrationHelpers.install()
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.function, &1.approval}) == [
             {"migration.control_flow", "up/0", :unresolved_sql},
             {"migration.remote_helper_call", "up/0", :unresolved_sql}
           ]
  end

  test "recognizes zero-arity migration callbacks generated by default arguments" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "priv/repo/migrations/20260801000000_defaulted_callback.exs",
          source: """
          defmodule DefaultedCallback do
            use Ecto.Migration

            def up(options \\\\ []) do
              MigrationHelpers.install(options)
            end
          end
          """
        }
      ])

    assert occurrence.class == :direct_ecto
    assert occurrence.construct == "migration.remote_helper_call"
    assert occurrence.function == "up/0"
    assert occurrence.approval == :unresolved_sql
  end

  test "scans database calls in migration default expressions" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "priv/repo/migrations/20260801000000_default_expression.exs",
          source: """
          defmodule DefaultExpressionMigration do
            use Ecto.Migration

            def up(value \\\\ OfficeGraph.Repo.query!("SELECT 1", [])), do: value
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.function == "up/0"
  end

  test "rejects dependency use macros in migration modules" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "priv/repo/migrations/20260801000000_use_macro.exs",
          source: """
          defmodule UseMacroMigration do
            use Ecto.Migration
            use ExternalInstaller

            def change, do: create(table(:items))
          end
          """
        }
      ])

    assert occurrence.class == :direct_ecto
    assert occurrence.construct == "migration.use_macro"
    assert occurrence.function == nil
    assert occurrence.approval == :unresolved_sql
  end

  test "rejects migration compile and load callbacks" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "priv/repo/migrations/20260801000000_compile_callbacks.exs",
          source: """
          defmodule CompileCallbackMigration do
            use Ecto.Migration

            @before_compile ExternalInstaller
            @after_compile ExternalInstaller
            @after_verify {ExternalInstaller, :run}
            @on_definition ExternalInstaller
            @on_load :install

            def change, do: create(table(:items))
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.function, &1.approval}) == [
             {"migration.compile_callback", nil, :unresolved_sql},
             {"migration.compile_callback", nil, :unresolved_sql},
             {"migration.compile_callback", nil, :unresolved_sql},
             {"migration.compile_callback", nil, :unresolved_sql},
             {"migration.compile_callback", nil, :unresolved_sql}
           ]
  end

  test "treats migration transaction hooks as persistence-sensitive entrypoints" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "priv/repo/migrations/20260801000000_transaction_hooks.exs",
          source: """
          defmodule TransactionHooks do
            use Ecto.Migration

            @install_more true

            def after_begin, do: Oban.Migrations.up()

            def before_commit do
              if @install_more do
                MigrationHelpers.install_more()
              end
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.function, &1.approval}) == [
             {"migration.remote_helper_call", "after_begin/0", :unresolved_sql},
             {"migration.control_flow", "before_commit/0", :unresolved_sql},
             {"migration.remote_helper_call", "before_commit/0", :unresolved_sql}
           ]
  end

  test "audits DBConnection execution and connection-control primitives" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/db_connection_boundary.ex",
          source: """
          defmodule DBConnectionBoundary do
            def execute(conn, query), do: DBConnection.prepare_execute(conn, query, [])
            def transact(conn, fun), do: DBConnection.transaction(conn, fun)
          end
          """
        }
      ])

    assert Enum.map(
             occurrences,
             &{&1.class, &1.construct, &1.function, Map.get(&1, :approval)}
           ) == [
             {:raw_sql, "DBConnection.prepare_execute", "execute/2", :unresolved_sql},
             {:direct_ecto, "DBConnection.transaction", "transact/2", nil}
           ]
  end

  test "audits Postgrex transaction and connection-control primitives" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/postgrex_boundary.ex",
          source: """
          defmodule PostgrexBoundary do
            def start(options), do: Postgrex.start_link(options)
            def transact(conn, fun), do: Postgrex.transaction(conn, fun)
            def rollback(conn, reason), do: Postgrex.rollback(conn, reason)
            def parameters(conn), do: Postgrex.parameters(conn)
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.function}) == [
             {:direct_ecto, "Postgrex.start_link", "start/1"},
             {:direct_ecto, "Postgrex.transaction", "transact/2"},
             {:direct_ecto, "Postgrex.rollback", "rollback/2"},
             {:direct_ecto, "Postgrex.parameters", "parameters/1"}
           ]
  end

  test "audits Postgrex notification connections and subscriptions" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/postgrex_notifications_boundary.ex",
          source: """
          defmodule PostgrexNotificationsBoundary do
            def start(options), do: Postgrex.Notifications.start_link(options)
            def listen(pid, channel), do: Postgrex.Notifications.listen(pid, channel)
            def unlisten(pid, ref), do: Postgrex.Notifications.unlisten(pid, ref)
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.function, &1.approval}) == [
             {:direct_ecto, "Postgrex.Notifications.start_link", "start/1", :unresolved_sql},
             {:direct_ecto, "Postgrex.Notifications.listen", "listen/2", :unresolved_sql},
             {:direct_ecto, "Postgrex.Notifications.unlisten", "unlisten/2", :unresolved_sql}
           ]
  end

  test "audits zero-arity repository controls on database-shaped variables" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/repository_controls.ex",
          source: """
          defmodule RepositoryControls do
            def current(repo), do: repo.get_dynamic_repo()
            def stop(repo), do: repo.stop()
            def stop_worker(worker), do: worker.stop()
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.function}) == [
             {:direct_ecto, "variable_receiver.get_dynamic_repo", "current/1"},
             {:direct_ecto, "variable_receiver.stop", "stop/1"}
           ]
  end

  test "audits adapter and repository connection-control operations" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/dynamic_repo_boundary.ex",
          source: """
          defmodule DynamicRepoBoundary do
            def select(repo), do: OfficeGraph.Repo.put_dynamic_repo(repo)
            def current, do: OfficeGraph.Repo.get_dynamic_repo()
            def disconnect, do: OfficeGraph.Repo.disconnect_all(1_000)
            def disconnect_adapter, do: Ecto.Adapters.SQL.disconnect_all(OfficeGraph.Repo, 1_000)
            def start(options), do: OfficeGraph.Repo.start_link(options)
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.function}) == [
             {:direct_ecto, "Repo.put_dynamic_repo", "select/1"},
             {:direct_ecto, "Repo.get_dynamic_repo", "current/0"},
             {:direct_ecto, "Repo.disconnect_all", "disconnect/0"},
             {:direct_ecto, "Ecto.Adapters.SQL.disconnect_all", "disconnect_adapter/0"},
             {:direct_ecto, "Repo.start_link", "start/1"}
           ]
  end

  test "rejects SQL-bearing migration options" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "priv/repo/migrations/20260801000000_sql_options.exs",
          source: """
          defmodule SqlOptions do
            use Ecto.Migration

            def change do
              create constraint(:items, :positive_amount, check: "amount > 0")
              create index(:items, [:deleted_at], where: "deleted_at IS NULL")
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.function}) == [
             {:raw_sql, "migration.constraint.check", "change/0"},
             {:raw_sql, "migration.index.where", "change/0"}
           ]
  end

  test "rejects nonliteral migration SQL option containers" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "priv/repo/migrations/20260801000000_indirect_sql_options.exs",
          source: """
          defmodule IndirectSqlOptions do
            use Ecto.Migration

            @index_options [where: "deleted_at IS NULL"]

            def change do
              create index(:items, [:deleted_at], @index_options)
            end
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "migration.index.options"
    assert occurrence.function == "change/0"
    assert occurrence.approval == :unresolved_sql
  end

  test "rejects a reversible migration when either SQL payload is dynamic" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "priv/repo/migrations/20260801000000_dynamic_rollback.exs",
          source: """
          defmodule DynamicRollback do
            use Ecto.Migration

            def change do
              execute("CREATE TABLE examples (id uuid)", @rollback_sql)
            end
          end
          """
        }
      ])

    assert occurrence.construct == "migration.execute"
    assert occurrence.approval == :unresolved_sql
  end

  test "rejects SQL fragments and lock clauses inside Ecto query DSL calls" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            import Ecto.Query, only: [from: 2]

            def load do
              from row in "rows",
                where: fragment("lower(?)", row.name),
                hints: ["TABLESAMPLE SYSTEM_ROWS(10)"],
                lock: "FOR UPDATE"
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.function}) == [
             {:raw_sql, "query.from.hints", "load/0"},
             {:raw_sql, "query.from.lock", "load/0"},
             {:raw_sql, "fragment", "load/0"}
           ]
  end

  test "rejects qualified migration primitives and SQL-bearing options" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "priv/repo/migrations/20260801000000_qualified_primitives.exs",
          source: """
          defmodule QualifiedPrimitives do
            use Ecto.Migration

            def change do
              Ecto.Migration.fragment("now()")
              Ecto.Migration.insert(%{id: "1"})
              create Ecto.Migration.index(:items, [:name], where: "name IS NOT NULL")
              create Ecto.Migration.index(:items, ["lower(name)"])
              create Ecto.Migration.table(:items, options: "fillfactor=70")
              alter Ecto.Migration.table(:items) do
                Ecto.Migration.add(:slug, :text, generated: "lower(name)")
              end
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.function}) == [
             {:raw_sql, "Ecto.Migration.fragment", "change/0"},
             {:direct_ecto, "Ecto.Migration.insert", "change/0"},
             {:raw_sql, "migration.index.where", "change/0"},
             {:raw_sql, "migration.index.fields", "change/0"},
             {:raw_sql, "migration.table.options", "change/0"},
             {:raw_sql, "migration.add.generated", "change/0"}
           ]
  end

  test "keeps qualified and aliased execute_file calls unresolved" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "priv/repo/migrations/20260801000000_external_sql.exs",
          source: """
          defmodule ExternalSql do
            use Ecto.Migration
            alias Ecto.Migration, as: Migration

            def up do
              Ecto.Migration.execute_file("priv/repo/install.sql")
              Migration.execute_file("priv/repo/upgrade.sql")
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.approval}) == [
             {"Ecto.Migration.execute_file", :unresolved_sql},
             {"Ecto.Migration.execute_file", :unresolved_sql}
           ]
  end

  test "rejects short-circuit migration branches" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "priv/repo/migrations/20260801000000_short_circuit.exs",
          source: """
          defmodule ShortCircuit do
            use Ecto.Migration
            @enabled System.get_env("ENABLE_TABLE")

            def up do
              @enabled && create(table(:conditional))
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.function, &1.approval}) == [
             {:direct_ecto, "migration.remote_helper_call", nil, :unresolved_sql},
             {:direct_ecto, "migration.control_flow", "up/0", :unresolved_sql}
           ]
  end

  test "rejects remote migration helpers from down callbacks" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "priv/repo/migrations/20260801000000_remote_helper.exs",
          source: """
          defmodule RemoteHelper do
            use Ecto.Migration

            def down do
              MigrationHelpers.install()
            end
          end
          """
        }
      ])

    assert occurrence.class == :direct_ecto
    assert occurrence.construct == "migration.remote_helper_call"
    assert occurrence.function == "down/0"
    assert occurrence.approval == :unresolved_sql
  end

  test "rejects remote migration helpers executed from the migration module body" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "priv/repo/migrations/20260801000000_module_body_helper.exs",
          source: """
          defmodule ModuleBodyHelper do
            use Ecto.Migration

            ExternalInstaller.install()

            def change, do: create(table(:items))
          end
          """
        }
      ])

    assert occurrence.class == :direct_ecto
    assert occurrence.construct == "migration.remote_helper_call"
    assert occurrence.function == nil
    assert occurrence.approval == :unresolved_sql
  end

  test "rejects Ecto migrator entrypoints and database command subprocesses" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/database_escape_paths.ex",
          source: """
          defmodule DatabaseEscapePaths do
            alias Ecto.Migrator
            alias System, as: ProcessRunner

            def migrate(path), do: Migrator.run(OfficeGraph.Repo, path, :up, all: true)
            def migrate_dynamic(migrator, repo, module), do: migrator.up(repo, 1, module, [])
            def direct(sql), do: ProcessRunner.cmd("psql", ["-c", sql])
            def shell, do: :os.cmd(~c"psql -c 'SELECT 1'")
            def dynamic(command, args), do: System.cmd(command, args)
            def stage, do: System.cmd("git", ["add", "tracked.ex"])
            def stage_intent(path), do: System.cmd("git", ["add", "--intent-to-add", "--", path])
            def fake_git, do: System.cmd("/tmp/git", ["init", "--quiet"])
            def disguised(command), do: System.cmd("sh", [command, "pg_dump"])
            def static_shell, do: System.cmd("sh", ["/tmp/run-db.sh"])
            def static_python, do: System.cmd("python3", ["/tmp/run-db.py"])
            def inspect_schema, do: System.cmd("pg_dump", ["--schema-only"])
            def inspect_container(container),
              do: System.cmd("docker", ["exec", "-e", "PGPASSWORD=secret", container, "pg_dump", "--schema-only"])
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.function, &1.approval}) == [
             {:direct_ecto, "Ecto.Migrator.run", "migrate/1", :unresolved_sql},
             {:direct_ecto, "variable_receiver.up", "migrate_dynamic/3", :unresolved_sql},
             {:raw_sql, "process.database_cli", "direct/1", :unresolved_sql},
             {:raw_sql, "process.database_cli", "shell/0", :unresolved_sql},
             {:raw_sql, "process.dynamic_command", "dynamic/2", :unresolved_sql},
             {:raw_sql, "process.dynamic_command", "stage/0", :unresolved_sql},
             {:raw_sql, "process.dynamic_command", "fake_git/0", :unresolved_sql},
             {:raw_sql, "process.dynamic_command", "disguised/1", :unresolved_sql},
             {:raw_sql, "process.dynamic_command", "static_shell/0", :unresolved_sql},
             {:raw_sql, "process.dynamic_command", "static_python/0", :unresolved_sql}
           ]
  end

  test "tracks SQL-like files as unapproved raw SQL" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{path: "priv/repo/manual_patch.sql", source: "SELECT pg_notify('events', 'changed');"},
        %{path: "priv/repo/manual_patch.SQL", source: "SELECT pg_notify('events', 'changed');"}
      ])

    assert Enum.map(occurrences, &{&1.path, &1.class, &1.construct, &1.approval, &1.line}) == [
             {"priv/repo/manual_patch.sql", :raw_sql, "tracked_sql_file", :unresolved_sql, 1},
             {"priv/repo/manual_patch.SQL", :raw_sql, "tracked_sql_file", :unresolved_sql, 1}
           ]
  end

  test "allows only the exact canonical verification shell seam" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "test/office_graph/project_quality_gate_test.exs",
          source: ~S|System.cmd("sh", ["bin/verify", "--print-environment"])|
        },
        %{
          path: "scripts/run_verify.exs",
          source: ~S|System.cmd("sh", ["bin/verify", "--print-environment"])|
        },
        %{
          path: "test/office_graph/project_quality_gate_test.exs",
          source: ~S|System.cmd("sh", ["/tmp/run-db.sh"])|
        }
      ])

    assert Enum.map(occurrences, &{&1.path, &1.construct, &1.approval}) == [
             {"scripts/run_verify.exs", "process.dynamic_command", :unresolved_sql},
             {"test/office_graph/project_quality_gate_test.exs", "process.dynamic_command",
              :unresolved_sql}
           ]
  end

  test "allows only the exact terminal database dump seam" do
    sources = [
      %{
        path: "test/support/office_graph/migration_conformance_support.ex",
        source: """
        defmodule OfficeGraph.TestSupport.MigrationConformanceSupport do
          def dump_terminal_inventory! do
            System.cmd("pg_dump", args, env: env, stderr_to_stdout: true)
          end
        end
        """
      },
      %{
        path: "test/support/office_graph/migration_conformance_support.ex",
        source: """
        defmodule OfficeGraph.TestSupport.MigrationConformanceSupport do
          def dump_terminal_inventory! do
            System.cmd("pg_dump", args, env: env, stderr_to_stdout: true, into: "")
          end
        end
        """
      }
    ]

    [occurrence] = DatabaseBoundaryScanner.scan_sources(sources)
    assert occurrence.construct == "process.dynamic_command"
    assert occurrence.function == "dump_terminal_inventory!/0"
    assert occurrence.approval == :unresolved_sql
  end

  test "invalidates the canonical verification seam when a reviewed script changes" do
    root = temporary_root("canonical_verifier_fingerprint")
    File.mkdir_p!(Path.join(root, "bin"))
    File.cp!("bin/verify", Path.join(root, "bin/verify"))
    File.cp!("bin/verify-migration-baseline", Path.join(root, "bin/verify-migration-baseline"))

    source = [
      %{
        path: "test/office_graph/project_quality_gate_test.exs",
        source: ~S|System.cmd("sh", ["bin/verify", "--print-environment"])|
      }
    ]

    assert DatabaseBoundaryScanner.scan_sources(source, root: root) == []

    File.write!(Path.join(root, "bin/verify"), File.read!("bin/verify") <> "\n# changed\n")

    [occurrence] = DatabaseBoundaryScanner.scan_sources(source, root: root)
    assert occurrence.construct == "process.dynamic_command"
    assert occurrence.approval == :unresolved_sql
  end

  test "preserves approved UUIDv7 fragment fingerprints" do
    occurrences =
      [
        "priv/repo/migrations/20260729233957_initial.exs",
        "priv/repo/migrations/20260730005539_integrate_workos_enterprise_identity.exs"
      ]
      |> Enum.flat_map(fn path ->
        DatabaseBoundaryScanner.scan_sources([%{path: path, source: File.read!(path)}])
      end)
      |> Enum.map(fn occurrence ->
        {occurrence.path, occurrence.line, occurrence.construct, occurrence.fingerprint}
      end)

    assert occurrences == [
             {"priv/repo/migrations/20260729233957_initial.exs", 4892, "fragment",
              "sha256:1c00daebdd2b1e43f8c59ea6a36b5a9606bf15f2292cd69cfa6c02b974e0717b"},
             {"priv/repo/migrations/20260730005539_integrate_workos_enterprise_identity.exs", 340,
              "fragment",
              "sha256:3fbfef45542e6568ac392c69d0849a575ae68dc51670f05002e2bb1abfc124f8"}
           ]
  end

  test "invalidates preserved UUIDv7 fingerprints when the fragment payload changes" do
    path = "priv/repo/migrations/20260729233957_initial.exs"

    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: path,
          source:
            path
            |> File.read!()
            |> String.replace("fragment(\"uuidv7()\")", "fragment(\"pg_sleep(1)\")",
              global: false
            )
        }
      ])
      |> Enum.filter(&(&1.construct == "fragment"))

    assert occurrence.line == 4892
    assert occurrence.construct == "fragment"

    refute occurrence.fingerprint ==
             "sha256:1c00daebdd2b1e43f8c59ea6a36b5a9606bf15f2292cd69cfa6c02b974e0717b"
  end

  test "invalidates the UUIDv7 loop exemption when its approved iterable changes" do
    path = "priv/repo/migrations/20260730005539_integrate_workos_enterprise_identity.exs"

    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: path,
          source:
            path
            |> File.read!()
            |> String.replace(
              "    :enterprise_directory_sync_events\n",
              "    :unapproved_table\n",
              global: false
            )
        }
      ])

    assert Enum.any?(occurrences, &(&1.construct == "migration.control_flow"))

    assert Enum.any?(
             occurrences,
             &(&1.construct == "fragment" and
                 &1.fingerprint ==
                   "sha256:3fbfef45542e6568ac392c69d0849a575ae68dc51670f05002e2bb1abfc124f8")
           )
  end

  test "runtime compiler fixtures reject generated source that is not content-approved" do
    root = temporary_root("unapproved_runtime_compiler_fixture")
    source_path = Path.join(root, "lib/unapproved_runtime_compiler_fixture.ex")
    ebin = Path.join(root, "_build/#{Mix.env()}/lib/office_graph/ebin")

    File.mkdir_p!(Path.dirname(source_path))
    File.mkdir_p!(ebin)

    File.write!(source_path, """
    defmodule OfficeGraph.UnapprovedRuntimeCompilerFixture do
      def run, do: :ok
    end
    """)

    assert_raise ArgumentError, ~r/generated compiler fixture source is not approved/, fn ->
      compile_file!(source_path, ebin)
    end
  end

  test "compiled audit reports low-level database calls from BEAM abstract code" do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_compiled_boundary_#{System.unique_integer([:positive])}"
      )

    source_path = Path.join(root, "lib/compiled_boundary_example.ex")
    ebin = Path.join(root, "_build/#{Mix.env()}/lib/office_graph/ebin")
    File.mkdir_p!(Path.dirname(source_path))
    File.mkdir_p!(ebin)
    on_exit(fn -> File.rm_rf!(root) end)
    previous_options = Code.compiler_options()
    Code.compiler_options(debug_info: true, ignore_module_conflict: true)
    on_exit(fn -> Code.compiler_options(previous_options) end)

    module = OfficeGraph.CompiledBoundaryExampleFixture

    File.write!(
      source_path,
      """
      defmodule #{inspect(module)} do
        def load do
          OfficeGraph.Repo.query!("SELECT 1", [])
        end
      end
      """
    )

    compile_file!(source_path, ebin, debug_info: true)

    [beam_path] = Path.wildcard(Path.join(ebin, "Elixir.OfficeGraph*.beam"))
    [occurrence] = DatabaseBoundaryScanner.scan_compiled(root, paths: [beam_path])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.path == "lib/compiled_boundary_example.ex"
    assert occurrence.line == 3
  end

  test "compiled audit rejects dynamic database receivers and apply targets" do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_compiled_dynamic_boundary_#{System.unique_integer([:positive])}"
      )

    source_path = Path.join(root, "lib/compiled_dynamic_boundary_example.exs")
    ebin = Path.join(root, "_build/#{Mix.env()}/lib/office_graph/ebin")
    File.mkdir_p!(Path.dirname(source_path))
    File.mkdir_p!(ebin)
    on_exit(fn -> File.rm_rf!(root) end)
    previous_options = Code.compiler_options()
    Code.compiler_options(debug_info: true)
    on_exit(fn -> Code.compiler_options(previous_options) end)

    module = OfficeGraph.CompiledDynamicBoundaryExampleFixture

    File.write!(
      source_path,
      """
      defmodule #{inspect(module)} do
        def dispatch_apply(target, sql), do: apply(target, :query, [sql])
        def dispatch_insert_apply(target, changeset), do: apply(target, :insert, [changeset])
        def dispatch_dynamic(repo, operation, arguments), do: apply(repo, operation, arguments)
        def capture_direct, do: Function.capture(OfficeGraph.Repo, :query!, 2)
        def capture_dynamic(repo, operation), do: Function.capture(repo, operation, 2)
        def dispatch_remote(target, sql), do: target.query(sql)
        def persist(target, changeset), do: target.insert(changeset)
        def transact(target, fun), do: target.transaction(fun)
        def explain(query), do: OfficeGraph.Repo.explain(:all, query, [])
        def current(repo), do: repo.get_dynamic_repo()
        def stop(repo), do: repo.stop()
        def evaluate(path), do: Code.eval_file(path)
        def evaluate_with_env(quoted, env), do: Code.eval_quoted_with_env(quoted, [], env)
        def evaluate_eex_string(template), do: EEx.eval_string(template, assigns: [])
        def evaluate_eex_file(path), do: EEx.eval_file(path, assigns: [])
        def compile_runtime(files), do: Kernel.ParallelCompiler.compile(files)
        def migrate(path), do: Ecto.Migrator.run(OfficeGraph.Repo, path, :up, all: true)
        def migrate_dynamic(migrator, repo, module), do: migrator.up(repo, 1, module, [])
        def spawn_query(sql), do: spawn(OfficeGraph.Repo, :query!, [sql, []])
        def rpc_query(sql), do: :rpc.call(node(), OfficeGraph.Repo, :query!, [sql, []])
        def rpc_async_query(sql), do: :rpc.async_call(node(), OfficeGraph.Repo, :query!, [sql, []])
        def start_repo(options), do: OfficeGraph.Repo.start_link(options)
        def process_spawn_query(sql), do: Process.spawn(OfficeGraph.Repo, :query!, [sql, []], [])
        def proc_lib_query(sql), do: :proc_lib.spawn(OfficeGraph.Repo, :query!, [sql, []])
        def hibernate_query(sql), do: :erlang.hibernate(OfficeGraph.Repo, :query!, [sql, []])
        def timed_query(sql), do: :timer.tc(OfficeGraph.Repo, :query!, [sql, []])
        def timed_query(unit, sql), do: :timer.tc(unit, OfficeGraph.Repo, :query!, [sql, []])
        def eval_terms(path), do: :file.eval(path)
        def eval_terms(path, bindings), do: :file.eval(path, bindings)
        def script(path), do: :file.script(path)
        def script(path, bindings), do: :file.script(path, bindings)
        def path_eval(path, name), do: :file.path_eval(path, name)
        def path_eval(path, name, bindings), do: :file.path_eval(path, name, bindings)
        def path_script(path, name), do: :file.path_script(path, name)
        def path_script(path, name, bindings), do: :file.path_script(path, name, bindings)
        def psql(sql), do: System.cmd("psql", ["-c", sql])
        def inspect_schema, do: System.cmd("pg_dump", ["--schema-only"])
      end
      """
    )

    compile_file!(source_path, ebin, debug_info: true)

    [beam_path] = Path.wildcard(Path.join(ebin, "Elixir.OfficeGraph*.beam"))
    occurrences = DatabaseBoundaryScanner.scan_compiled(root, paths: [beam_path])

    assert occurrences
           |> Enum.map(&{&1.class, &1.construct, Map.get(&1, :approval)})
           |> Enum.sort() ==
             [
               {:raw_sql, "variable_receiver.apply", :unresolved_sql},
               {:direct_ecto, "variable_receiver.apply", :unresolved_sql},
               {:raw_sql, "variable_receiver.apply", :unresolved_sql},
               {:raw_sql, "OfficeGraph.Repo.capture", :unresolved_sql},
               {:raw_sql, "variable_receiver.capture", :unresolved_sql},
               {:raw_sql, "variable_receiver.query", :unresolved_sql},
               {:direct_ecto, "variable_receiver.insert", :unresolved_sql},
               {:direct_ecto, "variable_receiver.transaction", :unresolved_sql},
               {:direct_ecto, "Repo.explain", nil},
               {:direct_ecto, "variable_receiver.get_dynamic_repo", :unresolved_sql},
               {:direct_ecto, "variable_receiver.stop", :unresolved_sql},
               {:direct_ecto, "reflection.Code.eval_file", :unresolved_sql},
               {:direct_ecto, "reflection.Code.eval_quoted_with_env", :unresolved_sql},
               {:direct_ecto, "reflection.EEx.eval_string", :unresolved_sql},
               {:direct_ecto, "reflection.EEx.eval_file", :unresolved_sql},
               {:direct_ecto, "reflection.Kernel.ParallelCompiler.compile", :unresolved_sql},
               {:direct_ecto, "Ecto.Migrator.run", :unresolved_sql},
               {:direct_ecto, "variable_receiver.up", :unresolved_sql},
               {:raw_sql, "OfficeGraph.Repo.spawn", :unresolved_sql},
               {:raw_sql, "OfficeGraph.Repo.call", :unresolved_sql},
               {:raw_sql, "OfficeGraph.Repo.async_call", :unresolved_sql},
               {:direct_ecto, "Repo.start_link", nil},
               {:raw_sql, "OfficeGraph.Repo.spawn_opt", :unresolved_sql},
               {:raw_sql, "OfficeGraph.Repo.spawn", :unresolved_sql},
               {:raw_sql, "OfficeGraph.Repo.hibernate", :unresolved_sql},
               {:raw_sql, "OfficeGraph.Repo.tc", :unresolved_sql},
               {:raw_sql, "OfficeGraph.Repo.tc", :unresolved_sql},
               {:direct_ecto, "reflection.file.eval", :unresolved_sql},
               {:direct_ecto, "reflection.file.eval", :unresolved_sql},
               {:direct_ecto, "reflection.file.script", :unresolved_sql},
               {:direct_ecto, "reflection.file.script", :unresolved_sql},
               {:direct_ecto, "reflection.file.path_eval", :unresolved_sql},
               {:direct_ecto, "reflection.file.path_eval", :unresolved_sql},
               {:direct_ecto, "reflection.file.path_script", :unresolved_sql},
               {:direct_ecto, "reflection.file.path_script", :unresolved_sql},
               {:raw_sql, "process.database_cli", :unresolved_sql}
             ]
             |> Enum.sort()
  end

  test "compiled audit rejects unresolved dispatch, private Ecto execution, and process ports" do
    root = temporary_root("compiled_strict_boundary")
    source_path = Path.join(root, "lib/compiled_strict_boundary.ex")
    ebin = Path.join(root, "_build/#{Mix.env()}/lib/office_graph/ebin")

    module = OfficeGraph.CompiledStrictBoundaryFixture

    compile_source!(source_path, ebin, """
    defmodule #{inspect(module)} do
      def apply_call(target, operation, arguments), do: apply(target, operation, arguments)
      def capture_call(target, operation), do: Function.capture(target, operation, 1)
      def spawn_call(target, operation, arguments), do: spawn(target, operation, arguments)
      def private_load(repo, query), do: Ecto.Repo.Queryable.all(repo, query, [])
      def private_insert(repo, schema, fields), do: Ecto.Repo.Schema.insert_all(repo, schema, fields, [])
      def run_migration(repo, migration), do: Ecto.Migration.Runner.run(repo, migration)
      def drop_database(config), do: Ecto.Adapters.Postgres.storage_down(config)
      def static_shell, do: System.cmd("sh", ["/tmp/run-db.sh"])
      def dash_shell, do: System.cmd("dash", ["/tmp/run-db.sh"])
      def port(command), do: Port.open({:spawn, command}, [])
      def busybox(command), do: System.cmd("busybox", ["sh", "-c", command])
      def multicast(nodes, sql), do: :erpc.multicast(nodes, OfficeGraph.Repo, :query!, [sql, []])
      def evaluate_everywhere(sql), do: :rpc.eval_everywhere(OfficeGraph.Repo, :query!, [sql, []])
      def parallel_evaluate(sql), do: :rpc.parallel_eval([{OfficeGraph.Repo, :query!, [sql, []]}])
      def parallel_map(sql), do: :rpc.pmap({OfficeGraph.Repo, :query!}, [[]], [sql])
      def load_binary(module, path, beam), do: :code.load_binary(module, path, beam)
      def evaluate_forms(forms), do: :erl_eval.exprs(forms, [])
      def timer_query(sql), do: :timer.apply_after(1, OfficeGraph.Repo, :query!, [sql, []])
      def listen(pid, channel), do: Postgrex.Notifications.listen(pid, channel)
      def simple_connection(options), do: Postgrex.SimpleConnection.start_link(__MODULE__, [], options)
      def mix_eval(code), do: System.cmd("mix", ["run", "-e", code])

      def supervised(supervisor, sql) do
        Supervisor.start_child(supervisor, %{
          id: :query,
          start: {OfficeGraph.Repo, :query!, [sql, []]}
        })
      end

      def otp_supervised(supervisor, sql) do
        :supervisor.start_child(supervisor, %{
          id: :query,
          start: {OfficeGraph.Repo, :query!, [sql, []]}
        })
      end
    end
    """)

    beam_path = Path.join(ebin, "#{module}.beam")
    occurrences = DatabaseBoundaryScanner.scan_compiled(root, paths: [beam_path])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.function, &1.approval}) == [
             {:raw_sql, "dynamic_dispatch.apply", "apply_call/3", :unresolved_sql},
             {:raw_sql, "dynamic_dispatch.capture", "capture_call/2", :unresolved_sql},
             {:raw_sql, "dynamic_dispatch.spawn", "spawn_call/3", :unresolved_sql},
             {:direct_ecto, "Ecto.Repo.Queryable.all", "private_load/2", :unresolved_sql},
             {:direct_ecto, "Ecto.Repo.Schema.insert_all", "private_insert/3", :unresolved_sql},
             {:direct_ecto, "Ecto.Migration.Runner.run", "run_migration/2", :unresolved_sql},
             {:direct_ecto, "Ecto.Adapters.Postgres.storage_down", "drop_database/1",
              :unresolved_sql},
             {:raw_sql, "process.dynamic_command", "static_shell/0", :unresolved_sql},
             {:raw_sql, "process.dynamic_command", "dash_shell/0", :unresolved_sql},
             {:raw_sql, "process.dynamic_command", "port/1", :unresolved_sql},
             {:raw_sql, "process.dynamic_command", "busybox/1", :unresolved_sql},
             {:raw_sql, "OfficeGraph.Repo.multicast", "multicast/2", :unresolved_sql},
             {:raw_sql, "OfficeGraph.Repo.eval_everywhere", "evaluate_everywhere/1",
              :unresolved_sql},
             {:raw_sql, "OfficeGraph.Repo.parallel_eval", "parallel_evaluate/1", :unresolved_sql},
             {:raw_sql, "OfficeGraph.Repo.pmap", "parallel_map/1", :unresolved_sql},
             {:direct_ecto, "reflection.code.load_binary", "load_binary/3", :unresolved_sql},
             {:direct_ecto, "reflection.erl_eval.exprs", "evaluate_forms/1", :unresolved_sql},
             {:raw_sql, "OfficeGraph.Repo.apply_after", "timer_query/1", :unresolved_sql},
             {:direct_ecto, "Postgrex.Notifications.listen", "listen/2", :unresolved_sql},
             {:direct_ecto, "Postgrex.SimpleConnection.start_link", "simple_connection/1",
              :unresolved_sql},
             {:raw_sql, "process.dynamic_command", "mix_eval/1", :unresolved_sql},
             {:raw_sql, "OfficeGraph.Repo.start_child", "supervised/2", :unresolved_sql},
             {:raw_sql, "OfficeGraph.Repo.start_child", "otp_supervised/2", :unresolved_sql}
           ]
  end

  test "compiled audit scans generated functions in the canonical Repo source" do
    root = temporary_root("compiled_generated_canonical_repo")
    init_git_repo!(root)

    suffix = System.unique_integer([:positive])
    macro_module = OfficeGraph.GeneratedRepoMacroFixture
    repo_module = OfficeGraph.GeneratedRepoTargetFixture
    macro_path = Path.join(System.tmp_dir!(), "generated_repo_macro_#{suffix}.ex")
    macro_ebin = Path.join(System.tmp_dir!(), "generated_repo_macro_ebin_#{suffix}")
    source_path = Path.join(root, "lib/office_graph/repo.ex")
    ebin = Path.join(root, "_build/#{Mix.env()}/lib/office_graph/ebin")

    on_exit(fn -> File.rm(macro_path) end)
    on_exit(fn -> File.rm_rf!(macro_ebin) end)

    compile_source!(macro_path, macro_ebin, """
    defmodule #{inspect(macro_module)} do
      defmacro install do
        quote generated: true do
          def generated_load(repo, query), do: Ecto.Repo.Queryable.all(repo, query, [])
        end
      end
    end
    """)

    File.mkdir_p!(Path.dirname(source_path))
    File.mkdir_p!(ebin)

    File.write!(source_path, """
    defmodule #{inspect(repo_module)} do
      require #{inspect(macro_module)}
      #{inspect(macro_module)}.install()
    end
    """)

    git!(root, ["add", "lib/office_graph/repo.ex"])

    compile_file!(source_path, ebin)

    beam_path = Path.join(ebin, "#{repo_module}.beam")

    assert [occurrence] = DatabaseBoundaryScanner.scan_compiled(root, paths: [beam_path])
    assert occurrence.construct == "Ecto.Repo.Queryable.all"
    assert occurrence.function == "generated_load/2"
    assert occurrence.approval == :unresolved_sql
  end

  test "compiled audit scans macro expansions inside authored canonical Repo definitions" do
    root = temporary_root("compiled_canonical_repo_macro")
    source_path = Path.join(root, "lib/office_graph/repo.ex")
    ebin = Path.join(root, "_build/#{Mix.env()}/lib/office_graph/ebin")
    macro_module = OfficeGraph.RepoBoundaryMacroFixture
    repo_module = OfficeGraph.CanonicalRepoBoundaryFixture

    compile_source!(source_path, ebin, """
    defmodule #{inspect(macro_module)} do
      defmacro query(sql) do
        quote do
          OfficeGraph.Repo.query!(unquote(sql), [])
        end
      end
    end

    defmodule #{inspect(repo_module)} do
      require #{inspect(macro_module)}

      def unsafe(sql), do: #{inspect(macro_module)}.query(sql)
    end
    """)

    beam_path = Path.join(ebin, "#{repo_module}.beam")
    [occurrence] = DatabaseBoundaryScanner.scan_compiled(root, paths: [beam_path])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.path == "lib/office_graph/repo.ex"
  end

  test "compiled audit retains generated private persistence calls from dependency macros" do
    root = temporary_root("compiled_generated_dependency_macro")
    init_git_repo!(root)

    suffix = System.unique_integer([:positive])
    macro_module = OfficeGraph.GeneratedPersistenceMacroFixture
    target_module = OfficeGraph.GeneratedPersistenceTargetFixture
    macro_path = Path.join(System.tmp_dir!(), "generated_persistence_macro_#{suffix}.ex")
    macro_ebin = Path.join(System.tmp_dir!(), "generated_persistence_macro_ebin_#{suffix}")
    source_path = Path.join(root, "lib/generated_persistence_target.ex")
    ebin = Path.join(root, "_build/#{Mix.env()}/lib/office_graph/ebin")

    on_exit(fn -> File.rm(macro_path) end)
    on_exit(fn -> File.rm_rf!(macro_ebin) end)

    compile_source!(macro_path, macro_ebin, """
    defmodule #{inspect(macro_module)} do
      defmacro load(repo, query) do
        quote generated: true do
          Ecto.Repo.Queryable.all(unquote(repo), unquote(query), [])
        end
      end
    end
    """)

    File.mkdir_p!(Path.dirname(source_path))
    File.mkdir_p!(ebin)

    File.write!(source_path, """
    defmodule #{inspect(target_module)} do
      require #{inspect(macro_module)}

      def load(repo, query), do: #{inspect(macro_module)}.load(repo, query)
    end
    """)

    git!(root, ["add", "lib/generated_persistence_target.ex"])

    compile_file!(source_path, ebin)

    beam_path = Path.join(ebin, "#{target_module}.beam")

    assert [occurrence] = DatabaseBoundaryScanner.scan_compiled(root, paths: [beam_path])
    assert occurrence.construct == "Ecto.Repo.Queryable.all"
    assert occurrence.function == "load/2"
    assert occurrence.approval == :unresolved_sql
  end

  test "compiled audit rejects persistence operations on expression receivers" do
    root = temporary_root("compiled_expression_boundary")
    source_path = Path.join(root, "lib/compiled_expression_boundary.ex")
    ebin = Path.join(root, "_build/#{Mix.env()}/lib/office_graph/ebin")

    module = OfficeGraph.CompiledExpressionBoundaryFixture

    compile_source!(source_path, ebin, """
    defmodule #{inspect(module)} do
      def persist(changeset), do: lookup_repo().insert(changeset)
      def transact(conn, fun), do: DBConnection.transaction(conn, fun)
      def postgrex_transact(conn, fun), do: Postgrex.transaction(conn, fun)
      defp lookup_repo, do: OfficeGraph.Repo
    end
    """)

    [beam_path] = Path.wildcard(Path.join(ebin, "Elixir.OfficeGraph*.beam"))
    occurrences = DatabaseBoundaryScanner.scan_compiled(root, paths: [beam_path])

    assert Enum.map(occurrences, &{&1.class, &1.construct, Map.get(&1, :approval)}) == [
             {:direct_ecto, "expression_receiver.insert", :unresolved_sql},
             {:direct_ecto, "DBConnection.transaction", nil},
             {:direct_ecto, "Postgrex.transaction", nil}
           ]
  end

  test "compiled audit preserves duplicate occurrences on the same source line" do
    root = temporary_root("compiled_boundary_multiplicity")
    source_path = Path.join(root, "lib/compiled_boundary_multiplicity.ex")
    ebin = Path.join(root, "_build/#{Mix.env()}/lib/office_graph/ebin")

    module = OfficeGraph.CompiledBoundaryMultiplicityFixture

    compile_source!(source_path, ebin, """
    defmodule #{inspect(module)} do
      def load, do: (OfficeGraph.Repo.query!("SELECT 1", []); OfficeGraph.Repo.query!("SELECT 2", []))
    end
    """)

    [first, second] =
      DatabaseBoundaryScanner.scan_compiled(root,
        paths: Path.wildcard(Path.join(ebin, "*.beam"))
      )

    assert {first.line, first.construct, first.function, first.ordinal} ==
             {2, "Repo.query!", "load/0", 1}

    assert {second.line, second.construct, second.function, second.ordinal} ==
             {2, "Repo.query!", "load/0", 2}
  end

  test "compiled audit scans every project BEAM module, not only OfficeGraph-prefixed modules" do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_compiled_boundary_all_modules_#{System.unique_integer([:positive])}"
      )

    source_path = Path.join(root, "lib/legacy_importer.ex")
    ebin = Path.join(root, "_build/#{Mix.env()}/lib/office_graph/ebin")
    File.mkdir_p!(Path.dirname(source_path))
    File.mkdir_p!(ebin)
    on_exit(fn -> File.rm_rf!(root) end)
    previous_options = Code.compiler_options()
    Code.compiler_options(debug_info: true)
    on_exit(fn -> Code.compiler_options(previous_options) end)

    File.write!(
      source_path,
      """
      defmodule LegacyImporter do
        def load do
          OfficeGraph.Repo.query!("SELECT 1", [])
        end
      end
      """
    )

    compile_file!(source_path, ebin, debug_info: true)

    [occurrence] =
      DatabaseBoundaryScanner.scan_compiled(root,
        paths: Path.wildcard(Path.join(ebin, "*.beam"))
      )

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.path == "lib/legacy_importer.ex"
    assert occurrence.function == "load/0"
  end

  test "compiled audit fails closed when a required environment has no BEAM output" do
    root = temporary_root("compiled_boundary_missing_environment")
    source_path = Path.join(root, "lib/current_environment_boundary.ex")
    current_ebin = Path.join(root, "_build/#{Mix.env()}/lib/office_graph/ebin")

    module = OfficeGraph.CurrentEnvironmentBoundaryFixture

    init_git_repo!(root)

    compile_source!(source_path, current_ebin, """
    defmodule #{inspect(module)} do
      def load, do: :ok
    end
    """)

    git!(root, ["add", "lib/current_environment_boundary.ex"])

    [occurrence] = DatabaseBoundaryScanner.scan_compiled(root)

    assert occurrence.class == :direct_ecto
    assert occurrence.construct == "compiled.environment_missing"
    assert occurrence.approval == :unresolved_sql
    assert occurrence.path == "mix.exs"
  end

  test "compiled audit does not count its excluded scanner BEAM as environment output" do
    root = temporary_root("compiled_boundary_scanner_only_environment")
    scanner_beam = :code.which(DatabaseBoundaryScanner) |> List.to_string()

    init_git_repo!(root)

    for env <- [Mix.env(), :prod] |> Enum.uniq() do
      ebin = Path.join(root, "_build/#{env}/lib/office_graph/ebin")
      File.mkdir_p!(ebin)
      File.cp!(scanner_beam, Path.join(ebin, Path.basename(scanner_beam)))
    end

    occurrences = DatabaseBoundaryScanner.scan_compiled(root)

    assert occurrences != []
    assert Enum.all?(occurrences, &(&1.construct == "compiled.environment_missing"))
  end

  test "compiled audit excludes only the exact scanner BEAM" do
    root = temporary_root("compiled_boundary_scanner_name_prefix")
    source_path = Path.join(root, "lib/database_boundary_scanner_plugin.ex")
    module = OfficeGraph.ProjectQuality.DatabaseBoundaryScannerPluginFixture

    init_git_repo!(root)

    source = """
    defmodule #{inspect(module)} do
      def load, do: OfficeGraph.Repo.query!("SELECT 1", [])
    end
    """

    for env <- [Mix.env(), :prod] |> Enum.uniq() do
      ebin = Path.join(root, "_build/#{env}/lib/office_graph/ebin")
      compile_source!(source_path, ebin, source)
    end

    git!(root, ["add", "lib/database_boundary_scanner_plugin.ex"])

    [occurrence] = DatabaseBoundaryScanner.scan_compiled(root)
    assert occurrence.construct == "Repo.query!"
    assert occurrence.path == "lib/database_boundary_scanner_plugin.ex"
  end

  test "compiled audit includes production BEAM output" do
    root = temporary_root("compiled_boundary_production")
    test_source_path = Path.join(root, "lib/test_environment_boundary.ex")
    prod_source_path = Path.join(root, "lib/prod_environment_boundary.ex")
    test_ebin = Path.join(root, "_build/#{Mix.env()}/lib/office_graph/ebin")
    prod_ebin = Path.join(root, "_build/prod/lib/office_graph/ebin")
    test_module = OfficeGraph.TestEnvironmentBoundaryFixture
    prod_module = OfficeGraph.ProdEnvironmentBoundaryFixture

    init_git_repo!(root)

    compile_source!(test_source_path, test_ebin, """
    defmodule #{inspect(test_module)} do
      def load, do: :ok
    end
    """)

    compile_source!(prod_source_path, prod_ebin, """
    defmodule #{inspect(prod_module)} do
      def load, do: OfficeGraph.Repo.query!("SELECT 1", [])
    end
    """)

    git!(root, ["add", "lib/test_environment_boundary.ex", "lib/prod_environment_boundary.ex"])

    [occurrence] = DatabaseBoundaryScanner.scan_compiled(root)
    assert occurrence.construct == "Repo.query!"
    assert occurrence.path == "lib/prod_environment_boundary.ex"
  end

  test "compiled audit ignores stale BEAMs whose source is no longer tracked" do
    root = temporary_root("compiled_boundary_stale")
    source_path = Path.join(root, "lib/stale_boundary.ex")
    module = OfficeGraph.StaleBoundaryFixture

    init_git_repo!(root)

    source = """
    defmodule #{inspect(module)} do
      def load, do: OfficeGraph.Repo.query!("SELECT 1", [])
    end
    """

    for env <- [Mix.env(), :prod] |> Enum.uniq() do
      ebin = Path.join(root, "_build/#{env}/lib/office_graph/ebin")
      compile_source!(source_path, ebin, source)
    end

    git!(root, ["add", "lib/stale_boundary.ex"])
    git!(root, ["mv", "lib/stale_boundary.ex", "lib/current_boundary.ex"])

    assert DatabaseBoundaryScanner.scan_compiled(root) == []
  end

  test "compiled audit fails closed when BEAM abstract code is unavailable" do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_compiled_boundary_no_debug_#{System.unique_integer([:positive])}"
      )

    source_path = Path.join(root, "lib/no_debug_boundary_example.ex")
    ebin = Path.join(root, "_build/#{Mix.env()}/lib/office_graph/ebin")
    File.mkdir_p!(Path.dirname(source_path))
    File.mkdir_p!(ebin)
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(
      source_path,
      """
      defmodule OfficeGraph.NoDebugBoundaryExample do
        @compile {:debug_info, false}

        def load do
          OfficeGraph.Repo.query!("SELECT 1", [])
        end
      end
      """
    )

    compile_file!(source_path, ebin, debug_info: false)

    [beam_path] = Path.wildcard(Path.join(ebin, "Elixir.OfficeGraph*.beam"))
    [occurrence] = DatabaseBoundaryScanner.scan_compiled(root, paths: [beam_path])

    assert occurrence.class == :direct_ecto
    assert occurrence.construct == "compiled.abstract_code_unavailable"
    assert occurrence.approval == :unresolved_sql
    assert occurrence.path == "lib/no_debug_boundary_example.ex"
  end

  test "repository scan includes every tracked Elixir source" do
    root = temporary_root("database_boundary_tracked_sources")
    init_git_repo!(root)

    sources = [
      {"config/runtime.exs", "OfficeGraph.Repo.query!(\"SELECT 1\", [])"},
      {".credo.exs", "OfficeGraph.Repo.query!(\"SELECT 2\", [])"},
      {"operations.exs", "OfficeGraph.Repo.query!(\"SELECT 3\", [])"}
    ]

    Enum.each(sources, fn {path, source} ->
      full_path = Path.join(root, path)
      File.mkdir_p!(Path.dirname(full_path))
      File.write!(full_path, source)
      git!(root, ["add", path])
    end)

    expected_paths = sources |> Enum.map(&elem(&1, 0)) |> Enum.sort()

    assert DatabaseBoundaryScanner.scan_repository(root)
           |> Enum.map(& &1.path) == expected_paths
  end

  test "repository scan skips tracked sources deleted from the worktree" do
    root = temporary_root("database_boundary_deleted_source")
    init_git_repo!(root)
    path = "scripts/deleted.exs"
    full_path = Path.join(root, path)

    File.mkdir_p!(Path.dirname(full_path))
    File.write!(full_path, ~S|OfficeGraph.Repo.query!("SELECT 1", [])|)
    git!(root, ["add", path])
    File.rm!(full_path)

    assert DatabaseBoundaryScanner.scan_repository(root) == []
  end

  test "current repository scan only reports exact reviewed occurrences" do
    assert DatabaseBoundaryScanner.scan_repository(File.cwd!())
           |> Enum.map(&{&1.path, &1.line, &1.construct, &1.fingerprint}) == [
             {"priv/repo/migrations/20260729233957_initial.exs", 4892, "fragment",
              "sha256:1c00daebdd2b1e43f8c59ea6a36b5a9606bf15f2292cd69cfa6c02b974e0717b"},
             {"priv/repo/migrations/20260730005539_integrate_workos_enterprise_identity.exs", 340,
              "fragment",
              "sha256:3fbfef45542e6568ac392c69d0849a575ae68dc51670f05002e2bb1abfc124f8"},
             {"test/office_graph/project_quality/database_boundary_gate_test.exs", 618,
              "reflection.Kernel.ParallelCompiler.compile_to_path",
              "sha256:e1f7cd55f322b02454f7c17e7e623568e53a0ae234e4ad8482803b9a75289ce0"},
             {"test/office_graph/project_quality/database_boundary_scanner_test.exs", 2490,
              "reflection.Kernel.ParallelCompiler.compile_to_path",
              "sha256:861c12ace96bf0eb625a4eed83cb9de563aee787fcfa615cb568494a38bdf78c"},
             {"test/office_graph/project_quality/project_boundaries_credo_check_test.exs", 342,
              "reflection.Kernel.ParallelCompiler.compile_to_path",
              "sha256:90f961bb5e48b5c5524bd93d86857c8960ae9cc836b595e4403d844020a92292"}
           ]
  end

  defp temporary_root(label) do
    root =
      Path.join(System.tmp_dir!(), "office_graph_#{label}_#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end

  defp init_git_repo!(root), do: git!(root, ["init", "--quiet"])

  defp git!(root, ["init", "--quiet"]) do
    assert {_output, 0} =
             System.cmd("git", ["init", "--quiet"], cd: root, stderr_to_stdout: true)

    :ok
  end

  defp git!(root, ["add" | paths]) do
    Enum.each(paths, fn path ->
      assert {_output, 0} =
               System.cmd("git", ["add", "--intent-to-add", "--", path],
                 cd: root,
                 stderr_to_stdout: true
               )
    end)

    :ok
  end

  defp git!(root, ["mv", source, destination]) do
    assert {_output, 0} =
             System.cmd("git", ["mv", "--", source, destination],
               cd: root,
               stderr_to_stdout: true
             )

    :ok
  end

  defp compile_source!(source_path, ebin, source) do
    File.mkdir_p!(Path.dirname(source_path))
    File.mkdir_p!(ebin)
    File.write!(source_path, source)

    compile_file!(source_path, ebin)
  end

  defp compile_file!(source_path, ebin, options \\ []) do
    compiler_options = Code.compiler_options()
    Code.compiler_options(debug_info: true, ignore_module_conflict: true)

    try do
      assert {:ok, _modules, _diagnostics} =
               Kernel.ParallelCompiler.compile_to_path(
                 [
                   source_path
                   |> File.read!()
                   |> then(fn source ->
                     fingerprint =
                       source
                       |> then(&:crypto.hash(:sha256, &1))
                       |> Base.encode16(case: :lower)

                     approved_sources = %{
                       canonical_repo_macro:
                         "8e31d5061a4eb59adb27e1ea51582028ad68982fcd7de0745fd08ba79e116ad9",
                       compiled_boundary:
                         "e97785c4198e1b316c535066697961dc04342975d13248b80a51a56ee21a929b",
                       compiled_dynamic_boundary:
                         "da9fd37f9522df00058eaab060ddad7ab654e684845d17919255665d313571b1",
                       compiled_expression_boundary:
                         "87cf440de249265a352aa19dfa02a9ce914854e5ea30cae02a14deae44bc6a91",
                       compiled_multiplicity:
                         "d4a454347c1d5cb1d4b4fbe87bbd911336f8cdd62e0bb150a6e417ecd49d15ae",
                       compiled_reviewed_runtime_boundaries:
                         "e8c35125ec372268f6a80be31a11642339ef263b6dca5b9f993e7094e5cdfdc6",
                       compiled_strict_boundary:
                         "f3fa046ea2e6761141e06322341712ebd629f12d04c56dd18a81e77444d9562d",
                       current_environment:
                         "51da408a16c40a07129763d7f89926d2758405fd69d92f2f22e05ba0830d5286",
                       generated_persistence_macro:
                         "7e857d6c6e0efc76894b3609ade7103b0ad9836a3265cdb5cda41b33a994b4a4",
                       generated_persistence_target:
                         "bc27d6dc5776f18e5378dec5f7d448883939f4c947f790891242ca7cedf375a7",
                       generated_repo_macro:
                         "bf0328b0d25c03ecda5b5a3a1a63496fed0b6e557e29b95259590da36e814886",
                       generated_repo_target:
                         "9283bb98601d116ad56b32e0d17b855fa08aed26ae670ced3832ac6a644f9e1b",
                       legacy_importer:
                         "ebec71783de7b0bfe0fe1d9576837bb5c3d4bb83283d611d3f959e6b8249f84c",
                       no_debug_info:
                         "3fc628b2184eef161a9c5590b04efaaa3c2920fabfd12ee289b57342bbcbb012",
                       production_environment:
                         "3519554bcb5f1c02bb7bb4d6044eccbb4bcb738f1ec584c36274b393be0f0ef2",
                       scanner_prefix:
                         "dbd0797870523b233fa8494a6fbbca3b9512a78257b63113518960604b8a030b",
                       stale_boundary:
                         "6819a3b481ca97500414fdaa42e70471aea0eee7253aff003eafa0658f0c1a95",
                       test_environment:
                         "0f93bd491507c0845b6a608aaa1f7eab6cd65f785fc136514c6953768f683c42"
                     }

                     if fingerprint in Map.values(approved_sources) do
                       source_path
                     else
                       raise ArgumentError,
                             "generated compiler fixture source is not approved: sha256:#{fingerprint}"
                     end
                   end)
                 ],
                 ebin,
                 Keyword.put(options, :return_diagnostics, true)
               )
    after
      Code.compiler_options(compiler_options)
    end
  end

  test "resolves wildcard imports for runtime MFA dispatch" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "scripts/wildcard_task_dispatch.exs",
          source: """
          defmodule WildcardTaskDispatch do
            import Task

            def run(sql), do: async(OfficeGraph.Repo, :query!, [sql, []])
          end
          """
        }
      ])

    assert {occurrence.class, occurrence.construct, occurrence.function, occurrence.approval} ==
             {:raw_sql, "OfficeGraph.Repo.async", "run/1", :unresolved_sql}
  end

  test "rejects standard module and tuple supervisor child specs" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "scripts/supervisor_child_specs.exs",
          source: """
          defmodule SupervisorChildSpecs do
            def tuple(supervisor, options),
              do: Supervisor.start_child(supervisor, {OfficeGraph.Repo, options})

            def module(supervisor),
              do: DynamicSupervisor.start_child(supervisor, OfficeGraph.Repo)

            def worker_tuple(supervisor, options),
              do: Supervisor.start_child(supervisor, {Worker, options})

            def worker_module(supervisor),
              do: DynamicSupervisor.start_child(supervisor, Worker)
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.function, &1.approval}) == [
             {:raw_sql, "OfficeGraph.Repo.start_child", "tuple/2", :unresolved_sql},
             {:raw_sql, "OfficeGraph.Repo.start_child", "module/1", :unresolved_sql}
           ]
  end

  test "rejects repository children passed to Supervisor.start_link" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "scripts/supervisor_start_link_children.exs",
          source: """
          defmodule SupervisorStartLinkChildren do
            def repo(options),
              do: Supervisor.start_link([{OfficeGraph.Repo, options}], strategy: :one_for_one)

            def worker(options),
              do: Supervisor.start_link([{Worker, options}], strategy: :one_for_one)
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.function, &1.approval}) == [
             {:raw_sql, "OfficeGraph.Repo.start_link", "repo/1", :unresolved_sql}
           ]
  end

  test "recognizes the built-in child-spec constructor without flagging generic workers" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "scripts/constructed_supervisor_child_specs.exs",
          source: """
          defmodule ConstructedSupervisorChildSpecs do
            def repo(supervisor, options),
              do:
                Supervisor.start_child(
                  supervisor,
                  Supervisor.child_spec(OfficeGraph.Repo, id: :review_repo)
                )

            def worker(supervisor, options),
              do:
                Supervisor.start_child(
                  supervisor,
                  Supervisor.child_spec({Worker, options}, id: :worker)
                )

            def unresolved(supervisor, child_spec),
              do: Supervisor.start_child(supervisor, child_spec)
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.function, &1.approval}) == [
             {:raw_sql, "OfficeGraph.Repo.start_child", "repo/2", :unresolved_sql}
           ]
  end

  test "rejects direct repository startup through Ecto.Repo.Supervisor" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "scripts/private_repo_supervisor.exs",
          source: """
          Ecto.Repo.Supervisor.start_link(
            OfficeGraph.Repo,
            :office_graph,
            Ecto.Adapters.Postgres,
            []
          )
          """
        }
      ])

    assert {occurrence.class, occurrence.construct, occurrence.approval} ==
             {:direct_ecto, "Ecto.Repo.Supervisor.start_link", :unresolved_sql}
  end

  test "rejects IEx compilation and recompilation helpers" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "scripts/iex_compilation.exs",
          source: """
          IEx.Helpers.c(path)
          IEx.Helpers.c(path, output_path)
          IEx.Helpers.r(module)
          IEx.Helpers.recompile()
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.approval}) == [
             {"reflection.IEx.Helpers.c", :unresolved_sql},
             {"reflection.IEx.Helpers.c", :unresolved_sql},
             {"reflection.IEx.Helpers.r", :unresolved_sql},
             {"reflection.IEx.Helpers.recompile", :unresolved_sql}
           ]
  end

  test "rejects runtime evaluation through Mix tasks" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "scripts/mix_task_evaluation.exs",
          source: """
          Mix.Tasks.Run.run(["-e", code])
          Mix.Tasks.Eval.run([code])
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.approval}) == [
             {"reflection.Mix.Tasks.Run.run", :unresolved_sql},
             {"reflection.Mix.Tasks.Eval.run", :unresolved_sql}
           ]
  end

  test "rejects indirect runtime evaluation, code loading, and Mix shell execution" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "scripts/runtime_escape_paths.exs",
          source: """
          defmodule RuntimeEscapePaths do
            def mix_run(arguments), do: Mix.Task.run("run", arguments)
            def mix_rerun(arguments), do: Mix.Task.rerun("eval", arguments)
            def erlang_compile(path), do: :c.c(path)
            def erlang_network_compile(path), do: :c.nc(path)
            def code_load(path), do: Code.load_file(path)
            def config_eval(path, contents), do: Config.Reader.eval!(path, contents, [])
            def config_read(path), do: Config.Reader.read!(path, imports: :enabled)
            def config_imports(path), do: Config.Reader.read_imports!(path, imports: :enabled)
            def expand(ast, env), do: Macro.expand(ast, env)
            def expand_once(ast, env), do: Macro.expand_once(ast, env)
            def shell(command), do: Mix.Shell.cmd(Mix.Shell.IO, command, fn _ -> :ok end)
            def io_shell(command), do: Mix.Shell.IO.cmd(command)
            def process_shell(command), do: Mix.Shell.Process.cmd(command)
            def quiet_shell(command), do: Mix.Shell.Quiet.cmd(command)
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.function, &1.approval}) == [
             {"reflection.Mix.Task.run", "mix_run/1", :unresolved_sql},
             {"reflection.Mix.Task.rerun", "mix_rerun/1", :unresolved_sql},
             {"reflection.c.c", "erlang_compile/1", :unresolved_sql},
             {"reflection.c.nc", "erlang_network_compile/1", :unresolved_sql},
             {"reflection.Code.load_file", "code_load/1", :unresolved_sql},
             {"reflection.Config.Reader.eval!", "config_eval/2", :unresolved_sql},
             {"reflection.Config.Reader.read!", "config_read/1", :unresolved_sql},
             {"reflection.Config.Reader.read_imports!", "config_imports/1", :unresolved_sql},
             {"reflection.Macro.expand", "expand/2", :unresolved_sql},
             {"reflection.Macro.expand_once", "expand_once/2", :unresolved_sql},
             {"process.dynamic_command", "shell/1", :unresolved_sql},
             {"process.dynamic_command", "io_shell/1", :unresolved_sql},
             {"process.dynamic_command", "process_shell/1", :unresolved_sql},
             {"process.dynamic_command", "quiet_shell/1", :unresolved_sql}
           ]
  end

  test "trusts project macros only when their modules are defined in tracked sources" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/tracked_macro.ex",
          source:
            "defmodule OfficeGraph.TrackedMacro do\n  defmacro __using__(_options), do: quote(do: :ok)\nend"
        },
        %{
          path: "lib/macro_consumers.ex",
          source: """
          defmodule OfficeGraph.MacroConsumers do
            use OfficeGraph.TrackedMacro
            use OfficeGraph.DependencyPersistenceMacro
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.line, &1.approval}) == [
             {"dependency_macro.use", 3, :unresolved_sql}
           ]
  end

  test "tracks compound SQL-like source suffixes as unapproved raw SQL" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{path: "priv/repo/patch.sql.eex", source: "SELECT 1"},
        %{path: "scripts/report.PSQL.template", source: "SELECT 2"},
        %{path: "scripts/not_sql.sqlx.eex", source: "SELECT 3"}
      ])

    assert Enum.map(occurrences, &{&1.path, &1.construct, &1.approval}) == [
             {"priv/repo/patch.sql.eex", "tracked_sql_file", :unresolved_sql},
             {"scripts/report.PSQL.template", "tracked_sql_file", :unresolved_sql}
           ]
  end

  test "rejects direct Erlang compiler entrypoints" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "scripts/erlang_compiler.exs",
          source: """
          :compile.file(path)
          :compile.file(path, options)
          :compile.forms(forms)
          :compile.forms(forms, options)
          :compile.noenv_file(path, options)
          :compile.noenv_forms(forms, options)
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.approval}) == [
             {"reflection.compile.file", :unresolved_sql},
             {"reflection.compile.file", :unresolved_sql},
             {"reflection.compile.forms", :unresolved_sql},
             {"reflection.compile.forms", :unresolved_sql},
             {"reflection.compile.noenv_file", :unresolved_sql},
             {"reflection.compile.noenv_forms", :unresolved_sql}
           ]
  end

  test "trusts Config.Reader only for project-root files anchored to the source directory" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources(
        [
          %{
            path: "test/office_graph/runtime_config_test.exs",
            source: """
            Config.Reader.read!("config/config.exs")
            Config.Reader.read!(Path.expand("../../config/config.exs", __DIR__))
            Config.Reader.read_imports!(Path.expand("../../config/runtime.exs", __DIR__))
            Config.Reader.read!(Path.expand("../../external/config.exs", __DIR__))
            """
          },
          %{
            path: "scripts/spoofed_config_reader.exs",
            source: """
            alias Dependency.Path, as: Path
            Config.Reader.read!(Path.expand("../config/config.exs", __DIR__))
            """
          }
        ],
        root: "/workspace/office_graph"
      )

    assert Enum.map(occurrences, &{&1.construct, &1.line, &1.approval}) == [
             {"reflection.Config.Reader.read!", 1, :unresolved_sql},
             {"reflection.Config.Reader.read!", 4, :unresolved_sql},
             {"reflection.Config.Reader.read!", 2, :unresolved_sql}
           ]
  end

  test "rejects opaque dependency macros even when the tracked source compiled" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources(
        [
          %{
            path: "lib/compiled_dependency_macros.ex",
            source: """
            defmodule CompiledDependencyMacros do
              require Dependency.QueryMacros
              import Dependency.CommandMacros
              use Dependency.PersistenceDSL
            end
            """
          }
        ],
        compiled_source_paths: MapSet.new(["lib/compiled_dependency_macros.ex"])
      )

    assert Enum.map(occurrences, &{&1.construct, &1.line, &1.approval}) == [
             {"dependency_macro.require", 2, :unresolved_sql},
             {"dependency_macro.import", 3, :unresolved_sql},
             {"dependency_macro.use", 4, :unresolved_sql}
           ]
  end

  test "rejects anonymous helper invocation in migration execution contexts" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "priv/repo/migrations/20260811000000_anonymous_helper.exs",
          source: """
          defmodule AnonymousHelperMigration do
            use Ecto.Migration

            def up do
              callback = &execute/1
              callback.("SELECT 1")
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.function, &1.approval}) == [
             {"migration.helper_call", "up/0", :unresolved_sql}
           ]
  end

  test "compiled audit rejects reviewed runtime startup and evaluation escape paths" do
    root = temporary_root("compiled_reviewed_runtime_boundaries")
    source_path = Path.join(root, "lib/compiled_reviewed_runtime_boundaries.ex")
    ebin = Path.join(root, "_build/#{Mix.env()}/lib/office_graph/ebin")

    module = OfficeGraph.CompiledReviewedRuntimeBoundariesFixture

    compile_source!(source_path, ebin, """
    defmodule #{inspect(module)} do
      def private_start(options),
        do: Ecto.Repo.Supervisor.start_link(OfficeGraph.Repo, :office_graph, Ecto.Adapters.Postgres, options)

      def compile(path), do: IEx.Helpers.c(path)
      def recompile(module), do: IEx.Helpers.r(module)

      def tuple(supervisor, options),
        do: Supervisor.start_child(supervisor, {OfficeGraph.Repo, options})

      def module(supervisor),
        do: DynamicSupervisor.start_child(supervisor, OfficeGraph.Repo)

      def supervisor_start_link(options),
        do: Supervisor.start_link([{OfficeGraph.Repo, options}], strategy: :one_for_one)

      def constructed(supervisor),
        do:
          Supervisor.start_child(
            supervisor,
            Supervisor.child_spec(OfficeGraph.Repo, id: :review_repo)
          )

      def unresolved(supervisor, child_spec),
        do: Supervisor.start_child(supervisor, child_spec)

      def mix_run(arguments), do: Mix.Tasks.Run.run(arguments)
      def mix_eval(arguments), do: Mix.Tasks.Eval.run(arguments)
      def mix_task_run(arguments), do: Mix.Task.run("run", arguments)
      def mix_task_rerun(arguments), do: Mix.Task.rerun("eval", arguments)
      def erlang_compile(path), do: :c.c(path)
      def compiler_file(path, options), do: :compile.file(path, options)
      def config_read(path), do: Config.Reader.read!(path)
      def expand(ast, env), do: Macro.expand(ast, env)
      def shell(command), do: Mix.Shell.IO.cmd(command)
    end
    """)

    beam_path = Path.join(ebin, "#{module}.beam")
    occurrences = DatabaseBoundaryScanner.scan_compiled(root, paths: [beam_path])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.function, &1.approval}) == [
             {:direct_ecto, "Ecto.Repo.Supervisor.start_link", "private_start/1",
              :unresolved_sql},
             {:direct_ecto, "reflection.IEx.Helpers.c", "compile/1", :unresolved_sql},
             {:direct_ecto, "reflection.IEx.Helpers.r", "recompile/1", :unresolved_sql},
             {:raw_sql, "OfficeGraph.Repo.start_child", "tuple/2", :unresolved_sql},
             {:raw_sql, "OfficeGraph.Repo.start_child", "module/1", :unresolved_sql},
             {:raw_sql, "OfficeGraph.Repo.start_link", "supervisor_start_link/1",
              :unresolved_sql},
             {:raw_sql, "OfficeGraph.Repo.start_child", "constructed/1", :unresolved_sql},
             {:direct_ecto, "reflection.Mix.Tasks.Run.run", "mix_run/1", :unresolved_sql},
             {:direct_ecto, "reflection.Mix.Tasks.Eval.run", "mix_eval/1", :unresolved_sql},
             {:direct_ecto, "reflection.Mix.Task.run", "mix_task_run/1", :unresolved_sql},
             {:direct_ecto, "reflection.Mix.Task.rerun", "mix_task_rerun/1", :unresolved_sql},
             {:direct_ecto, "reflection.c.c", "erlang_compile/1", :unresolved_sql},
             {:direct_ecto, "reflection.compile.file", "compiler_file/2", :unresolved_sql},
             {:direct_ecto, "reflection.Config.Reader.read!", "config_read/1", :unresolved_sql},
             {:direct_ecto, "reflection.Macro.expand", "expand/2", :unresolved_sql},
             {:raw_sql, "process.dynamic_command", "shell/1", :unresolved_sql}
           ]
  end
end
