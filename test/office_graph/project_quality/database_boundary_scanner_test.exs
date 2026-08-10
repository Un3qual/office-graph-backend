defmodule OfficeGraph.ProjectQuality.DatabaseBoundaryScannerTest do
  use ExUnit.Case, async: true

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
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/office_graph/repo.ex",
          source: """
          defmodule OfficeGraph.Repo do
            use AshPostgres.Repo, otp_app: :office_graph

            def unsafe(sql), do: query!(sql, [])
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.function, &1.approval}) == [
             {:raw_sql, "Repo.query!", "unsafe/1", :unresolved_sql}
           ]
  end

  test "rejects additional Ecto.Repo modules and audits their authored calls" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/secondary_repo.ex",
          source: """
          defmodule SecondaryRepo do
            use Ecto.Repo, otp_app: :office_graph, adapter: Ecto.Adapters.Postgres

            def unsafe(sql), do: query!(sql, [])
          end
          """
        }
      ])

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
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.function, &1.approval}) == [
             {"reflection.Code.eval_file", "evaluate/1", :unresolved_sql},
             {"reflection.Code.require_file", "require_runtime/1", :unresolved_sql},
             {"reflection.Code.compile_file", "compile_runtime/1", :unresolved_sql}
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

  test "audits dynamic-repo and repository connection-control operations" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/dynamic_repo_boundary.ex",
          source: """
          defmodule DynamicRepoBoundary do
            def select(repo), do: OfficeGraph.Repo.put_dynamic_repo(repo)
            def current, do: OfficeGraph.Repo.get_dynamic_repo()
            def disconnect, do: OfficeGraph.Repo.disconnect_all(1_000)
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.function}) == [
             {:direct_ecto, "Repo.put_dynamic_repo", "select/1"},
             {:direct_ecto, "Repo.get_dynamic_repo", "current/0"},
             {:direct_ecto, "Repo.disconnect_all", "disconnect/0"}
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
            def disguised(command), do: System.cmd("sh", [command, "pg_dump"])
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
             {:raw_sql, "process.dynamic_command", "disguised/1", :unresolved_sql}
           ]
  end

  test "tracks SQL-like files as unapproved raw SQL" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{path: "priv/repo/manual_patch.sql", source: "SELECT pg_notify('events', 'changed');"}
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "tracked_sql_file"
    assert occurrence.approval == :unresolved_sql
    assert occurrence.line == 1
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
    Code.compiler_options(debug_info: true)
    on_exit(fn -> Code.compiler_options(previous_options) end)

    module =
      Module.concat(
        OfficeGraph,
        "CompiledBoundaryExample#{System.unique_integer([:positive])}"
      )

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

    assert {:ok, _modules, %{compile_warnings: [], runtime_warnings: []}} =
             Kernel.ParallelCompiler.compile_to_path([source_path], ebin,
               debug_info: true,
               return_diagnostics: true
             )

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

    module =
      Module.concat(
        OfficeGraph,
        "CompiledDynamicBoundaryExample#{System.unique_integer([:positive])}"
      )

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
        def migrate(path), do: Ecto.Migrator.run(OfficeGraph.Repo, path, :up, all: true)
        def migrate_dynamic(migrator, repo, module), do: migrator.up(repo, 1, module, [])
        def psql(sql), do: System.cmd("psql", ["-c", sql])
        def inspect_schema, do: System.cmd("pg_dump", ["--schema-only"])
      end
      """
    )

    assert {:ok, _modules, %{compile_warnings: [], runtime_warnings: []}} =
             Kernel.ParallelCompiler.compile_to_path([source_path], ebin,
               debug_info: true,
               return_diagnostics: true
             )

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
               {:direct_ecto, "Ecto.Migrator.run", :unresolved_sql},
               {:direct_ecto, "variable_receiver.up", :unresolved_sql},
               {:raw_sql, "process.database_cli", :unresolved_sql}
             ]
             |> Enum.sort()
  end

  test "compiled audit scans macro expansions inside authored canonical Repo definitions" do
    root = temporary_root("compiled_canonical_repo_macro")
    source_path = Path.join(root, "lib/office_graph/repo.ex")
    ebin = Path.join(root, "_build/#{Mix.env()}/lib/office_graph/ebin")
    suffix = System.unique_integer([:positive])
    macro_module = Module.concat(OfficeGraph, "RepoBoundaryMacro#{suffix}")
    repo_module = Module.concat(OfficeGraph, "CanonicalRepoBoundary#{suffix}")

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

  test "compiled audit rejects persistence operations on expression receivers" do
    root = temporary_root("compiled_expression_boundary")
    source_path = Path.join(root, "lib/compiled_expression_boundary.ex")
    ebin = Path.join(root, "_build/#{Mix.env()}/lib/office_graph/ebin")

    module =
      Module.concat(
        OfficeGraph,
        "CompiledExpressionBoundary#{System.unique_integer([:positive])}"
      )

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

    module =
      Module.concat(
        OfficeGraph,
        "CompiledBoundaryMultiplicity#{System.unique_integer([:positive])}"
      )

    compile_source!(source_path, ebin, """
    defmodule #{inspect(module)} do
      def load, do: (OfficeGraph.Repo.query!("SELECT 1", []); OfficeGraph.Repo.query!("SELECT 2", []))
    end
    """)

    [first, second] = DatabaseBoundaryScanner.scan_compiled(root)

    assert {first.line, first.construct, first.ordinal} == {2, "Repo.query!", 1}
    assert {second.line, second.construct, second.ordinal} == {2, "Repo.query!", 2}
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

    assert {:ok, _modules, %{compile_warnings: [], runtime_warnings: []}} =
             Kernel.ParallelCompiler.compile_to_path([source_path], ebin,
               debug_info: true,
               return_diagnostics: true
             )

    [occurrence] = DatabaseBoundaryScanner.scan_compiled(root)

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.path == "lib/legacy_importer.ex"
  end

  test "compiled audit includes production BEAM output" do
    root = temporary_root("compiled_boundary_production")
    test_source_path = Path.join(root, "lib/test_environment_boundary.ex")
    prod_source_path = Path.join(root, "lib/prod_environment_boundary.ex")
    test_ebin = Path.join(root, "_build/#{Mix.env()}/lib/office_graph/ebin")
    prod_ebin = Path.join(root, "_build/prod/lib/office_graph/ebin")
    suffix = System.unique_integer([:positive])
    test_module = Module.concat(OfficeGraph, "TestEnvironmentBoundary#{suffix}")
    prod_module = Module.concat(OfficeGraph, "ProdEnvironmentBoundary#{suffix}")

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
    ebin = Path.join(root, "_build/#{Mix.env()}/lib/office_graph/ebin")
    module = Module.concat(OfficeGraph, "StaleBoundary#{System.unique_integer([:positive])}")

    init_git_repo!(root)

    compile_source!(source_path, ebin, """
    defmodule #{inspect(module)} do
      def load, do: OfficeGraph.Repo.query!("SELECT 1", [])
    end
    """)

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

    assert {:ok, _modules, %{compile_warnings: [], runtime_warnings: []}} =
             Kernel.ParallelCompiler.compile_to_path([source_path], ebin,
               debug_info: false,
               return_diagnostics: true
             )

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

  test "current repository scan only reports approved UUIDv7 fragments" do
    assert DatabaseBoundaryScanner.scan_repository(File.cwd!())
           |> Enum.map(&{&1.path, &1.line, &1.construct, &1.fingerprint}) == [
             {"priv/repo/migrations/20260729233957_initial.exs", 4892, "fragment",
              "sha256:1c00daebdd2b1e43f8c59ea6a36b5a9606bf15f2292cd69cfa6c02b974e0717b"},
             {"priv/repo/migrations/20260730005539_integrate_workos_enterprise_identity.exs", 340,
              "fragment",
              "sha256:3fbfef45542e6568ac392c69d0849a575ae68dc51670f05002e2bb1abfc124f8"}
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

  defp git!(root, arguments) do
    assert {_output, 0} = System.cmd("git", arguments, cd: root, stderr_to_stdout: true)
    :ok
  end

  defp compile_source!(source_path, ebin, source) do
    File.mkdir_p!(Path.dirname(source_path))
    File.mkdir_p!(ebin)
    File.write!(source_path, source)

    assert {_output, 0} =
             System.cmd("elixirc", ["-o", ebin, source_path], stderr_to_stdout: true)
  end
end
