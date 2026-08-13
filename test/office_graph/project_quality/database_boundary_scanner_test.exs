defmodule OfficeGraph.ProjectQuality.DatabaseBoundaryScannerTest do
  use ExUnit.Case, async: true

  alias OfficeGraph.ProjectQuality.{DatabaseBoundaryScanner, DatabaseDependencyAudit}

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

    [beam_path] = Path.wildcard(Path.join(ebin, "Elixir.OfficeGraph*.beam"))
    {root, source_path, beam_path}
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
