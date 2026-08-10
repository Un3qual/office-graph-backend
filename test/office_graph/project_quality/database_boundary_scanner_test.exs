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

            def persist(changeset), do: Repo.insert_or_update(changeset)
            def reload_record(record), do: Repo.reload(record)
            def prepare(conn), do: Postgrex.prepare_execute(conn, "example", "SELECT 1", [])
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.function}) == [
             {:direct_ecto, "Repo.insert_or_update", "persist/1"},
             {:direct_ecto, "Repo.reload", "reload_record/1"},
             {:raw_sql, "Postgrex.prepare_execute", "prepare/1"}
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
    assert occurrence.path =~ "NoDebugBoundaryExample.beam"
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
end
