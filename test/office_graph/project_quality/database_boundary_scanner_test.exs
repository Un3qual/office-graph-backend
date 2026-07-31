defmodule OfficeGraph.ProjectQuality.DatabaseBoundaryScannerTest do
  use ExUnit.Case, async: true

  alias OfficeGraph.ProjectQuality.DatabaseBoundaryScanner

  test "classifies a direct repository SQL call" do
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
  end

  test "classifies repository operations through an explicit alias" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            alias OfficeGraph.Repo, as: Database

            def persist(changeset) do
              Database.query!("SELECT 1", [])
              Database.insert(changeset)
            end
          end
          """
        }
      ])

    assert MapSet.new(occurrences, &{&1.class, &1.construct}) ==
             MapSet.new([
               {:raw_sql, "Repo.query!"},
               {:direct_ecto, "Repo.insert"}
             ])
  end

  test "classifies imported SQL adapter calls only within their lexical scope" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule ImportedQuery do
            import Ecto.Adapters.SQL, only: [query: 3]

            def load(repo) do
              query(repo, "SELECT 1", [])
            end
          end

          defmodule UnrelatedQuery do
            def load(repo) do
              query(repo, "SELECT 2", [])
            end
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Ecto.Adapters.SQL.query"
    assert occurrence.function == "load/1"
    assert occurrence.line == 5
  end

  test "does not leak repository aliases across sibling modules" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule DatabaseBacked do
            alias OfficeGraph.Repo, as: Store

            def load(id), do: Store.get!(Example, id)
          end

          defmodule CacheBacked do
            def load(id), do: Store.get!(Example, id)
          end
          """
        }
      ])

    assert occurrence.construct == "Repo.get!"
    assert occurrence.function == "load/1"
    assert occurrence.line == 4
  end

  test "nested aliases shadow repository aliases without changing the outer scope" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Outer do
            alias OfficeGraph.Repo, as: Store

            def before(id), do: Store.get!(Example, id)

            defmodule Inner do
              alias OfficeGraph.Cache, as: Store

              def load(id), do: Store.get!(Example, id)
            end

            def later(id), do: Store.get!(Example, id)
          end
          """
        }
      ])

    assert Enum.map(occurrences, & &1.function) == ["before/1", "later/1"]
    assert Enum.all?(occurrences, &(&1.construct == "Repo.get!"))
  end

  test "classifies database calls in implicit function exception clauses" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            alias OfficeGraph.Repo

            def load(id) do
              :ok
            rescue
              _error -> Repo.get!(Example, id)
            end
          end
          """
        }
      ])

    assert occurrence.construct == "Repo.get!"
    assert occurrence.function == "load/1"
    assert occurrence.line == 7
  end

  test "classifies SQL adapter calls and fragments as raw SQL" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            import Ecto.Query

            def load(query, connection) do
              Ecto.Adapters.SQL.query(OfficeGraph.Repo, "SELECT 1", [])
              Postgrex.query(connection, "SELECT 2", [])
              where(query, [row], fragment("lower(?)", row.name) == "name")
              {:unsafe_fragment, "(organization_id) WHERE workspace_id IS NULL"}
            end
          end
          """
        }
      ])

    assert MapSet.new(occurrences, &{&1.class, &1.construct}) ==
             MapSet.new([
               {:raw_sql, "Ecto.Adapters.SQL.query"},
               {:raw_sql, "Postgrex.query"},
               {:raw_sql, "fragment"},
               {:raw_sql, "unsafe_fragment"}
             ])
  end

  test "classifies fully qualified and aliased Ecto query fragments as raw SQL" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            alias Ecto.Query.API, as: QueryAPI

            def load do
              Ecto.Query.API.fragment("lower(?)", "NAME")
              QueryAPI.unsafe_fragment("(organization_id)")
              Example.Fragment.fragment("not sql")
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.line}) == [
             {:raw_sql, "Ecto.Query.API.fragment", 5},
             {:raw_sql, "Ecto.Query.API.unsafe_fragment", 6}
           ]
  end

  test "classifies direct Ecto operations separately from raw SQL" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            alias OfficeGraph.Repo

            def persist(changeset, rows) do
              Repo.transaction(fn -> Repo.insert_all(Example, rows) end)
              Ecto.Multi.new() |> Ecto.Multi.insert(:example, changeset)
            end
          end
          """
        }
      ])

    assert MapSet.new(occurrences, &{&1.class, &1.construct}) ==
             MapSet.new([
               {:direct_ecto, "Repo.transaction"},
               {:direct_ecto, "Repo.insert_all"},
               {:direct_ecto, "Ecto.Multi.insert"}
             ])
  end

  test "classifies repository relationship and record reload reads" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            alias OfficeGraph.Repo

            def load(records) do
              Repo.preload(records, :children)
              Repo.preload!(records, :children)
              Repo.reload(records)
              Repo.reload!(records)
              Repo.all_by(Example, status: "active")
            end
          end
          """
        }
      ])

    assert MapSet.new(occurrences, &{&1.class, &1.construct}) ==
             MapSet.new([
               {:direct_ecto, "Repo.preload"},
               {:direct_ecto, "Repo.preload!"},
               {:direct_ecto, "Repo.reload"},
               {:direct_ecto, "Repo.reload!"},
               {:direct_ecto, "Repo.all_by"}
             ])
  end

  test "ignores non-database receivers rooted at the current module" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load(id) do
              __MODULE__.TokenCache.fetch(id)
              OfficeGraph.Repo.query!("SELECT 1", [])
            end
          end
          """
        }
      ])

    assert occurrence.construct == "Repo.query!"
  end

  test "classifies SQL-bearing migration constructs" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "priv/repo/migrations/20260728000000_example.exs",
          source: """
          defmodule ExampleMigration do
            use Ecto.Migration

            def change do
              execute("ALTER TABLE examples ADD COLUMN code text")
              create index(:examples, [:code], where: "deleted_at IS NULL")
              create constraint(:examples, :positive_score, check: "score > 0")
              alter table(:examples), do: add(:id, :uuid, default: fragment("uuidv7()"))
            end
          end
          """
        }
      ])

    assert MapSet.new(occurrences, &{&1.class, &1.construct}) ==
             MapSet.new([
               {:raw_sql, "migration.execute"},
               {:raw_sql, "migration.where"},
               {:raw_sql, "migration.check"},
               {:raw_sql, "fragment"}
             ])
  end

  test "classifies nonliteral migration execute calls conservatively" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "priv/repo/migrations/20260728000000_example.exs",
          source: """
          defmodule ExampleMigration do
            use Ecto.Migration

            @statement "ALTER TABLE examples ADD COLUMN code text"

            def change do
              execute(@statement)
              execute("ALTER TABLE " <> "examples ADD COLUMN label text")
            end
          end
          """
        }
      ])

    assert Enum.count(occurrences, &(&1.construct == "migration.execute")) == 2
    assert Enum.all?(occurrences, &(&1.class == :raw_sql))
  end

  test "classifies migration data insertion and MD5-derived identifiers" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "priv/repo/migrations/20260728000000_example.exs",
          source: """
          defmodule ExampleMigration do
            use Ecto.Migration

            def change do
              execute("INSERT INTO examples (id) VALUES (gen_random_uuid())")
              execute("SELECT md5('example')")
              insert(:examples, %{id: "application-owned"})
            end
          end
          """
        }
      ])

    assert Enum.count(occurrences, &(&1.construct == "migration.insert")) == 2
    assert Enum.any?(occurrences, &(&1.construct == "migration.execute"))
    assert Enum.any?(occurrences, &(&1.construct == "migration.md5"))
  end

  test "classifies a tracked SQL file as one raw SQL occurrence" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{path: "priv/repo/report.sql", source: "SELECT count(*) FROM examples;\n"}
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "sql_file"
    assert occurrence.line == 1
  end

  test "excludes dependency and build artifacts" do
    sources =
      for path <- [
            "deps/example/lib/example.ex",
            "_build/test/lib/example.ex",
            "assets/node_modules/example/index.ex"
          ] do
        %{path: path, source: "OfficeGraph.Repo.query!(\"SELECT 1\", [])"}
      end

    assert DatabaseBoundaryScanner.scan_sources(sources) == []
  end

  test "fingerprints remain stable when only source line positions change" do
    source = """
    defmodule Example do
      def load, do: OfficeGraph.Repo.query!("SELECT 1", [])
    end
    """

    [first] =
      DatabaseBoundaryScanner.scan_sources([%{path: "lib/example.ex", source: source}])

    [moved] =
      DatabaseBoundaryScanner.scan_sources([
        %{path: "lib/example.ex", source: "\n\n" <> source}
      ])

    assert first.line != moved.line
    assert first.fingerprint == moved.fingerprint
  end

  test "identical constructs in one function receive distinct stable ordinals" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load do
              OfficeGraph.Repo.query!("SELECT 1", [])
              OfficeGraph.Repo.query!("SELECT 1", [])
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, & &1.ordinal) == [1, 2]
    assert occurrences |> Enum.map(& &1.fingerprint) |> Enum.uniq() |> length() == 2
  end

  test "repository scans inspect only Git-tracked eligible sources" do
    with_git_repository(fn root ->
      tracked_path = Path.join(root, "lib/tracked.ex")
      untracked_path = Path.join(root, "lib/untracked.ex")
      File.mkdir_p!(Path.dirname(tracked_path))
      File.write!(tracked_path, "OfficeGraph.Repo.query!(\"SELECT 1\", [])")
      File.write!(untracked_path, "OfficeGraph.Repo.query!(\"SELECT 2\", [])")
      {_output, 0} = System.cmd("git", ["add", "lib/tracked.ex"], cd: root)

      [occurrence] = DatabaseBoundaryScanner.scan_repository(root)

      assert occurrence.path == "lib/tracked.ex"
    end)
  end

  test "repository scans inspect tracked Elixir sources across the project" do
    with_git_repository(fn root ->
      paths = [
        "config/runtime.exs",
        "credo_checks/project_boundary.ex",
        "docs/example.ex",
        "mix.exs"
      ]

      Enum.each(paths, fn path ->
        full_path = Path.join(root, path)
        File.mkdir_p!(Path.dirname(full_path))
        File.write!(full_path, "OfficeGraph.Repo.query!(\"SELECT 1\", [])")
      end)

      {_output, 0} = System.cmd("git", ["add", "--" | paths], cd: root)

      assert DatabaseBoundaryScanner.scan_repository(root)
             |> Enum.map(& &1.path)
             |> MapSet.new() == MapSet.new(paths)
    end)
  end

  test "repository scans ignore tracked files deleted from the working tree" do
    with_git_repository(fn root ->
      tracked_path = Path.join(root, "lib/deleted.ex")
      File.mkdir_p!(Path.dirname(tracked_path))
      File.write!(tracked_path, "OfficeGraph.Repo.query!(\"SELECT 1\", [])")
      {_output, 0} = System.cmd("git", ["add", "lib/deleted.ex"], cd: root)
      File.rm!(tracked_path)

      assert DatabaseBoundaryScanner.scan_repository(root) == []
    end)
  end

  test "repository scans leave tracked files and Git state unchanged" do
    with_git_repository(fn root ->
      tracked_path = Path.join(root, "lib/tracked.ex")
      File.mkdir_p!(Path.dirname(tracked_path))
      File.write!(tracked_path, "OfficeGraph.Repo.query!(\"SELECT 1\", [])")
      {_output, 0} = System.cmd("git", ["add", "lib/tracked.ex"], cd: root)

      before_source = File.read!(tracked_path)
      {before_status, 0} = System.cmd("git", ["status", "--porcelain=v1"], cd: root)

      DatabaseBoundaryScanner.scan_repository(root)

      assert File.read!(tracked_path) == before_source
      assert System.cmd("git", ["status", "--porcelain=v1"], cd: root) == {before_status, 0}
    end)
  end

  defp with_git_repository(test) do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_database_boundary_scanner_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {_output, 0} = System.cmd("git", ["init", "--quiet"], cd: root)
    test.(root)
  end
end
