defmodule OfficeGraph.ProjectQuality.DatabaseBoundaryScannerTest do
  use ExUnit.Case, async: true

  defmodule HiddenDatabaseMacro do
    defmacro query do
      quote do
        OfficeGraph.Repo.query!("SELECT hidden", [])
      end
    end
  end

  alias OfficeGraph.ProjectQuality.{
    DatabaseBoundaryGate,
    DatabaseBoundaryScanner,
    DatabaseDependencyAudit
  }

  @uuidv7_approvals [
    {"priv/repo/migrations/20260729233957_initial.exs", 4892, "fragment",
     "sha256:1c00daebdd2b1e43f8c59ea6a36b5a9606bf15f2292cd69cfa6c02b974e0717b"},
    {"priv/repo/migrations/20260730005539_integrate_workos_enterprise_identity.exs", 340,
     "fragment", "sha256:3fbfef45542e6568ac392c69d0849a575ae68dc51670f05002e2bb1abfc124f8"}
  ]

  test "classifies direct repository SQL through an explicit alias" do
    [occurrence] =
      scan("lib/example.ex", """
      defmodule Example do
        alias OfficeGraph.Repo

        def load(id) do
          Repo.query!("SELECT * FROM examples WHERE id = $1", [id])
        end
      end
      """)

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.function == "load/1"
    assert occurrence.line == 5
    assert String.starts_with?(occurrence.fingerprint, "sha256:")
    refute Map.has_key?(occurrence, :approval)
  end

  test "rejects a direct raw SQL call with a nonliteral payload" do
    [occurrence] =
      scan("lib/example.ex", """
      defmodule Example do
        def load(statement), do: OfficeGraph.Repo.query!(statement, [])
      end
      """)

    assert occurrence.construct == "Repo.query!"
    assert occurrence.approval == :unresolved_sql
  end

  test "classifies direct Repo, Ecto, Postgrex, DBConnection, and migrator calls" do
    occurrences =
      scan("lib/example.ex", """
      defmodule Example do
        def run(changeset, multi, connection) do
          OfficeGraph.Repo.insert(changeset)
          OfficeGraph.Repo.explain(:all, query)
          Ecto.Multi.update(multi, :record, changeset)
          Postgrex.query(connection, "SELECT 1", [])
          DBConnection.prepare(connection, "query", [])
          Ecto.Migrator.run(OfficeGraph.Repo, "priv/repo/migrations", :up, all: true)
          Ecto.Adapters.Postgres.storage_status([])
          Ecto.Repo.Supervisor.start_link(:office_graph, OfficeGraph.Repo, [])
          DBConnection.Holder.checkout(pool, [], [])
          Postgrex.Notifications.listen(notifications, "events")
          Postgrex.ReplicationConnection.call(replication, :status)
          Ecto.Adapters.Postgres.Connection.query(connection, "SELECT 2", [], [])
        end
      end
      """)

    assert MapSet.new(occurrences, &{&1.class, &1.construct}) ==
             MapSet.new([
               {:direct_ecto, "Repo.insert"},
               {:direct_ecto, "Repo.explain"},
               {:direct_ecto, "Ecto.Multi.update"},
               {:raw_sql, "Postgrex.query"},
               {:raw_sql, "DBConnection.prepare"},
               {:direct_ecto, "Ecto.Migrator.run"},
               {:direct_ecto, "Ecto.Adapters.Postgres.storage_status"},
               {:direct_ecto, "Ecto.Repo.Supervisor.start_link"},
               {:direct_ecto, "DBConnection.Holder.checkout"},
               {:direct_ecto, "Postgrex.Notifications.listen"},
               {:direct_ecto, "Postgrex.ReplicationConnection.call"},
               {:raw_sql, "Ecto.Adapters.Postgres.Connection.query"}
             ])

    refute occurrences
           |> Enum.find(&(&1.construct == "Postgrex.query"))
           |> Map.has_key?(:approval)

    refute Enum.find(
             occurrences,
             &(&1.construct == "Ecto.Adapters.Postgres.Connection.query")
           )
           |> Map.has_key?(:approval)
  end

  test "classifies direct Ecto repository internals in uncompiled sources" do
    occurrences =
      scan("test/example_test.exs", """
      defmodule OfficeGraph.ExampleTest do
        def run(query, changeset) do
          Ecto.Repo.Queryable.all(OfficeGraph.Repo, query, [])
          Ecto.Repo.Schema.insert(OfficeGraph.Repo, :dynamic, changeset, :tuplet, [])
          Ecto.Repo.Transaction.transaction(OfficeGraph.Repo, :dynamic, fn -> :ok end, [])
        end
      end
      """)

    assert Enum.map(occurrences, & &1.construct) == [
             "Ecto.Repo.Queryable.all",
             "Ecto.Repo.Schema.insert",
             "Ecto.Repo.Transaction.transaction"
           ]
  end

  test "classifies imported SQL adapter and query fragment calls" do
    occurrences =
      scan("lib/example.ex", """
      defmodule Example do
        import Ecto.Adapters.SQL, only: [query: 3]
        import Ecto.Query, only: [fragment: 1]

        def load do
          query(OfficeGraph.Repo, "SELECT 1", [])
          fragment("lower(name)")
        end
      end
      """)

    assert Enum.map(occurrences, & &1.construct) == ["Ecto.Adapters.SQL.query", "fragment"]
    refute Map.has_key?(hd(occurrences), :approval)
  end

  test "resolves grouped and prefixed static aliases" do
    occurrences =
      scan("lib/example.ex", """
      defmodule Example do
        alias Ecto.{Multi, Migrator}
        alias OfficeGraph, as: OG

        def run(multi) do
          Multi.insert_or_update(multi, :record, %{})
          Migrator.migrations(OG.Repo)
          OG.Repo.transaction(fn -> :ok end)
        end
      end
      """)

    assert Enum.map(occurrences, & &1.construct) == [
             "Ecto.Multi.insert_or_update",
             "Ecto.Migrator.migrations",
             "Repo.transaction"
           ]
  end

  test "does not classify unrelated receivers by operation name" do
    assert scan("lib/example.ex", """
           defmodule Example do
             def run(value) do
               Example.query(value)
               Example.fragment(value)
               Example.transaction(fn -> value end)
             end
           end
           """) == []
  end

  test "classifies SQL-bearing Ecto query options but not typed Ash locks" do
    occurrences =
      scan("lib/example.ex", """
      defmodule Example do
        import Ecto.Query

        def ecto(query) do
          lock(query, "FOR UPDATE SKIP LOCKED")
          lock(query, System.fetch_env!("LOCK"))
          from(row in query, hints: ["TABLESAMPLE SYSTEM (1)"])
        end

        def ash(query), do: Ash.Query.lock(query, :for_update)
      end
      """)

    assert Enum.map(occurrences, & &1.construct) == ["query.lock", "query.lock", "query.from"]
    assert Enum.at(occurrences, 1).approval == :unresolved_sql
  end

  test "classifies static and dynamic AshPostgres SQL settings" do
    occurrences =
      scan("lib/example_resource.ex", """
      defmodule ExampleResource do
        alias Ash, as: Framework
        alias AshPostgres.DataLayer, as: Postgres
        use Framework.Resource, data_layer: Postgres

        postgres do
          create_table_options "fillfactor=70"
          base_filter_sql System.fetch_env!("BASE_FILTER_SQL")
          check_constraint :positive_count, check: "count > 0"
        end
      end
      """)

    assert Enum.map(occurrences, & &1.construct) == [
             "ash_postgres.create_table_options",
             "ash_postgres.base_filter_sql",
             "ash_postgres.check_constraint"
           ]

    assert Enum.at(occurrences, 1).approval == :unresolved_sql
    refute Map.has_key?(Enum.at(occurrences, 0), :approval)
  end

  test "rejects raw SQL, external files, helpers, control flow, and direct Repo calls in migrations" do
    occurrences =
      scan("priv/repo/migrations/20260801000000_invalid.exs", """
      defmodule InvalidMigration do
        use Ecto.Migration

        def change do
          if System.get_env("CREATE") do
            create_examples()
          end

          System.get_env("CREATE_MORE") && create_more_examples()
          helper = fn -> :ok end
          helper.()
          __MODULE__.create_even_more_examples()

          execute("ALTER TABLE examples ADD COLUMN label text")
          execute("ALTER TABLE examples ADD COLUMN note text", dynamic_down())
          execute_file("priv/repo/sql/change.sql")
          OfficeGraph.Repo.insert!(%{})
        end
      end
      """)

    constructs = MapSet.new(occurrences, & &1.construct)
    assert MapSet.member?(constructs, "migration.control_flow")
    assert MapSet.member?(constructs, "migration.helper_call")
    assert MapSet.member?(constructs, "migration.execute")
    assert MapSet.member?(constructs, "migration.execute_file")
    assert MapSet.member?(constructs, "Repo.insert!")

    assert Enum.find(occurrences, &(&1.construct == "migration.execute_file")).approval ==
             :unresolved_sql

    assert occurrences
           |> Enum.filter(&(&1.construct == "migration.execute"))
           |> Enum.map(&Map.get(&1, :approval)) == [nil, :unresolved_sql]
  end

  test "rejects nondeclarative syntax inside guarded migration callbacks" do
    occurrences =
      scan("priv/repo/migrations/20260801000000_guarded.exs", """
      defmodule GuardedMigration do
        use Ecto.Migration

        def up() when true do
          if System.get_env("CREATE") do
            create_examples()
          end
        end
      end
      """)

    assert MapSet.new(occurrences, & &1.construct) ==
             MapSet.new(["migration.control_flow", "migration.helper_call"])

    assert Enum.all?(occurrences, &(&1.function == "up/0"))
  end

  test "rejects bare zero-arity migration helper calls" do
    [occurrence] =
      scan("priv/repo/migrations/20260801000000_bare_helper.exs", """
      defmodule BareHelperMigration do
        use Ecto.Migration

        def up, do: create_objects
        defp create_objects, do: create(table(:examples))
      end
      """)

    assert occurrence.construct == "migration.helper_call"
    assert occurrence.function == "up/0"
    assert occurrence.line == 4
  end

  test "classifies migration constraint SQL and index expression fields" do
    occurrences =
      scan("priv/repo/migrations/20260801000000_sql_fields.exs", """
      defmodule SqlFieldsMigration do
        use Ecto.Migration

        def change do
          create constraint(:accounts, :positive_balance, check: "balance > 0")
          create constraint(:reservations, :no_overlap, exclude: System.fetch_env!("RULE"))
          create index(:users, ["lower(email)"])
          create unique_index(:users, dynamic_fields())
        end
      end
      """)

    raw_sql_occurrences = Enum.filter(occurrences, &(&1.class == :raw_sql))

    assert Enum.map(raw_sql_occurrences, & &1.construct) == [
             "migration.constraint_options",
             "migration.constraint_options",
             "migration.index_expression",
             "migration.index_expression"
           ]

    refute Map.has_key?(Enum.at(raw_sql_occurrences, 0), :approval)
    assert Enum.at(raw_sql_occurrences, 1).approval == :unresolved_sql
    refute Map.has_key?(Enum.at(raw_sql_occurrences, 2), :approval)
    assert Enum.at(raw_sql_occurrences, 3).approval == :unresolved_sql
  end

  test "classifies generated-column SQL in migration options" do
    occurrences =
      scan("priv/repo/migrations/20260801000000_generated_columns.exs", """
      defmodule GeneratedColumnsMigration do
        use Ecto.Migration

        def change do
          alter table(:examples) do
            add :slug, :text, generated: "lower(name)"
            modify :search_text, :text, generated: generated_expression()
          end
        end
      end
      """)

    raw_sql_occurrences = Enum.filter(occurrences, &(&1.class == :raw_sql))

    assert Enum.map(raw_sql_occurrences, & &1.construct) == [
             "migration.add_options",
             "migration.modify_options"
           ]

    refute Map.has_key?(Enum.at(raw_sql_occurrences, 0), :approval)
    assert Enum.at(raw_sql_occurrences, 1).approval == :unresolved_sql
    assert Enum.any?(occurrences, &(&1.construct == "migration.helper_call"))
  end

  test "classifies SQL-bearing AshPostgres custom indexes in their DSL context" do
    occurrences =
      scan("lib/example_resource.ex", """
      defmodule ExampleResource do
        use Ash.Resource, data_layer: AshPostgres.DataLayer

        postgres do
          custom_indexes do
            index [:organization_id], name: "typed_index"
            index [:email], where: "deleted_at IS NULL"
            index ["lower(email)"], name: "email_expression_index"
            index dynamic_fields(), where: dynamic_predicate()
          end
        end
      end
      """)

    assert MapSet.new(occurrences, fn occurrence ->
             {occurrence.line, occurrence.construct, Map.get(occurrence, :approval)}
           end) ==
             MapSet.new([
               {7, "ash_postgres.custom_index", nil},
               {8, "ash_postgres.custom_index_expression", nil},
               {9, "ash_postgres.custom_index", :unresolved_sql},
               {9, "ash_postgres.custom_index_expression", :unresolved_sql}
             ])
  end

  test "rejects fully qualified nondeclarative Ecto migration calls" do
    occurrences =
      scan("priv/repo/migrations/20260801000000_qualified_invalid.exs", """
      defmodule OfficeGraph.Repo.Migrations.QualifiedInvalid do
        use Ecto.Migration

        def up do
          Ecto.Migration.insert(:examples, [%{id: 1}])
          Ecto.Migration.fragment("uuidv7()")
          Ecto.Migration.repo()
          Ecto.Migration.after_begin(fn -> :ok end)
        end
      end
      """)

    assert MapSet.new(occurrences, & &1.construct) ==
             MapSet.new([
               "migration.insert",
               "fragment",
               "migration.repo",
               "migration.helper_call"
             ])
  end

  test "accepts ordinary declarative migration syntax" do
    assert scan("priv/repo/migrations/20260801000000_declarative.exs", """
           defmodule DeclarativeMigration do
             use Ecto.Migration

             def change do
               create table(:examples) do
                 add :id, :uuid, primary_key: true
                 add :label, :text, null: false
               end

               create unique_index(:examples, [:label])
             end
           end
           """) == []
  end

  test "generic runtime execution is outside the database boundary" do
    assert scan("lib/runtime.ex", """
           defmodule Runtime do
             def run(provider, operation, arguments) do
               apply(provider, operation, arguments)
               Task.start(fn -> provider.execute(arguments) end)
               Module.concat([provider, Adapter])
               :erpc.call(node(), provider, operation, arguments)
             end
           end
           """) == []
  end

  test "ignores comments, documentation, ordinary strings, and quoted syntax" do
    assert scan("lib/example.ex", """
           defmodule Example do
             # OfficeGraph.Repo.query!("SELECT 1", [])
             @doc ~S|execute("CREATE TABLE examples (id uuid)")|
             def note, do: quote(do: OfficeGraph.Repo.query!("SELECT 1", []))
           end
           """) == []
  end

  test "scans explicit unquote evaluation while leaving quoted syntax inert" do
    [occurrence] =
      scan("lib/example.ex", """
      defmodule Example do
        def quoted do
          quote do
            unquote(OfficeGraph.Repo.query!("SELECT 1", []))
            OfficeGraph.Repo.query!("SELECT 2", [])
          end
        end
      end
      """)

    assert occurrence.construct == "Repo.query!"
    assert occurrence.function == "quoted/0"
    assert occurrence.line == 4
  end

  test "tracks compound and case-insensitive SQL-like files by exact content" do
    [first] = scan("priv/repo/manual.SQL.EEX", "SELECT 1;")
    [second] = scan("priv/repo/manual.SQL.EEX", "SELECT 2;")

    assert first.class == :raw_sql
    assert first.construct == "tracked_sql_file"
    refute Map.has_key?(first, :approval)
    refute first.fingerprint == second.fingerprint
  end

  test "rejects direct database clients in tracked scripts without interpreting shell flow" do
    [occurrence] =
      scan("bin/manual-database-task", """
      #!/usr/bin/env sh
      psql "$DATABASE_URL" -c 'SELECT 1'
      """)

    assert occurrence.line == 2
    assert occurrence.construct == "script.database_client.psql"
    assert occurrence.approval == :unresolved_sql

    assert scan("bin/ordinary-task", """
           #!/usr/bin/env sh
           # psql is forbidden here.
           printf '%s' 'psql is documentation'
           mix ecto.migrate
           """) == []

    [elixir_occurrence] =
      scan("bin/database-task.exs", "OfficeGraph.Repo.query!(\"SELECT 1\", [])")

    assert elixir_occurrence.construct == "Repo.query!"
  end

  test "rejects database clients in extensionless shell scripts outside bin" do
    [occurrence] =
      scan("scripts/reset-database", """
      #!/usr/bin/env bash
      exec psql "$DATABASE_URL" -c 'SELECT 1'
      """)

    assert occurrence.line == 2
    assert occurrence.construct == "script.database_client.psql"
  end

  test "rejects literal database clients in tracked JavaScript scripts" do
    [occurrence] =
      scan("assets/scripts/database-task.mjs", """
      import {execFile} from "node:child_process";
      execFile("psql", [process.env.DATABASE_URL, "-c", "SELECT 1"]);
      """)

    assert occurrence.line == 2
    assert occurrence.construct == "script.database_client.psql"
    assert occurrence.approval == :unresolved_sql

    assert scan("assets/src/database-copy.ts", "const label = 'psql documentation';") == []
  end

  test "rejects multiline JavaScript clients while leaving block comments inert" do
    [occurrence] =
      scan("assets/scripts/database-task.mjs", """
      /*
      execFile("psql", []);
      */
      const openCommentMarker = "/*";
      execFile(
        "psql",
        [process.env.DATABASE_URL]
      );
      const closeCommentMarker = "*/";
      """)

    assert occurrence.line == 5
    assert occurrence.construct == "script.database_client.psql"
  end

  test "preserves only the exact approved UUIDv7 migration contexts" do
    assert repository_uuidv7_occurrences() == @uuidv7_approvals

    path = "priv/repo/migrations/20260730005539_integrate_workos_enterprise_identity.exs"

    changed_source =
      path
      |> File.read!()
      |> String.replace("    :enterprise_directory_sync_events\n", "    :other_table\n",
        global: false
      )

    occurrences = scan(path, changed_source)
    fragment = Enum.find(occurrences, &(&1.construct == "fragment"))

    assert Enum.any?(occurrences, &(&1.construct == "migration.control_flow"))
    refute fragment.fingerprint == elem(List.last(@uuidv7_approvals), 3)
  end

  test "compiled audit reports direct database imports" do
    {root, source_path, beam_path} =
      compile_fixture("compiled_database_boundary", """
      defmodule OfficeGraph.CompiledDatabaseBoundary do
        def load, do: OfficeGraph.Repo.query!("SELECT 1", [])
      end
      """)

    [occurrence] =
      DatabaseDependencyAudit.scan(root,
        paths: [beam_path],
        tracked_paths: MapSet.new([source_path])
      )

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.path == source_path
    assert occurrence.caller == "OfficeGraph.CompiledDatabaseBoundary"
    assert occurrence.module == "OfficeGraph.Repo"
    assert occurrence.arity == 2
    assert occurrence.function == "load/0"
    assert occurrence.line == 2
  end

  test "compiled audit reports direct Repo explain calls" do
    {root, source_path, beam_path} =
      compile_fixture("compiled_repo_explain_boundary", """
      defmodule OfficeGraph.CompiledRepoExplainBoundary do
        def explain(query), do: OfficeGraph.Repo.explain(:all, query)
      end
      """)

    [occurrence] =
      DatabaseDependencyAudit.scan(root,
        paths: [beam_path],
        tracked_paths: MapSet.new([source_path])
      )

    assert occurrence.class == :direct_ecto
    assert occurrence.construct == "Repo.explain"
    assert occurrence.arity == 2
  end

  test "compiled audit discovers tracked generated modules outside the OfficeGraph prefix" do
    {root, source_path, beam_path} =
      compile_fixture("compiled_generated_boundary", """
      defmodule Inspect.OfficeGraph.CompiledGeneratedBoundary do
        def load, do: OfficeGraph.Repo.query!("SELECT 1", [])
      end
      """)

    ebin = Path.join(root, "_build/test/lib/office_graph/ebin")
    File.mkdir_p!(ebin)
    File.cp!(beam_path, Path.join(ebin, Path.basename(beam_path)))

    [occurrence] =
      DatabaseDependencyAudit.scan(root,
        environments: [:test],
        include_test_modules: false,
        tracked_paths: MapSet.new([source_path])
      )

    assert occurrence.caller == "Inspect.OfficeGraph.CompiledGeneratedBoundary"
    assert occurrence.construct == "Repo.query!"
  end

  test "compiled audit discovers direct dependencies emitted into test-module BEAMs" do
    root = temporary_root("compiled_test_module_boundary")
    source_path = "test/generated_boundary_test.exs"
    full_source_path = Path.join(root, source_path)
    ebin = Path.join(root, "_build/test/lib/office_graph/test_ebin")

    File.mkdir_p!(Path.dirname(full_source_path))
    File.mkdir_p!(ebin)

    File.write!(full_source_path, """
    defmodule OfficeGraph.GeneratedBoundaryTest do
      def load, do: OfficeGraph.Repo.query!("SELECT 1", [])
    end
    """)

    assert {:ok, _modules, %{compile_warnings: [], runtime_warnings: []}} =
             Kernel.ParallelCompiler.compile_to_path([full_source_path], ebin,
               debug_info: true,
               return_diagnostics: true
             )

    [occurrence] =
      DatabaseDependencyAudit.scan(root,
        environments: [],
        include_test_modules: true,
        tracked_paths: MapSet.new([source_path])
      )

    assert occurrence.path == source_path
    assert occurrence.caller == "OfficeGraph.GeneratedBoundaryTest"
    assert occurrence.construct == "Repo.query!"
  end

  test "compiled reconciliation requires the exact caller and arity" do
    [source] =
      scan("lib/example.ex", """
      defmodule OfficeGraph.Example do
        def load, do: OfficeGraph.Repo.query!("SELECT 1", [])
      end
      """)

    assert DatabaseBoundaryGate.compare_compiled([compiled_occurrence(source, 2)], [source]) == []

    [arity_diagnostic] =
      DatabaseBoundaryGate.compare_compiled([compiled_occurrence(source, 3)], [source])

    assert arity_diagnostic.kind == :compiled_reference
    assert arity_diagnostic.arity == 3

    [caller_diagnostic] =
      DatabaseBoundaryGate.compare_compiled(
        [compiled_occurrence(source, 2, "OfficeGraph.GeneratedExample")],
        [source]
      )

    assert caller_diagnostic.kind == :compiled_reference
    assert caller_diagnostic.caller == "OfficeGraph.GeneratedExample"
  end

  test "compiled reconciliation detects an additional macro-generated call in the same module" do
    source = """
    defmodule OfficeGraph.CompiledMacroBoundary do
      require #{inspect(HiddenDatabaseMacro)}
      def explicit, do: OfficeGraph.Repo.query!("SELECT explicit", [])
      def hidden, do: #{inspect(HiddenDatabaseMacro)}.query()
    end
    """

    {root, source_path, beam_path} = compile_fixture("compiled_macro_boundary", source)
    [source_occurrence] = scan(source_path, source)

    compiled =
      DatabaseDependencyAudit.scan(root,
        paths: [beam_path],
        tracked_paths: MapSet.new([source_path])
      )

    assert Enum.map(compiled, &{&1.function, &1.line}) == [
             {"explicit/0", 3},
             {"hidden/0", 4}
           ]

    [diagnostic] = DatabaseBoundaryGate.compare_compiled(compiled, [source_occurrence])
    assert diagnostic.kind == :compiled_reference
    assert diagnostic.function == "hidden/0"
    assert diagnostic.line == 4
  end

  test "source occurrences use the compiled name of nested modules" do
    [occurrence] =
      scan("lib/example.ex", """
      defmodule OfficeGraph.Example do
        defmodule Nested.Loader do
          def load, do: OfficeGraph.Repo.query!("SELECT 1", [])
        end
      end
      """)

    assert occurrence.caller == "OfficeGraph.Example.Nested.Loader"
  end

  test "compiled audit ignores generic callback imports" do
    {root, source_path, beam_path} =
      compile_fixture("compiled_generic_callback", """
      defmodule OfficeGraph.CompiledGenericCallback do
        def run(provider), do: Task.start(fn -> provider.run() end)
      end
      """)

    assert DatabaseDependencyAudit.scan(root,
             paths: [beam_path],
             tracked_paths: MapSet.new([source_path])
           ) == []
  end

  test "compiled audit fails closed when required build output is absent" do
    root = temporary_root("missing_compiled_environment")

    [occurrence] =
      DatabaseDependencyAudit.scan(root,
        environments: [:prod],
        tracked_paths: MapSet.new()
      )

    assert occurrence.construct == "compiled.environment_missing"
    assert occurrence.path == "_build/prod/lib/office_graph/ebin"
  end

  test "compiled audit fails closed for a repository outside the current directory" do
    root = temporary_root("external_repository_builds")

    occurrences = DatabaseDependencyAudit.scan(root, tracked_paths: MapSet.new())

    assert MapSet.new(occurrences, & &1.path) ==
             MapSet.new([
               "_build/prod/lib/office_graph/ebin",
               "_build/test/lib/office_graph/ebin",
               "_build/test/lib/office_graph/test_ebin"
             ])
  end

  test "current repository source scan reports only approved UUIDv7 fragments" do
    assert DatabaseBoundaryScanner.scan_repository(File.cwd!())
           |> Enum.map(&{&1.path, &1.line, &1.construct, &1.fingerprint}) == @uuidv7_approvals
  end

  defp scan(path, source),
    do: DatabaseBoundaryScanner.scan_sources([%{path: path, source: source}])

  defp repository_uuidv7_occurrences do
    @uuidv7_approvals
    |> Enum.map(&elem(&1, 0))
    |> Enum.flat_map(fn path -> scan(path, File.read!(path)) end)
    |> Enum.map(&{&1.path, &1.line, &1.construct, &1.fingerprint})
  end

  defp compile_fixture(name, source) do
    root = temporary_root(name)
    source_path = "lib/#{name}.ex"
    full_source_path = Path.join(root, source_path)
    ebin = Path.join(root, "ebin")

    File.mkdir_p!(Path.dirname(full_source_path))
    File.mkdir_p!(ebin)
    File.write!(full_source_path, source)

    assert {:ok, _modules, %{compile_warnings: [], runtime_warnings: []}} =
             Kernel.ParallelCompiler.compile_to_path([full_source_path], ebin,
               debug_info: true,
               return_diagnostics: true
             )

    [beam_path] = Path.wildcard(Path.join(ebin, "*.beam"))
    {root, source_path, beam_path}
  end

  defp compiled_occurrence(source, arity, caller \\ "OfficeGraph.Example") do
    source
    |> Map.merge(%{
      arity: arity,
      caller: caller,
      module: "OfficeGraph.Repo",
      operation: :query!
    })
    |> Map.put(:fingerprint, "sha256:compiled-#{caller}-#{arity}")
  end

  defp temporary_root(name) do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_#{name}_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end
end
