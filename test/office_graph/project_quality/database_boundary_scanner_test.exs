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
    refute Map.has_key?(occurrence, :approval)
  end

  test "binds approval fingerprints to the resolved database receiver" do
    fingerprint = fn module_setup, call ->
      [occurrence] =
        DatabaseBoundaryScanner.scan_sources([
          %{
            path: "lib/example.ex",
            source: """
            defmodule Example do
              #{module_setup}

              def load, do: #{call}("SELECT 1", [])
            end
            """
          }
        ])

      occurrence.fingerprint
    end

    office_graph_alias =
      fingerprint.("alias OfficeGraph.Repo, as: Target", "Target.query!")

    top_level_alias = fingerprint.("alias Repo, as: Target", "Target.query!")
    fully_qualified = fingerprint.("", "OfficeGraph.Repo.query!")

    assert office_graph_alias == fully_qualified
    refute office_graph_alias == top_level_alias
  end

  test "classifies SQL embedded in DBConnection query structs" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            alias DBConnection, as: Connection
            alias Postgrex.Query, as: Query
            import DBConnection, only: [prepare_execute: 4]

            def run(connection, dynamic_statement, prepared_query) do
              DBConnection.execute(
                connection,
                %Postgrex.Query{statement: "SELECT 1"},
                [],
                []
              )

              Connection.prepare_execute(
                connection,
                %Query{statement: "SELECT 2"},
                [],
                []
              )

              prepare_execute(
                connection,
                %Postgrex.TextQuery{statement: dynamic_statement},
                [],
                []
              )

              DBConnection.execute(connection, prepared_query, [], [])
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, fn occurrence ->
             {occurrence.construct, Map.get(occurrence, :approval)}
           end) == [
             {"DBConnection.execute", nil},
             {"DBConnection.prepare_execute", nil},
             {"DBConnection.prepare_execute", :unresolved_sql},
             {"DBConnection.execute", :unresolved_sql}
           ]

    fingerprints =
      Enum.map(["SELECT 1", "SELECT 2"], fn statement ->
        [occurrence] =
          DatabaseBoundaryScanner.scan_sources([
            %{
              path: "lib/example.ex",
              source: """
              defmodule Example do
                def run(connection) do
                  DBConnection.execute(
                    connection,
                    %Postgrex.Query{statement: #{inspect(statement)}},
                    [],
                    []
                  )
                end
              end
              """
            }
          ])

        occurrence.fingerprint
      end)

    assert Enum.uniq(fingerprints) == fingerprints
  end

  test "classifies repository SQL calls through module-atom receivers" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load do
              :"Elixir.OfficeGraph.Repo".query!("DELETE FROM events", [])
            end
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.function == "load/0"
    assert occurrence.line == 3
  end

  test "resolves database receivers built by literal String atom conversions" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            alias String, as: AtomParser

            def load do
              String.to_existing_atom("Elixir.OfficeGraph.Repo").query!("DELETE FROM events", [])

              AtomParser.to_atom("Elixir.Ecto.Adapters.SQL").query!(
                OfficeGraph.Repo,
                "DELETE FROM archived_events",
                []
              )

              String.to_existing_atom("Elixir.Example.NotARepo").query!("not database SQL", [])
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.function, &1.line}) == [
             {:raw_sql, "Repo.query!", "load/0", 5},
             {:raw_sql, "Ecto.Adapters.SQL.query!", "load/0", 7}
           ]
  end

  test "fails closed for runtime String atom conversion receivers" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load(module_name) do
              String.to_existing_atom(module_name).query!("DELETE FROM events", [])
            end
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.function == "load/1"
    assert occurrence.line == 3
  end

  test "recognizes database module atoms in static helper and generator values" do
    [
      """
      repo = :"Elixir.OfficeGraph.Repo"
      run_query(repo, "DELETE FROM events")
      """,
      """
      for repo <- [Example.NotARepo, :"Elixir.OfficeGraph.Repo"] do
        repo.query!("DELETE FROM events", [])
      end
      """
    ]
    |> Enum.each(fn load_body ->
      [occurrence] =
        DatabaseBoundaryScanner.scan_sources([
          %{
            path: "lib/example.ex",
            source: """
            defmodule Example do
              def load do
                #{load_body}
              end

              defp run_query(repo, sql), do: repo.query!(sql, [])
            end
            """
          }
        ])

      assert occurrence.class == :raw_sql
      assert occurrence.construct == "Repo.query!"
      refute Map.has_key?(occurrence, :approval)
    end)
  end

  test "fails closed for repository SQL exposed through defdelegate" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            defdelegate query(sql, params), to: OfficeGraph.Repo, as: :query!

            def load, do: query("DELETE FROM events", [])
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.function == "query/2"
    assert occurrence.line == 2
    assert occurrence.approval == :unresolved_sql
  end

  test "classifies statically targeted apply calls through supported apply entrypoints" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load(connection) do
              apply(OfficeGraph.Repo, :query!, ["SELECT 1", []])
              Kernel.apply(Ecto.Adapters.SQL, :query, [OfficeGraph.Repo, "SELECT 2", []])
              :erlang.apply(Postgrex, :query, [connection, "SELECT 3", []])
              Example.apply(OfficeGraph.Repo, :query!, ["SELECT 4", []])
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.function, &1.line}) == [
             {"Repo.query!", "load/1", 3},
             {"Ecto.Adapters.SQL.query", "load/1", 4},
             {"Postgrex.query", "load/1", 5}
           ]

    assert Enum.all?(occurrences, &(not Map.has_key?(&1, :approval)))
  end

  test "rejects unresolved apply calls targeting database modules" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            alias OfficeGraph.Repo

            def dispatch_repo(operation, arguments),
              do: apply(Repo, operation, arguments)

            def dispatch_sql(arguments),
              do: Kernel.apply(Ecto.Adapters.SQL, :query, arguments)

            def dispatch_postgrex(operation, arguments),
              do: :erlang.apply(Postgrex, operation, arguments)

            def dispatch_multi(operation, arguments),
              do: apply(Ecto.Multi, operation, arguments)
          end
          """
        }
      ])

    assert Enum.map(occurrences, fn occurrence ->
             {
               occurrence.class,
               occurrence.construct,
               occurrence.function,
               Map.get(occurrence, :approval)
             }
           end) == [
             {:raw_sql, "Repo.apply", "dispatch_repo/2", :unresolved_sql},
             {:raw_sql, "Ecto.Adapters.SQL.query", "dispatch_sql/1", :unresolved_sql},
             {:raw_sql, "Postgrex.apply", "dispatch_postgrex/2", :unresolved_sql},
             {:direct_ecto, "Ecto.Multi.apply", "dispatch_multi/2", nil}
           ]
  end

  test "does not treat dynamic Ecto.Query builder dispatch as database access" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def dispatch_query(operation, arguments),
              do: apply(Ecto.Query, operation, arguments)

            def dispatch_multi(operation, arguments),
              do: apply(Ecto.Multi, operation, arguments)
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.function}) == [
             {:direct_ecto, "Ecto.Multi.apply", "dispatch_multi/2"}
           ]
  end

  test "preserves apply calls explicitly imported from a non-Kernel module" do
    assert DatabaseBoundaryScanner.scan_sources([
             %{
               path: "lib/example.ex",
               source: """
               defmodule Example do
                 import Kernel, except: [apply: 3]
                 import Example.CustomApply, only: [apply: 3]

                 def load do
                   apply(OfficeGraph.Repo, :query!, ["SELECT 1", []])
                 end
               end
               """
             }
           ]) == []
  end

  test "marks unresolved raw SQL parameters as unapprovable" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            alias OfficeGraph.Repo

            def run, do: query("SELECT 1")
            defp query(sql), do: Repo.query!(sql)
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.approval == :unresolved_sql
  end

  test "accepts literal SQL interpolation without accepting runtime interpolation" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: ~S'''
          defmodule Example do
            alias OfficeGraph.Repo

            def static, do: Repo.query!("SELECT #{1}")
            def dynamic(value), do: Repo.query!("SELECT #{value}")
          end
          '''
        }
      ])

    assert Enum.map(occurrences, &{&1.function, Map.get(&1, :approval)}) == [
             {"static/0", nil},
             {"dynamic/1", :unresolved_sql}
           ]
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
              Ecto.Adapters.SQL.query_many(OfficeGraph.Repo, "SELECT 1; SELECT 2", [])
              Ecto.Adapters.SQL.query_many!(OfficeGraph.Repo, "SELECT 3; SELECT 4", [])
              Ecto.Adapters.SQL.stream(OfficeGraph.Repo, "SELECT 5", [])
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
               {:raw_sql, "Ecto.Adapters.SQL.query_many"},
               {:raw_sql, "Ecto.Adapters.SQL.query_many!"},
               {:raw_sql, "Ecto.Adapters.SQL.stream"},
               {:raw_sql, "Postgrex.query"},
               {:raw_sql, "fragment"},
               {:raw_sql, "unsafe_fragment"}
             ])
  end

  test "classifies SQL-adapter query-many functions injected into repos as raw SQL" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load do
              OfficeGraph.Repo.query_many("SELECT 1; SELECT 2", [])
              OfficeGraph.Repo.query_many!("SELECT 3; SELECT 4", [])
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.line}) == [
             {:raw_sql, "Repo.query_many", 3},
             {:raw_sql, "Repo.query_many!", 4}
           ]

    assert Enum.all?(occurrences, &(not Map.has_key?(&1, :approval)))
  end

  test "classifies generated Ecto SQL explain calls as direct database access" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            alias Ecto.Adapters.SQL, as: SQL
            import Ecto.Adapters.SQL, only: [explain: 4]

            def inspect_query(query) do
              Ecto.Adapters.SQL.explain(OfficeGraph.Repo, :all, query)
              SQL.explain(OfficeGraph.Repo, :all, query, analyze: true)
              explain(OfficeGraph.Repo, :all, query, analyze: true)
              Example.SQL.explain(OfficeGraph.Repo, :all, query)
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.line}) == [
             {:direct_ecto, "Ecto.Adapters.SQL.explain", 6},
             {:direct_ecto, "Ecto.Adapters.SQL.explain", 7},
             {:direct_ecto, "Ecto.Adapters.SQL.explain", 8}
           ]
  end

  test "classifies SQL-adapter explain calls injected into repos" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def inspect_query(query) do
              OfficeGraph.Repo.explain(:all, query, analyze: true)
              apply(OfficeGraph.Repo, :explain, [:all, query, [analyze: true]])
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.line}) == [
             {:direct_ecto, "Repo.explain", 3},
             {:direct_ecto, "Repo.explain", 4}
           ]
  end

  test "classifies Ecto SQL adapter checkout as direct database access" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            alias Ecto.Adapters.SQL, as: SQL
            import Ecto.Adapters.SQL, only: [checkout: 3]

            def with_connection(meta, opts, callback) do
              Ecto.Adapters.SQL.checkout(meta, opts, callback)
              SQL.checkout(meta, opts, callback)
              checkout(meta, opts, callback)
              Example.SQL.checkout(meta, opts, callback)
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.line}) == [
             {:direct_ecto, "Ecto.Adapters.SQL.checkout", 6},
             {:direct_ecto, "Ecto.Adapters.SQL.checkout", 7},
             {:direct_ecto, "Ecto.Adapters.SQL.checkout", 8}
           ]
  end

  test "classifies explicit Ecto migration SQL APIs in external helpers" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example_migration_helper.ex",
          source: """
          defmodule ExampleMigrationHelper do
            alias Ecto.Migration, as: Migration
            import Ecto.Migration, only: [execute: 1, fragment: 1]

            def run do
              Ecto.Migration.execute("SELECT 1")
              Migration.execute("SELECT 2")
              execute("SELECT 3")
              Ecto.Migration.fragment("now()")
              Migration.fragment("clock_timestamp()")
              fragment("gen_random_uuid()")
              Example.Migration.execute("SELECT 4")
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.line}) == [
             {:raw_sql, "migration.execute", 6},
             {:raw_sql, "migration.execute", 7},
             {:raw_sql, "migration.execute", 8},
             {:raw_sql, "fragment", 9},
             {:raw_sql, "fragment", 10},
             {:raw_sql, "fragment", 11}
           ]

    assert Enum.all?(occurrences, &(not Map.has_key?(&1, :approval)))
  end

  test "classifies Ecto migration SQL APIs imported by use in external helpers" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example_migration_helper.ex",
          source: """
          defmodule ExampleMigrationHelper do
            alias Ecto.Migration, as: Migration
            use Migration

            def run do
              execute("SELECT 1")
              fragment("clock_timestamp()")
              repo().query!("DELETE FROM events", [])
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.line}) == [
             {:raw_sql, "migration.execute", 6},
             {:raw_sql, "fragment", 7},
             {:raw_sql, "Repo.query!", 8}
           ]
  end

  test "does not classify unqualified local fragment functions without an Ecto import" do
    assert [] ==
             DatabaseBoundaryScanner.scan_sources([
               %{
                 path: "lib/example.ex",
                 source: """
                 defmodule Example do
                   def fragment(value), do: value
                   def unsafe_fragment(value), do: value

                   def render do
                     fragment("display only")
                     unsafe_fragment("still not SQL")
                   end
                 end
                 """
               }
             ])
  end

  test "classifies fragments inside recognized Ecto query DSL calls without fragment imports" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            import Ecto.Query, only: [from: 2]

            def load(query) do
              from row in query,
                where: fragment("lower(?)", row.name) == "name"

              Ecto.Query.from(
                row in query,
                where: fragment("upper(?)", row.name) == "NAME"
              )
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.line}) == [
             {:raw_sql, "fragment", 6},
             {:raw_sql, "fragment", 10}
           ]

    assert Enum.all?(occurrences, &(not Map.has_key?(&1, :approval)))
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

  test "marks runtime SQL-shaping fragment helpers as unapprovable" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            import Ecto.Query.API

            def filter(field, value) do
              fragment("? IS NOT NULL", identifier(^field))
              fragment("? = 1", constant(^value))
              fragment("? IS NOT NULL", identifier("fixed_column"))
              fragment("? = ?", value, ^value)
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.line, Map.get(&1, :approval)}) == [
             {5, :unresolved_sql},
             {6, :unresolved_sql},
             {7, nil},
             {8, nil}
           ]
  end

  test "classifies SQL-bearing query helper options with value-sensitive fingerprints" do
    occurrences_by_lock =
      ["FOR UPDATE", "FOR SHARE"]
      |> Enum.map(fn lock_clause ->
        DatabaseBoundaryScanner.scan_sources([
          %{
            path: "lib/example.ex",
            source: """
            defmodule Example do
              import Ecto.Query

              defp locked_users do
                from user in "users",
                  hints: ["ONLY"],
                  lock: #{inspect(lock_clause)}
              end

              def load, do: OfficeGraph.Repo.all(locked_users())
            end
            """
          }
        ])
      end)

    assert Enum.map(List.first(occurrences_by_lock), fn occurrence ->
             {occurrence.class, occurrence.construct, occurrence.function, occurrence.line}
           end) == [
             {:raw_sql, "Ecto.Query.hints", "locked_users/0", 5},
             {:raw_sql, "Ecto.Query.lock", "locked_users/0", 5},
             {:direct_ecto, "Repo.all", "load/0", 10}
           ]

    lock_fingerprints =
      Enum.map(occurrences_by_lock, fn occurrences ->
        occurrences
        |> Enum.find(&(&1.construct == "Ecto.Query.lock"))
        |> Map.fetch!(:fingerprint)
      end)

    assert Enum.uniq(lock_fingerprints) == lock_fingerprints
  end

  test "classifies SQL-bearing Ecto.Query options across aliases and imports" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            alias Ecto.Query, as: Query
            import Ecto.Query, only: [join: 5, lock: 2]

            def build(query) do
              Query.from("users", hints: ["FULL"], lock: "FOR UPDATE")
              join(query, :inner, [], "comments", hints: ["USE INDEX comments_created_at"])
              lock(query, "FOR SHARE")
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.function, &1.line}) == [
             {:raw_sql, "Ecto.Query.hints", "build/1", 6},
             {:raw_sql, "Ecto.Query.lock", "build/1", 6},
             {:raw_sql, "Ecto.Query.hints", "build/1", 7},
             {:raw_sql, "Ecto.Query.lock", "build/1", 8}
           ]
  end

  test "does not classify generated or empty Ecto.Query lock and hint values as authored SQL" do
    assert [] ==
             DatabaseBoundaryScanner.scan_sources([
               %{
                 path: "lib/example.ex",
                 source: """
                 defmodule Example do
                   import Ecto.Query

                   def build(query) do
                     from("users", hints: [], lock: true)
                     lock(query, false)
                   end
                 end
                 """
               }
             ])
  end

  test "classifies every Postgrex SQL preparation and execution spelling" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            alias Postgrex, as: Pg
            import Postgrex, only: [prepare_execute: 5]

            def run(connection, query) do
              Postgrex.prepare(connection, "one", "SELECT 1")
              Pg.prepare!(connection, "two", "SELECT 2")
              prepare_execute(connection, "three", "SELECT 3", [], [])
              Postgrex.prepare_execute!(connection, "four", "SELECT 4", [])
              Pg.execute(connection, query, [])
              Postgrex.execute!(connection, query, [])
              Pg.stream(connection, "SELECT 5", [])
              Example.Postgrex.prepare(connection, "not-sql", "ignored")
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.line}) == [
             {"Postgrex.prepare", 6},
             {"Postgrex.prepare!", 7},
             {"Postgrex.prepare_execute", 8},
             {"Postgrex.prepare_execute!", 9},
             {"Postgrex.execute", 10},
             {"Postgrex.execute!", 11},
             {"Postgrex.stream", 12}
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

  test "classifies Ecto.Multi reads without matching unrelated receivers" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            alias Ecto.Multi, as: DatabaseMulti

            def load(multi, query) do
              Ecto.Multi.all(multi, :all, query)
              DatabaseMulti.one(multi, :one, query)
              DatabaseMulti.exists?(multi, :exists, query)
              OfficeGraph.Cache.all(multi, :all, query)
              OfficeGraph.Cache.one(multi, :one, query)
              OfficeGraph.Cache.exists?(multi, :exists, query)
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.line}) == [
             {:direct_ecto, "Ecto.Multi.all", 5},
             {:direct_ecto, "Ecto.Multi.one", 6},
             {:direct_ecto, "Ecto.Multi.exists?", 7}
           ]
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

  test "classifies repository connection control without matching unrelated receivers" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            alias OfficeGraph.Repo
            alias OfficeGraph.Repo, as: Database

            def run(fun) do
              Repo.checkout(fun)
              Database.checkout(fun, timeout: 1_000)
              OfficeGraph.Repo.rollback(:cancelled)
              Database.rollback(:cancelled)
              Repo.disconnect_all(1_000)
              Database.disconnect_all(1_000, log: false)
              Ecto.Adapters.SQL.disconnect_all(Repo, 1_000)
              OfficeGraph.Cache.checkout(fun)
              OfficeGraph.Cache.rollback(:cancelled)
              OfficeGraph.Cache.disconnect_all(1_000)
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.line}) == [
             {:direct_ecto, "Repo.checkout", 6},
             {:direct_ecto, "Repo.checkout", 7},
             {:direct_ecto, "Repo.rollback", 8},
             {:direct_ecto, "Repo.rollback", 9},
             {:direct_ecto, "Repo.disconnect_all", 10},
             {:direct_ecto, "Repo.disconnect_all", 11},
             {:direct_ecto, "Ecto.Adapters.SQL.disconnect_all", 12}
           ]
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
              create index(:examples, [:code],
                options: "fillfactor = 70",
                where: "deleted_at IS NULL"
              )

              create constraint(:examples, :positive_score, check: "score > 0")

              create constraint(:examples, :non_overlapping_score,
                exclude: "gist (int4range(min_score, max_score, '[]') WITH &&)"
              )

              alter table(:examples), do: add(:id, :uuid, default: fragment("uuidv7()"))
            end
          end
          """
        }
      ])

    assert MapSet.new(occurrences, &{&1.class, &1.construct}) ==
             MapSet.new([
               {:raw_sql, "migration.execute"},
               {:raw_sql, "migration.options"},
               {:raw_sql, "migration.where"},
               {:raw_sql, "migration.check"},
               {:raw_sql, "migration.exclude"},
               {:raw_sql, "fragment"}
             ])
  end

  test "classifies SQL options in qualified and aliased migration constructs" do
    [
      "create Ecto.Migration.index(:items, [:id], where: \"deleted_at IS NULL\")",
      "Ecto.Migration.create(Migration.index(:items, [:id], where: \"deleted_at IS NULL\"))"
    ]
    |> Enum.each(fn statement ->
      [occurrence] =
        DatabaseBoundaryScanner.scan_sources([
          %{
            path: "priv/repo/migrations/20260803000000_example.exs",
            source: """
            defmodule ExampleMigration do
              use Ecto.Migration
              alias Ecto.Migration, as: Migration

              def change do
                #{statement}
              end
            end
            """
          }
        ])

      assert occurrence.class == :raw_sql
      assert occurrence.construct == "migration.where"
      assert occurrence.function == "change/0"
    end)
  end

  test "classifies SQL-bearing migration options through static apply entrypoints" do
    [
      ~s'apply(Ecto.Migration, :create, [index(:items, [:id], where: "deleted_at IS NULL")])',
      ~s'Kernel.apply(Ecto.Migration, :create, [index(:items, [:id], where: "deleted_at IS NULL")])',
      ~s':erlang.apply(Ecto.Migration, :create, [index(:items, [:id], where: "deleted_at IS NULL")])'
    ]
    |> Enum.each(fn statement ->
      [occurrence] =
        DatabaseBoundaryScanner.scan_sources([
          %{
            path: "priv/repo/migrations/20260804000000_example.exs",
            source: """
            defmodule ExampleMigration do
              use Ecto.Migration

              def change do
                #{statement}
              end
            end
            """
          }
        ])

      assert occurrence.class == :raw_sql
      assert occurrence.construct == "migration.where"
      assert occurrence.function == "change/0"
    end)
  end

  test "classifies SQL options in piped migration constructs" do
    fingerprints =
      ["deleted_at IS NULL", "archived_at IS NULL"]
      |> Enum.map(fn predicate ->
        occurrences =
          DatabaseBoundaryScanner.scan_sources([
            %{
              path: "priv/repo/migrations/20260804000000_example.exs",
              source: """
              defmodule ExampleMigration do
                use Ecto.Migration
                alias Ecto.Migration, as: Migration

                def change do
                  index(:items, [:id], where: #{inspect(predicate)}) |> create()

                  Ecto.Migration.table(:events, options: "PARTITION BY RANGE (inserted_at)")
                  |> Migration.create() do
                    add :inserted_at, :utc_datetime_usec
                  end
                end
              end
              """
            }
          ])

        assert Enum.map(occurrences, &{&1.class, &1.construct, &1.function}) == [
                 {:raw_sql, "migration.where", "change/0"},
                 {:raw_sql, "migration.options", "change/0"}
               ]

        Enum.map(occurrences, & &1.fingerprint)
      end)

    [[first_where, first_options], [second_where, second_options]] = fingerprints

    assert first_where != second_where
    assert first_options == second_options
  end

  test "classifies raw table creation options and modifiers" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "priv/repo/migrations/20260728000000_example.exs",
          source: """
          defmodule ExampleMigration do
            use Ecto.Migration

            def change do
              create table(:events,
                       modifiers: "UNLOGGED",
                       options: "PARTITION BY RANGE (inserted_at)"
                     )
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct}) == [
             {:raw_sql, "migration.modifiers"},
             {:raw_sql, "migration.options"}
           ]
  end

  test "classifies raw table options on block-form migration creation" do
    [
      """
      create table(:events,
               modifiers: "UNLOGGED",
               options: "PARTITION BY RANGE (inserted_at)"
             ) do
        add :inserted_at, :utc_datetime_usec
      end
      """,
      """
      Ecto.Migration.create(
        Ecto.Migration.table(:events,
          modifiers: "UNLOGGED",
          options: "PARTITION BY RANGE (inserted_at)"
        )
      ) do
        Ecto.Migration.add :inserted_at, :utc_datetime_usec
      end
      """
    ]
    |> Enum.each(fn statement ->
      occurrences =
        DatabaseBoundaryScanner.scan_sources([
          %{
            path: "priv/repo/migrations/20260728000000_example.exs",
            source: """
            defmodule ExampleMigration do
              use Ecto.Migration

              def change do
                #{statement}
              end
            end
            """
          }
        ])

      assert Enum.map(occurrences, &{&1.class, &1.construct}) == [
               {:raw_sql, "migration.modifiers"},
               {:raw_sql, "migration.options"}
             ]
    end)
  end

  test "classifies generated column expressions within migration table blocks" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "priv/repo/migrations/20260804000000_example.exs",
          source: """
          defmodule ExampleMigration do
            use Ecto.Migration

            @search_expression "ALWAYS AS (lower(name)) STORED"

            def change do
              create table(:users) do
                add :search_name, :text, generated: @search_expression
              end

              runtime_expression = System.fetch_env!("SEARCH_EXPRESSION")

              alter table(:users) do
                modify :search_key, :text, generated: runtime_expression
              end

              Ecto.Migration.alter(Ecto.Migration.table(:accounts)) do
                Ecto.Migration.add :search_name, :text,
                  generated: "ALWAYS AS (lower(name)) STORED"
              end
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, fn occurrence ->
             {occurrence.construct, occurrence.line, Map.get(occurrence, :approval)}
           end) == [
             {"migration.generated", 8, nil},
             {"migration.generated", 14, :unresolved_sql},
             {"migration.generated", 18, nil}
           ]
  end

  test "binds generated-column fingerprints to the enclosing table and column" do
    scan = fn table, column, expression ->
      [occurrence] =
        DatabaseBoundaryScanner.scan_sources([
          %{
            path: "priv/repo/migrations/20260804000000_example.exs",
            source: """
            defmodule ExampleMigration do
              use Ecto.Migration

              def change do
                alter table(#{inspect(table)}) do
                  add #{inspect(column)}, :text, generated: #{inspect(expression)}
                end
              end
            end
            """
          }
        ])

      occurrence.fingerprint
    end

    baseline = scan.(:users, :search_name, "ALWAYS AS (lower(name)) STORED")

    refute scan.(:accounts, :search_name, "ALWAYS AS (lower(name)) STORED") == baseline
    refute scan.(:users, :search_key, "ALWAYS AS (lower(name)) STORED") == baseline
    refute scan.(:users, :search_name, "ALWAYS AS (upper(name)) STORED") == baseline
  end

  test "classifies SQL-bearing migration constructs returned from reachable local helpers" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "priv/repo/migrations/20260728000000_example.exs",
          source: """
          defmodule ExampleMigration do
            use Ecto.Migration

            def change do
              create active_index("deleted_at IS NULL")
              create partitioned_table()
            end

            defp active_index(predicate),
              do: index(:items, [:status], where: predicate)

            defp partitioned_table, do: table_definition()

            defp table_definition,
              do: table(:events, options: "PARTITION BY RANGE (inserted_at)")

            defp unused_index,
              do: index(:items, [:archived_at], where: "archived_at IS NULL")
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.function, &1.line}) == [
             {:raw_sql, "migration.where", "change/0", 5},
             {:raw_sql, "migration.options", "change/0", 6}
           ]

    refute Map.has_key?(
             Enum.find(occurrences, &(&1.construct == "migration.where")),
             :approval
           )
  end

  test "classifies SQL options only from the statically reachable guarded helper clause" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "priv/repo/migrations/20260728000000_example.exs",
          source: """
          defmodule ExampleMigration do
            use Ecto.Migration

            def change do
              create guarded_index(:active)
              create guarded_index(:archived)
            end

            defp guarded_index(mode) when mode == :archived,
              do: index(:items, [:status], where: "archived_at IS NULL")

            defp guarded_index(_mode), do: index(:items, [:status])
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.function, &1.line}) == [
             {"migration.where", "change/0", 6}
           ]
  end

  test "classifies SQL options expanded from reachable local migration macros" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "priv/repo/migrations/20260728000000_example.exs",
          source: """
          defmodule ExampleMigration do
            use Ecto.Migration

            def change do
              create active_index("deleted_at IS NULL")
              create archived_index("archived_at IS NULL")
            end

            defmacrop active_index(predicate) do
              quote do
                index(:items, [:status], where: unquote(predicate))
              end
            end

            defmacrop archived_index(predicate) do
              quote bind_quoted: [predicate: predicate] do
                index(:items, [:archived_at], where: predicate)
              end
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.function, &1.line}) == [
             {"migration.where", "change/0", 5},
             {"migration.where", "change/0", 6}
           ]

    assert Enum.all?(occurrences, &(not Map.has_key?(&1, :approval)))
  end

  test "does not classify database calls stored only as quoted data" do
    assert [] ==
             DatabaseBoundaryScanner.scan_sources([
               %{
                 path: "lib/example.ex",
                 source: """
                 defmodule Example do
                   def ast do
                     quote do
                       OfficeGraph.Repo.query!("SELECT 1", [])
                     end
                   end
                 end
                 """
               }
             ])
  end

  test "classifies database calls evaluated while quoted data is built" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def unquoted do
              quote do
                unquote(OfficeGraph.Repo.query!("DELETE FROM events", []))
              end
            end

            def bound do
              quote bind_quoted: [
                      rows: OfficeGraph.Repo.query!("SELECT 1", [])
                    ] do
                rows
              end
            end

            def inert do
              quote unquote: false do
                unquote(OfficeGraph.Repo.query!("DELETE FROM ignored", []))
              end
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.function, &1.line}) == [
             {:raw_sql, "Repo.query!", "unquoted/0", 4},
             {:raw_sql, "Repo.query!", "bound/0", 10}
           ]
  end

  test "classifies database calls emitted by invoked local macros" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            defmacrop run_query do
              quote do
                OfficeGraph.Repo.query!("SELECT 1", [])
              end
            end

            def load, do: run_query()
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.function == "load/0"
  end

  test "fails closed for database calls emitted by public repository macros" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example/sql_macros.ex",
          source: """
          defmodule Example.SqlMacros do
            defmacro run(sql) do
              quote do
                OfficeGraph.Repo.query!(unquote(sql), [])
              end
            end
          end
          """
        },
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            require Example.SqlMacros

            def load, do: Example.SqlMacros.run("DELETE FROM events")
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.path == "lib/example/sql_macros.ex"
    assert occurrence.function == "run/1"
    assert occurrence.approval == :unresolved_sql
  end

  test "classifies qualified migration execution calls" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "priv/repo/migrations/20260728000000_example.exs",
          source: """
          defmodule ExampleMigration do
            use Ecto.Migration
            alias Ecto.Migration, as: Migration

            def change do
              Ecto.Migration.execute("INSERT INTO examples (id) VALUES (1)")
              Migration.execute("INSERT INTO examples (id) VALUES (2)")
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.line}) == [
             {"migration.execute", 6},
             {"migration.execute", 7}
           ]
  end

  test "classifies repository SQL through migration repo receivers" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "priv/repo/migrations/20260728000000_example.exs",
          source: """
          defmodule ExampleMigration do
            use Ecto.Migration
            alias Ecto.Migration, as: Migration

            def change do
              repo().query!("DELETE FROM events", [])
              Migration.repo().query!("DELETE FROM archived_events", [])
              Ecto.Migration.repo().query!("DELETE FROM deleted_events", [])
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.line}) == [
             {:raw_sql, "Repo.query!", 6},
             {:raw_sql, "Repo.query!", 7},
             {:raw_sql, "Repo.query!", 8}
           ]
  end

  test "classifies qualified migration fragments" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "priv/repo/migrations/20260728000000_example.exs",
          source: """
          defmodule ExampleMigration do
            use Ecto.Migration
            alias Ecto.Migration, as: Migration

            def change do
              Ecto.Migration.fragment("uuidv7()")
              Migration.fragment("now()")
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.line}) == [
             {:raw_sql, "fragment", 6},
             {:raw_sql, "fragment", 7}
           ]
  end

  test "classifies module attribute expressions used by SQL-bearing migration constructs" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "priv/repo/migrations/20260728000000_example.exs",
          source: """
          defmodule ExampleMigration do
            use Ecto.Migration

            @predicate "md5(name) " <> "IS NOT NULL"

            def change do
              create index(:examples, [:name], where: @predicate)
              create constraint(:examples, :valid_name, check: @predicate)
            end
          end
          """
        }
      ])

    assert MapSet.new(occurrences, &{&1.class, &1.construct}) ==
             MapSet.new([
               {:raw_sql, "migration.where"},
               {:raw_sql, "migration.check"}
             ])

    changed_occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "priv/repo/migrations/20260728000000_example.exs",
          source: """
          defmodule ExampleMigration do
            use Ecto.Migration

            @predicate "length(name) " <> "> 0"

            def change do
              create index(:examples, [:name], where: @predicate)
              create constraint(:examples, :valid_name, check: @predicate)
            end
          end
          """
        }
      ])

    assert MapSet.new(changed_occurrences, &{&1.class, &1.construct}) ==
             MapSet.new([
               {:raw_sql, "migration.where"},
               {:raw_sql, "migration.check"}
             ])

    refute Map.new(occurrences, &{&1.construct, &1.fingerprint}) ==
             Map.new(changed_occurrences, &{&1.construct, &1.fingerprint})
  end

  test "classifies SQL-bearing migration options stored in a local binding" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "priv/repo/migrations/20260728000000_example.exs",
          source: """
          defmodule ExampleMigration do
            use Ecto.Migration

            def change do
              options = [where: "deleted_at IS NULL"]
              create index(:examples, [:email], options)
            end
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "migration.where"
    assert occurrence.function == "change/0"
  end

  test "binds migration option fingerprints to recursively resolved local SQL values" do
    fingerprints =
      ["deleted_at IS NULL", "archived_at IS NULL"]
      |> Enum.map(fn predicate ->
        [occurrence] =
          DatabaseBoundaryScanner.scan_sources([
            %{
              path: "priv/repo/migrations/20260728000000_example.exs",
              source: """
              defmodule ExampleMigration do
                use Ecto.Migration

                def change do
                  predicate = #{inspect(predicate)}
                  options = [where: predicate]
                  create index(:examples, [:email], options)
                end
              end
              """
            }
          ])

        assert occurrence.construct == "migration.where"
        occurrence.fingerprint
      end)

    assert Enum.uniq(fingerprints) == fingerprints
  end

  test "captures local SQL values when a migration option binding is assigned" do
    fingerprints =
      ["archived_at IS NULL", "status = 'active'"]
      |> Enum.map(fn later_predicate ->
        [occurrence] =
          DatabaseBoundaryScanner.scan_sources([
            %{
              path: "priv/repo/migrations/20260728000000_example.exs",
              source: """
              defmodule ExampleMigration do
                use Ecto.Migration

                def change do
                  predicate = "deleted_at IS NULL"
                  options = [where: predicate]
                  predicate = #{inspect(later_predicate)}
                  create index(:examples, [:email], options)
                end
              end
              """
            }
          ])

        assert occurrence.construct == "migration.where"
        occurrence.fingerprint
      end)

    assert length(Enum.uniq(fingerprints)) == 1
  end

  test "binds migration option fingerprints to locally bound DDL targets" do
    fingerprints =
      [
        {:examples, [:email]},
        {:archived_examples, [:email]},
        {:examples, [:code]}
      ]
      |> Enum.map(fn {target, columns} ->
        [occurrence] =
          DatabaseBoundaryScanner.scan_sources([
            %{
              path: "priv/repo/migrations/20260728000000_example.exs",
              source: """
              defmodule ExampleMigration do
                use Ecto.Migration

                def change do
                  target = #{inspect(target)}
                  columns = #{inspect(columns)}
                  create index(target, columns, where: "deleted_at IS NULL")
                end
              end
              """
            }
          ])

        assert occurrence.construct == "migration.where"
        occurrence.fingerprint
      end)

    assert Enum.uniq(fingerprints) == fingerprints
  end

  test "binds direct SQL fingerprints to recursively resolved local values" do
    [
      {"lib/example.ex", "OfficeGraph.Repo.query!(statement, [])", "Repo.query!"},
      {"priv/repo/migrations/20260728000000_example.exs", "execute(statement)",
       "migration.execute"}
    ]
    |> Enum.each(fn {path, call, construct} ->
      fingerprints =
        ["SELECT 1", "SELECT 2"]
        |> Enum.map(fn statement ->
          [occurrence] =
            DatabaseBoundaryScanner.scan_sources([
              %{
                path: path,
                source: """
                defmodule Example do
                  def load do
                    statement = #{inspect(statement)}
                    #{call}
                  end
                end
                """
              }
            ])

          assert occurrence.construct == construct
          occurrence.fingerprint
        end)

      assert Enum.uniq(fingerprints) == fingerprints
    end)
  end

  test "binds destructured SQL values into direct-call fingerprints" do
    fingerprints =
      ["SELECT 1", "SELECT 2"]
      |> Enum.map(fn statement ->
        [occurrence] =
          DatabaseBoundaryScanner.scan_sources([
            %{
              path: "lib/example.ex",
              source: """
              defmodule Example do
                def load do
                  {statement, params} = {#{inspect(statement)}, []}
                  OfficeGraph.Repo.query!(statement, params)
                end
              end
              """
            }
          ])

        assert occurrence.construct == "Repo.query!"
        occurrence.fingerprint
      end)

    assert Enum.uniq(fingerprints) == fingerprints
  end

  test "binds both sides of nested match patterns into SQL fingerprints" do
    fingerprints =
      ["SELECT 1", "SELECT 2"]
      |> Enum.map(fn statement ->
        [occurrence] =
          DatabaseBoundaryScanner.scan_sources([
            %{
              path: "lib/example.ex",
              source: """
              defmodule Example do
                def load do
                  ({:ok, statement} = result) = {:ok, #{inspect(statement)}}
                  OfficeGraph.Repo.query!(statement, [])
                end
              end
              """
            }
          ])

        assert occurrence.construct == "Repo.query!"
        occurrence.fingerprint
      end)

    assert Enum.uniq(fingerprints) == fingerprints
  end

  test "anonymous-function parameter patterns shadow outer SQL bindings" do
    [
      {"statement", "OfficeGraph.Repo.query!(statement, [])"},
      {"{statement, params}", "OfficeGraph.Repo.query!(statement, params)"},
      {"%{statement: statement}", "OfficeGraph.Repo.query!(statement, [])"}
    ]
    |> Enum.each(fn {parameters, call} ->
      fingerprints =
        ["SELECT 1", "SELECT 2"]
        |> Enum.map(fn outer_statement ->
          [occurrence] =
            DatabaseBoundaryScanner.scan_sources([
              %{
                path: "lib/example.ex",
                source: """
                defmodule Example do
                  def load do
                    statement = #{inspect(outer_statement)}
                    params = []

                    fn #{parameters} ->
                      #{call}
                    end
                  end
                end
                """
              }
            ])

          assert occurrence.construct == "Repo.query!"
          occurrence.fingerprint
        end)

      assert length(Enum.uniq(fingerprints)) == 1
    end)
  end

  test "binds static arguments when scanning invoked literal callbacks" do
    [
      ~s'then(OfficeGraph.Repo, fn repo -> repo.query!("DELETE FROM events", []) end)',
      ~s'Kernel.then(OfficeGraph.Repo, fn repo -> repo.query!("DELETE FROM events", []) end)',
      ~s'OfficeGraph.Repo |> then(fn repo -> repo.query!("DELETE FROM events", []) end)',
      ~s'tap(OfficeGraph.Repo, fn repo -> repo.query!("DELETE FROM events", []) end)',
      ~s'(fn repo -> repo.query!("DELETE FROM events", []) end).(OfficeGraph.Repo)'
    ]
    |> Enum.each(fn callback_invocation ->
      [occurrence] =
        DatabaseBoundaryScanner.scan_sources([
          %{
            path: "lib/example.ex",
            source: """
            defmodule Example do
              def load do
                #{callback_invocation}
              end
            end
            """
          }
        ])

      assert occurrence.class == :raw_sql
      assert occurrence.construct == "Repo.query!"
      assert occurrence.function == "load/0"
      assert occurrence.line == 3
      refute Map.has_key?(occurrence, :approval)
    end)
  end

  test "binds static arguments when scanning invoked capture callbacks" do
    [
      ~s'then(OfficeGraph.Repo, & &1.query!("DELETE FROM events", []))',
      ~s'Kernel.then(OfficeGraph.Repo, & &1.query!("DELETE FROM events", []))',
      ~s'OfficeGraph.Repo |> then(& &1.query!("DELETE FROM events", []))',
      ~s'Enum.each([OfficeGraph.Repo], & &1.query!("DELETE FROM events", []))',
      ~s'(& &1.query!("DELETE FROM events", [])).(OfficeGraph.Repo)'
    ]
    |> Enum.each(fn callback_invocation ->
      [occurrence] =
        DatabaseBoundaryScanner.scan_sources([
          %{
            path: "lib/example.ex",
            source: """
            defmodule Example do
              def load do
                #{callback_invocation}
              end
            end
            """
          }
        ])

      assert occurrence.class == :raw_sql
      assert occurrence.construct == "Repo.query!"
      assert occurrence.function == "load/0"
      assert occurrence.line == 3
      refute Map.has_key?(occurrence, :approval)
    end)
  end

  test "classifies directly invoked remote database captures" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load do
              (&OfficeGraph.Repo.query!/2).("DELETE FROM events", [])
            end
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.function == "load/0"
    assert occurrence.line == 3
    refute Map.has_key?(occurrence, :approval)
  end

  test "binds static database receivers through captured local functions" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load do
              Enum.each([OfficeGraph.Repo], &run_query/1)
            end

            defp run_query(repo), do: repo.query!("DELETE FROM events", [])
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.function == "run_query/1"
    assert occurrence.line == 6
    refute Map.has_key?(occurrence, :approval)
  end

  test "binds static database receiver and SQL arguments through local helpers" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load do
              run_query(OfficeGraph.Repo, "DELETE FROM events")
            end

            defp run_query(repo, sql), do: repo.query!(sql, [])
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.function == "run_query/2"
    assert occurrence.line == 6
    refute Map.has_key?(occurrence, :approval)
  end

  test "resolves zero-arity local helpers used as database receivers" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load, do: repo().query!("DELETE FROM events", [])

            defp repo, do: OfficeGraph.Repo
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.function == "load/0"
    assert occurrence.line == 2
    refute Map.has_key?(occurrence, :approval)
  end

  test "resolves literal Module.concat database receivers without executing source" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load do
              repo = Module.concat(["OfficeGraph", "Repo"])
              adapter = Module.concat(Ecto.Adapters, "SQL")

              repo.query!("DELETE FROM events", [])
              adapter.query!(repo, "DELETE FROM archived_events", [])
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.function, &1.line}) == [
             {:raw_sql, "Repo.query!", "load/0", 6},
             {:raw_sql, "Ecto.Adapters.SQL.query!", "load/0", 7}
           ]
  end

  test "fails closed for partially dynamic Module.concat database receivers" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load(prefix) do
              repo = Module.concat([prefix, "Repo"])
              repo.query!("DELETE FROM events", [])
            end
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.function == "load/1"
    assert occurrence.line == 4
  end

  test "does not treat source tuples as internally resolved module receivers" do
    assert [] ==
             DatabaseBoundaryScanner.scan_sources([
               %{
                 path: "lib/example.ex",
                 source: """
                 defmodule Example do
                   def load do
                     receivers = [{:resolved_module_name, "OfficeGraph.Repo"}]

                     for receiver <- receivers do
                       receiver.query!("DELETE FROM events", [])
                     end
                   end
                 end
                 """
               }
             ])
  end

  test "uses callback argument expression results when binding literal callbacks" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load do
              then(repo = OfficeGraph.Repo, fn repo ->
                repo.query!("DELETE FROM events", [])
              end)

              (fn {:ok, repo} -> repo.query!("DELETE FROM events", []) end).(
                {:ok, repo} = {:ok, OfficeGraph.Repo}
              )
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.function, &1.line}) == [
             {"Repo.query!", "load/0", 4},
             {"Repo.query!", "load/0", 7}
           ]
  end

  test "resolves statically bound closures before direct invocation" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load do
              query = fn repo -> repo.query!("DELETE FROM events", []) end
              query.(OfficeGraph.Repo)
            end
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.function == "load/0"
    assert occurrence.line == 3
  end

  test "binds database receivers in callbacks supplied by Repo and Ecto.Multi" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load(multi) do
              OfficeGraph.Repo.transaction(fn repo ->
                repo.query!(System.fetch_env!("SQL"), [])
              end)

              Ecto.Multi.run(multi, :query, fn repo, _changes ->
                repo.query!(System.fetch_env!("SQL"), [])
              end)
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.function, &1.line}) == [
             {:direct_ecto, "Repo.transaction", "load/1", 3},
             {:raw_sql, "Repo.query!", "load/1", 4},
             {:direct_ecto, "Ecto.Multi.run", "load/1", 7},
             {:raw_sql, "Repo.query!", "load/1", 8}
           ]
  end

  test "binds static elements in consumed Stream callbacks" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load do
              Stream.each([OfficeGraph.Repo], fn repo ->
                repo.query!("DELETE FROM events", [])
              end)
              |> Stream.run()

              Stream.map([OfficeGraph.Repo], fn repo ->
                repo.query!("DELETE FROM archived_events", [])
              end)
              |> Stream.run()
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.function, &1.line}) == [
             {:raw_sql, "Repo.query!", "load/0", 4},
             {:raw_sql, "Repo.query!", "load/0", 9}
           ]
  end

  test "binds static elements in consumed Stream.map_every callbacks" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load do
              Stream.map_every([OfficeGraph.Repo], 1, fn repo ->
                repo.query!("DELETE FROM events", [])
              end)
              |> Stream.run()
            end
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.function == "load/0"
    assert occurrence.line == 4
  end

  test "binds static elements in Task async-stream callbacks" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load(supervisor) do
              Task.async_stream(
                [OfficeGraph.Repo],
                fn repo -> repo.query!("DELETE FROM events", []) end,
                ordered: false
              )
              |> Stream.run()

              Task.Supervisor.async_stream_nolink(
                supervisor,
                [OfficeGraph.Repo],
                fn repo -> repo.query!("DELETE FROM archived_events", []) end,
                ordered: false
              )
              |> Stream.run()

              Example.Task.async_stream(
                [OfficeGraph.Repo],
                fn repo -> repo.query!("DELETE FROM unrelated_events", []) end,
                ordered: false
              )
              |> Stream.run()
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.function, &1.line}) == [
             {:raw_sql, "Repo.query!", "load/1", 5},
             {:raw_sql, "Repo.query!", "load/1", 13}
           ]
  end

  test "resolves statically known map receiver projections" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load do
              state = %{repo: OfficeGraph.Repo}
              state.repo.query!("DELETE FROM events", [])
              Map.fetch!(state, :repo).query!("DELETE FROM archived_events", [])
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.function, &1.line}) == [
             {:raw_sql, "Repo.query!", "load/0", 4},
             {:raw_sql, "Repo.query!", "load/0", 5}
           ]
  end

  test "fails closed when an unresolved receiver expression contains a database module" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load(key) do
              state = %{repo: OfficeGraph.Repo}
              Map.fetch!(state, key).query!(System.fetch_env!("SQL"), [])
            end
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.function == "load/1"
    assert occurrence.line == 4
  end

  test "binds static enumerable elements in literal Enum callbacks" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            alias Enum, as: CoreEnum

            def load(initial) do
              Enum.each([OfficeGraph.Repo], fn repo ->
                repo.query!("DELETE FROM events", [])
              end)

              [OfficeGraph.Repo]
              |> Enum.map(fn repo -> repo.query!("DELETE FROM events", []) end)

              CoreEnum.reduce([OfficeGraph.Repo], initial, fn repo, accumulator ->
                repo.query!("DELETE FROM events", [])
                accumulator
              end)
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.function, &1.line}) == [
             {"Repo.query!", "load/1", 6},
             {"Repo.query!", "load/1", 10},
             {"Repo.query!", "load/1", 13}
           ]
  end

  test "binds static list elements in List fold callbacks" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            alias List, as: CoreList

            def load(initial) do
              List.foldl([OfficeGraph.Repo], initial, fn repo, accumulator ->
                repo.query!("DELETE FROM events", [])
                accumulator
              end)

              [OfficeGraph.Repo]
              |> CoreList.foldr(initial, fn repo, accumulator ->
                repo.query!("DELETE FROM archived_events", [])
                accumulator
              end)

              Example.List.foldl([OfficeGraph.Repo], initial, fn repo, accumulator ->
                repo.query!("DELETE FROM unrelated_events", [])
                accumulator
              end)
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.function, &1.line}) == [
             {"Repo.query!", "load/1", 6},
             {"Repo.query!", "load/1", 12}
           ]
  end

  test "binds static elements from every Enum.zip_with enumerable" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load(values) do
              Enum.zip_with(
                [OfficeGraph.Repo],
                [1],
                fn repo, _value -> repo.query!("DELETE FROM events", []) end
              )

              Enum.zip_with(
                [[OfficeGraph.Repo], [1]],
                fn [repo, _value] -> repo.query!("DELETE FROM archived_events", []) end
              )

              Enum.zip_with(
                [OfficeGraph.Repo],
                values,
                fn repo, _value -> repo.query!("DELETE FROM partial_left_events", []) end
              )

              Enum.zip_with(
                values,
                [OfficeGraph.Repo],
                fn _value, repo -> repo.query!("DELETE FROM partial_right_events", []) end
              )

              Enum.zip_with(
                [values, [OfficeGraph.Repo]],
                fn [_value, repo] -> repo.query!("DELETE FROM partial_list_events", []) end
              )

              Example.Enum.zip_with(
                [OfficeGraph.Repo],
                [1],
                fn repo, _value -> repo.query!("DELETE FROM unrelated_events", []) end
              )
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.function, &1.line}) == [
             {"Repo.query!", "load/1", 6},
             {"Repo.query!", "load/1", 11},
             {"Repo.query!", "load/1", 17},
             {"Repo.query!", "load/1", 23},
             {"Repo.query!", "load/1", 28}
           ]
  end

  test "binds static Enum.sort_by mapper results into comparator callbacks" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load do
              Enum.sort_by(
                [OfficeGraph.Repo, OfficeGraph.Repo],
                & &1,
                fn repo, _other ->
                  repo.query!("DELETE FROM events", [])
                  true
                end
              )

              Enum.sort_by(
                [:archived, :retained],
                fn _event -> OfficeGraph.Repo end,
                fn _left, repo ->
                  repo.query!("DELETE FROM archived_events", [])
                  false
                end
              )

              Enum.sort_by(
                [OfficeGraph.Repo, OfficeGraph.Repo],
                fn _repo -> Example.NotARepo end,
                fn value, _other -> value.query!("DELETE FROM unrelated_events", []) end
              )
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.function, &1.line}) == [
             {"Repo.query!", "load/0", 7},
             {"Repo.query!", "load/0", 16}
           ]
  end

  test "keeps Enum.sort_by mapper analysis when the sorter is not a callback" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load do
              Enum.sort_by(
                [OfficeGraph.Repo],
                fn repo -> repo.query!("DELETE FROM events", []) end,
                :asc
              )
            end
          end
          """
        }
      ])

    assert occurrence.construct == "Repo.query!"
    assert occurrence.function == "load/0"
    assert occurrence.line == 5
  end

  test "propagates static Enum map results into downstream callbacks" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load do
              Enum.map([OfficeGraph.Repo], & &1)
              |> Enum.each(fn repo -> repo.query!("DELETE FROM events", []) end)

              Enum.map([:event], fn _event -> OfficeGraph.Repo end)
              |> Enum.each(fn repo -> repo.query!("DELETE FROM archived_events", []) end)

              Enum.map([OfficeGraph.Repo], &identity/1)
              |> Enum.each(fn repo -> repo.query!("DELETE FROM retained_events", []) end)

              Enum.map([OfficeGraph.Repo], &identity/1)
              |> Stream.each(fn repo -> repo.query!("DELETE FROM streamed_events", []) end)
              |> Stream.run()

              Enum.map([:event], fn _event -> OfficeGraph.Repo end)
              |> Task.async_stream(fn repo -> repo.query!("DELETE FROM tasked_events", []) end)
              |> Stream.run()

              Enum.map([OfficeGraph.Repo], fn _repo -> Example.NotRepo end)
              |> Enum.each(fn value -> value.query!("DELETE FROM unrelated_events", []) end)
            end

            defp identity(value), do: value
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.function, &1.line}) == [
             {"Repo.query!", "load/0", 4},
             {"Repo.query!", "load/0", 7},
             {"Repo.query!", "load/0", 10},
             {"Repo.query!", "load/0", 13},
             {"Repo.query!", "load/0", 17}
           ]
  end

  test "bounds static Enum result resolution across cyclic lexical bindings" do
    scan =
      Task.async(fn ->
        DatabaseBoundaryScanner.scan_sources([
          %{
            path: "lib/example.ex",
            source: """
            defmodule Example do
              def load(patterns) do
                patterns = Enum.map(patterns, & &1)

                Enum.each(patterns, fn value ->
                  value.query!("DELETE FROM events", [])
                end)
              end
            end
            """
          }
        ])
      end)

    assert Task.await(scan, 1_000) == []
  end

  test "binds explicit static accumulators in Enum callbacks" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load do
              Enum.flat_map_reduce([:ok], OfficeGraph.Repo, fn _event, repo ->
                repo.query!("DELETE FROM events", [])
                {[], repo}
              end)

              Enum.map_reduce([:ok], OfficeGraph.Repo, fn _event, repo ->
                repo.query!("DELETE FROM events", [])
                {:ok, repo}
              end)

              Enum.reduce([:ok], OfficeGraph.Repo, fn _event, repo ->
                repo.query!("DELETE FROM events", [])
                repo
              end)

              Enum.reduce_while([:ok], OfficeGraph.Repo, fn _event, repo ->
                repo.query!("DELETE FROM events", [])
                {:cont, repo}
              end)

              Enum.scan([:ok], OfficeGraph.Repo, fn _event, repo ->
                repo.query!("DELETE FROM events", [])
                repo
              end)
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.construct, &1.function}) ==
             List.duplicate({"Repo.query!", "load/0"}, 5)
  end

  test "binds implicit static accumulators in Enum.reduce/2 and Enum.scan/2" do
    Enum.each([:reduce, :scan], fn operation ->
      [occurrence] =
        DatabaseBoundaryScanner.scan_sources([
          %{
            path: "lib/example.ex",
            source: """
            defmodule Example do
              def load do
                Enum.#{operation}([OfficeGraph.Repo, :event], fn _event, repo ->
                  repo.query!("DELETE FROM events", [])
                  repo
                end)
              end
            end
            """
          }
        ])

      assert occurrence.class == :raw_sql
      assert occurrence.construct == "Repo.query!"
      assert occurrence.function == "load/0"
      assert occurrence.line == 4
    end)
  end

  test "binds static enumerable elements in predicate Enum callback overloads" do
    callback_invocations = [
      ~s'Enum.take_while([OfficeGraph.Repo], fn repo -> repo.query!("SELECT 1", []) end)',
      ~s'Enum.drop_while([OfficeGraph.Repo], fn repo -> repo.query!("SELECT 1", []) end)',
      ~s'Enum.split_while([OfficeGraph.Repo], fn repo -> repo.query!("SELECT 1", []) end)',
      ~s'Enum.count_until([OfficeGraph.Repo], fn repo -> repo.query!("SELECT 1", []) end, 1)'
    ]

    Enum.each(callback_invocations, fn callback_invocation ->
      [occurrence] =
        DatabaseBoundaryScanner.scan_sources([
          %{
            path: "lib/example.ex",
            source: """
            defmodule Example do
              def load do
                #{callback_invocation}
              end
            end
            """
          }
        ])

      assert occurrence.class == :raw_sql
      assert occurrence.construct == "Repo.query!"
      assert occurrence.function == "load/0"
      assert occurrence.line == 3
    end)
  end

  test "binds static enumerable elements in Enum.map_join/2 callbacks" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load do
              Enum.map_join([OfficeGraph.Repo], fn repo ->
                repo.query!("SELECT 1", [])
              end)
            end
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.function == "load/0"
    assert occurrence.line == 4
  end

  test "does not apply Enum callback semantics to unrelated modules" do
    assert [] ==
             DatabaseBoundaryScanner.scan_sources([
               %{
                 path: "lib/example.ex",
                 source: """
                 defmodule Example do
                   def load do
                     Example.Enum.each([OfficeGraph.Repo], fn repo ->
                       repo.query!("DELETE FROM events", [])
                     end)
                   end
                 end
                 """
               }
             ])
  end

  test "does not treat function-valued Enum arguments as element callbacks" do
    assert [] ==
             DatabaseBoundaryScanner.scan_sources([
               %{
                 path: "lib/example.ex",
                 source: """
                 defmodule Example do
                   def load do
                     Enum.find(
                       [OfficeGraph.Repo],
                       fn default -> default.query!("DELETE FROM events", []) end,
                       fn _repo -> false end
                     )
                   end
                 end
                 """
               }
             ])
  end

  test "does not apply Kernel callback semantics to explicitly imported functions" do
    assert [] ==
             DatabaseBoundaryScanner.scan_sources([
               %{
                 path: "lib/example.ex",
                 source: """
                 defmodule Example do
                   import Example.Callbacks

                   def load do
                     then(OfficeGraph.Repo, fn repo ->
                       repo.query!("DELETE FROM events", [])
                     end)
                   end
                 end
                 """
               }
             ])
  end

  test "case-clause patterns shadow outer SQL bindings" do
    fingerprints =
      ["SELECT 1", "SELECT 2"]
      |> Enum.map(fn outer_statement ->
        [occurrence] =
          DatabaseBoundaryScanner.scan_sources([
            %{
              path: "lib/example.ex",
              source: """
              defmodule Example do
                def load(input) do
                  statement = #{inspect(outer_statement)}

                  case input do
                    statement -> OfficeGraph.Repo.query!(statement, [])
                  end
                end
              end
              """
            }
          ])

        assert occurrence.construct == "Repo.query!"
        occurrence.fingerprint
      end)

    assert length(Enum.uniq(fingerprints)) == 1
  end

  test "preserves bindings created while evaluating case subjects" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load do
              case repo = OfficeGraph.Repo do
                _repo -> :ok
              end

              repo.query!("DELETE FROM events", [])
            end
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.function == "load/0"
    assert occurrence.line == 7
  end

  test "generator patterns shadow outer SQL bindings" do
    [
      "for statement <- statements, do: OfficeGraph.Repo.query!(statement, [])",
      "with {:ok, statement} <- lookup(), do: OfficeGraph.Repo.query!(statement, [])"
    ]
    |> Enum.each(fn generator_source ->
      fingerprints =
        ["SELECT 1", "SELECT 2"]
        |> Enum.map(fn outer_statement ->
          [occurrence] =
            DatabaseBoundaryScanner.scan_sources([
              %{
                path: "lib/example.ex",
                source: """
                defmodule Example do
                  def load(statements) do
                    statement = #{inspect(outer_statement)}
                    #{generator_source}
                  end

                  defp lookup, do: {:ok, "SELECT 3"}
                end
                """
              }
            ])

          assert occurrence.construct == "Repo.query!"
          occurrence.fingerprint
        end)

      assert length(Enum.uniq(fingerprints)) == 1
    end)
  end

  test "threads condition bindings into if and unless branches" do
    [
      "if {:ok, repo} = {:ok, OfficeGraph.Repo}, do: repo.query!(\"SELECT 1\", [])",
      "unless {:ok, repo} = {:ok, OfficeGraph.Repo}, do: :ok, else: repo.query!(\"SELECT 1\", [])",
      "Kernel.if({:ok, repo} = {:ok, OfficeGraph.Repo}, do: repo.query!(\"SELECT 1\", []))",
      "Kernel.unless({:ok, repo} = {:ok, OfficeGraph.Repo}, do: :ok, else: repo.query!(\"SELECT 1\", []))"
    ]
    |> Enum.each(fn conditional_source ->
      [occurrence] =
        DatabaseBoundaryScanner.scan_sources([
          %{
            path: "lib/example.ex",
            source: """
            defmodule Example do
              def load do
                #{conditional_source}
              end
            end
            """
          }
        ])

      assert occurrence.class == :raw_sql
      assert occurrence.construct == "Repo.query!"
      assert occurrence.function == "load/0"
      assert occurrence.line == 3
    end)
  end

  test "threads left-operand bindings into reachable short-circuit operands" do
    [
      "(repo = OfficeGraph.Repo) && repo.query!(\"SELECT 1\", [])",
      "(repo = OfficeGraph.Repo; true) and repo.query!(\"SELECT 1\", [])",
      "(repo = OfficeGraph.Repo; false) || repo.query!(\"SELECT 1\", [])",
      "(repo = OfficeGraph.Repo; false) or repo.query!(\"SELECT 1\", [])"
    ]
    |> Enum.each(fn expression ->
      [occurrence] =
        DatabaseBoundaryScanner.scan_sources([
          %{
            path: "lib/example.ex",
            source: """
            defmodule Example do
              def load do
                #{expression}
              end
            end
            """
          }
        ])

      assert occurrence.class == :raw_sql
      assert occurrence.construct == "Repo.query!"
      assert occurrence.function == "load/0"
      assert occurrence.line == 3
    end)
  end

  test "binds a static try result into else clauses" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load do
              try do
                OfficeGraph.Repo
              else
                repo -> repo.query!("DELETE FROM events", [])
              end
            end
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.function == "load/0"
    assert occurrence.line == 6
  end

  test "fails closed when a database receiver crosses nonlocal control flow" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load do
              try do
                throw(OfficeGraph.Repo)
              catch
                repo -> repo.query!("DELETE FROM events", [])
              end

              try do
                Kernel.exit(OfficeGraph.Repo)
              catch
                :exit, repo -> repo.query!("DELETE FROM archived_events", [])
              end
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, fn occurrence ->
             {
               occurrence.class,
               occurrence.construct,
               occurrence.function,
               occurrence.line,
               occurrence.approval
             }
           end) == [
             {:raw_sql, "database_receiver.nonlocal_control_flow", "load/0", 4, :unresolved_sql},
             {:raw_sql, "database_receiver.nonlocal_control_flow", "load/0", 10, :unresolved_sql}
           ]
  end

  test "fails closed when a database receiver is sent to another process" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load(pid) do
              send(pid, OfficeGraph.Repo)
              Kernel.send(Process.whereis(:worker), {:repository, OfficeGraph.Repo})
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, fn occurrence ->
             {
               occurrence.class,
               occurrence.construct,
               occurrence.function,
               occurrence.line,
               occurrence.approval
             }
           end) == [
             {:raw_sql, "database_receiver.nonlocal_control_flow", "load/1", 3, :unresolved_sql},
             {:raw_sql, "database_receiver.nonlocal_control_flow", "load/1", 4, :unresolved_sql}
           ]
  end

  test "fails closed when a database receiver is stored in the process dictionary" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            alias Process, as: RuntimeProcess

            def load do
              Process.put(:repo, OfficeGraph.Repo)
              RuntimeProcess.put(:tagged_repo, {:repository, OfficeGraph.Repo})
              Process.put(:unrelated, Example.NotARepo)
              Example.Process.put(:repo, OfficeGraph.Repo)
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, fn occurrence ->
             {
               occurrence.class,
               occurrence.construct,
               occurrence.function,
               occurrence.line,
               occurrence.approval
             }
           end) == [
             {:raw_sql, "database_receiver.nonlocal_control_flow", "load/0", 5, :unresolved_sql},
             {:raw_sql, "database_receiver.nonlocal_control_flow", "load/0", 6, :unresolved_sql}
           ]
  end

  test "fails closed when a database receiver enters Agent state" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            alias Agent, as: StateAgent

            def load do
              {:ok, pid} = Agent.start_link(fn -> OfficeGraph.Repo end)
              Agent.get(pid, fn repo -> repo.query!("DELETE FROM events", []) end)

              StateAgent.start(fn -> {:repository, OfficeGraph.Repo} end)
              Agent.start_link(fn -> Example.NotARepo end)
              Example.Agent.start_link(fn -> OfficeGraph.Repo end)
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, fn occurrence ->
             {
               occurrence.class,
               occurrence.construct,
               occurrence.function,
               occurrence.line,
               occurrence.approval
             }
           end) == [
             {:raw_sql, "database_receiver.nonlocal_control_flow", "load/0", 5, :unresolved_sql},
             {:raw_sql, "database_receiver.nonlocal_control_flow", "load/0", 8, :unresolved_sql}
           ]
  end

  test "fails closed when a database receiver enters GenServer state" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            alias GenServer, as: RuntimeServer
            import GenServer, only: [start: 3]

            def load do
              GenServer.start_link(__MODULE__, OfficeGraph.Repo, [])
              RuntimeServer.start(__MODULE__, {:repository, OfficeGraph.Repo}, [])
              start(__MODULE__, Map.put(%{}, :repository, OfficeGraph.Repo), [])
              GenServer.start_link(__MODULE__, Example.NotARepo, [])
              Example.GenServer.start_link(__MODULE__, OfficeGraph.Repo, [])
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, fn occurrence ->
             {
               occurrence.class,
               occurrence.construct,
               occurrence.function,
               occurrence.line,
               occurrence.approval
             }
           end) == [
             {:raw_sql, "database_receiver.nonlocal_control_flow", "load/0", 6, :unresolved_sql},
             {:raw_sql, "database_receiver.nonlocal_control_flow", "load/0", 7, :unresolved_sql},
             {:raw_sql, "database_receiver.nonlocal_control_flow", "load/0", 8, :unresolved_sql}
           ]
  end

  test "fails closed when a database receiver enters ETS state" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load(table) do
              :ets.insert(table, {:repository, OfficeGraph.Repo})
              :ets.insert_new(table, [{:primary_repository, OfficeGraph.Repo}])
              :ets.update_element(table, :repository, {2, OfficeGraph.Repo})
              :ets.select_replace(table, [{{:"$1", :"$2"}, [], [{{:"$1", {:const, OfficeGraph.Repo}}}]}])
              :ets.update_counter(table, :repository, {2, 1}, {:repository, 0, OfficeGraph.Repo})
              :ets.insert(table, {:value, Example.NotARepo})
              Example.ETS.insert(table, {:repository, OfficeGraph.Repo})
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, fn occurrence ->
             {
               occurrence.class,
               occurrence.construct,
               occurrence.function,
               occurrence.line,
               occurrence.approval
             }
           end) == [
             {:raw_sql, "database_receiver.nonlocal_control_flow", "load/1", 3, :unresolved_sql},
             {:raw_sql, "database_receiver.nonlocal_control_flow", "load/1", 4, :unresolved_sql},
             {:raw_sql, "database_receiver.nonlocal_control_flow", "load/1", 5, :unresolved_sql},
             {:raw_sql, "database_receiver.nonlocal_control_flow", "load/1", 6, :unresolved_sql},
             {:raw_sql, "database_receiver.nonlocal_control_flow", "load/1", 7, :unresolved_sql}
           ]
  end

  test "fails closed when a database receiver enters persistent-term state" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load do
              :persistent_term.put(:repository, OfficeGraph.Repo)
              :persistent_term.put(:tagged_repository, {:repository, OfficeGraph.Repo})
              :persistent_term.put(:unrelated, Example.NotARepo)
              Example.PersistentTerm.put(:repository, OfficeGraph.Repo)
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, fn occurrence ->
             {
               occurrence.class,
               occurrence.construct,
               occurrence.function,
               occurrence.line,
               occurrence.approval
             }
           end) == [
             {:raw_sql, "database_receiver.nonlocal_control_flow", "load/0", 3, :unresolved_sql},
             {:raw_sql, "database_receiver.nonlocal_control_flow", "load/0", 4, :unresolved_sql}
           ]
  end

  test "fails closed when a database receiver enters application environment state" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            alias Application, as: AppEnvironment
            import Application, only: [put_env: 3]

            def load do
              Application.put_env(:example, :repository, OfficeGraph.Repo)
              Application.put_env(:example, :nested, {:repository, OfficeGraph.Repo}, persistent: true)
              AppEnvironment.put_all_env(example: [repository: OfficeGraph.Repo])
              put_env(:example, :repository, OfficeGraph.Repo)
              Application.put_env(:example, :unrelated, Example.NotARepo)
              Example.Application.put_env(:example, :repository, OfficeGraph.Repo)
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, fn occurrence ->
             {
               occurrence.class,
               occurrence.construct,
               occurrence.function,
               occurrence.line,
               occurrence.approval
             }
           end) == [
             {:raw_sql, "database_receiver.nonlocal_control_flow", "load/0", 6, :unresolved_sql},
             {:raw_sql, "database_receiver.nonlocal_control_flow", "load/0", 7, :unresolved_sql},
             {:raw_sql, "database_receiver.nonlocal_control_flow", "load/0", 8, :unresolved_sql},
             {:raw_sql, "database_receiver.nonlocal_control_flow", "load/0", 9, :unresolved_sql}
           ]
  end

  test "fails closed when an ordinary remote helper receives a database receiver" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load do
              SqlHelper.run(OfficeGraph.Repo, "DELETE FROM events")
            end
          end
          """
        },
        %{
          path: "lib/sql_helper.ex",
          source: """
          defmodule SqlHelper do
            def run(repo, sql), do: repo.query!(sql, [])
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "database_receiver.remote_helper"
    assert occurrence.function == "load/0"
    assert occurrence.line == 3
    assert occurrence.approval == :unresolved_sql

    assert DatabaseBoundaryScanner.scan_sources([
             %{
               path: "lib/example.ex",
               source: """
               defmodule Example do
                 def load do
                   SqlHelper.run(Example.NotARepo, "DELETE FROM events")
                   throw(Example.NotARepo)
                 end
               end
               """
             }
           ]) == []
  end

  test "fails closed when a tracked remote helper is a repository operation receiver" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load do
              SqlTarget.repo().query!("DELETE FROM events", [])
            end
          end
          """
        },
        %{
          path: "lib/sql_target.ex",
          source: """
          defmodule SqlTarget do
            def repo, do: OfficeGraph.Repo
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "database_receiver.remote_helper"
    assert occurrence.function == "load/0"
    assert occurrence.line == 3
    assert occurrence.approval == :unresolved_sql
  end

  test "binds statically delivered self messages into receive clauses" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load do
              send(self(), {:repository, OfficeGraph.Repo})
              Kernel.send(Kernel.self(), OfficeGraph.Repo)

              receive do
                {:repository, repo} -> repo.query!("DELETE FROM events", [])
              end

              receive do
                repo -> repo.query!("DELETE FROM archived_events", [])
              end
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, &{&1.class, &1.construct, &1.function, &1.line}) == [
             {:raw_sql, "Repo.query!", "load/0", 7},
             {:raw_sql, "Repo.query!", "load/0", 11}
           ]
  end

  test "does not shadow static local-helper expansion with Kernel send modeling" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load do
              send(OfficeGraph.Repo, "DELETE FROM events")
            end

            defp send(repo, statement) do
              repo.query!(statement, [])
            end
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.function == "send/2"
    assert occurrence.line == 7
  end

  test "expands static map enumerables into callback bindings" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load do
              Enum.each(%{repo: OfficeGraph.Repo}, fn {_key, repo} ->
                repo.query!("SELECT 1", [])
              end)
            end
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.function == "load/0"
    assert occurrence.line == 4
  end

  test "fails closed when a database receiver enters a callback-bearing Map operation" do
    callback_calls = [
      ~s|Map.filter(%{repo: OfficeGraph.Repo}, fn {_key, repo} -> repo end)|,
      ~s|Map.get_and_update(%{repo: OfficeGraph.Repo}, :repo, fn repo -> {repo, repo} end)|,
      ~s|Map.get_and_update!(Map.put(%{}, :repo, OfficeGraph.Repo), :repo, fn repo -> {repo.query!("SELECT 1", []), repo} end)|,
      ~s|Map.intersect(%{repo: OfficeGraph.Repo}, %{repo: Example.Cache}, fn _key, repo, _other -> repo end)|,
      ~s|Map.map(%{repo: OfficeGraph.Repo}, fn {_key, repo} -> repo end)|,
      ~s|Map.merge(%{repo: OfficeGraph.Repo}, %{repo: Example.Cache}, fn _key, repo, _other -> repo end)|,
      ~s|Map.new([repo: OfficeGraph.Repo], fn entry -> entry end)|,
      ~s|Map.reject(%{repo: OfficeGraph.Repo}, fn {_key, repo} -> repo end)|,
      ~s|Map.replace_lazy(%{repo: OfficeGraph.Repo}, :repo, fn repo -> repo end)|,
      ~s|Map.split_with(%{repo: OfficeGraph.Repo}, fn {_key, repo} -> repo end)|,
      ~s|Map.update(%{repo: OfficeGraph.Repo}, :repo, :default, fn repo -> repo end)|,
      ~s|Map.update!(%{repo: OfficeGraph.Repo}, :repo, fn repo -> repo end)|
    ]

    Enum.each(callback_calls, fn callback_call ->
      [occurrence] =
        DatabaseBoundaryScanner.scan_sources([
          %{
            path: "lib/example.ex",
            source: """
            defmodule Example do
              def load do
                #{callback_call}
              end
            end
            """
          }
        ])

      assert occurrence.class == :raw_sql
      assert occurrence.construct == "database_receiver.nonlocal_control_flow"
      assert occurrence.approval == :unresolved_sql
      assert occurrence.function == "load/0"
      assert occurrence.line == 3
    end)
  end

  test "fails closed for imported callback-bearing Map operations" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            import Map, only: [get_and_update!: 3]

            def load do
              get_and_update!(%{repo: OfficeGraph.Repo}, :repo, fn repo -> {repo, repo} end)
            end
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "database_receiver.nonlocal_control_flow"
    assert occurrence.approval == :unresolved_sql
    assert occurrence.function == "load/0"
    assert occurrence.line == 5
  end

  test "scans executable expressions in both positions of two-element tuples" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load do
              (fn repo -> {repo.query!("SELECT 1", []), repo} end).(OfficeGraph.Repo)
            end
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.function == "load/0"
    assert occurrence.line == 3
  end

  test "does not apply Map callback semantics to an unrelated receiver" do
    assert DatabaseBoundaryScanner.scan_sources([
             %{
               path: "lib/example.ex",
               source: """
               defmodule Example do
                 alias Example.Map

                 def load do
                   Map.get_and_update!(%{repo: OfficeGraph.Repo}, :repo, fn repo ->
                     {repo.query!("SELECT 1", []), repo}
                   end)
                 end
               end
               """
             }
           ]) == []
  end

  test "binds statically failed with values into else clauses" do
    [":error", "repo when false"]
    |> Enum.each(fn generator_pattern ->
      [occurrence] =
        DatabaseBoundaryScanner.scan_sources([
          %{
            path: "lib/example.ex",
            source: """
            defmodule Example do
              def load do
                with #{generator_pattern} <- OfficeGraph.Repo do
                  :ok
                else
                  repo -> repo.query!("SELECT 1", [])
                end
              end
            end
            """
          }
        ])

      assert occurrence.class == :raw_sql
      assert occurrence.construct == "Repo.query!"
      assert occurrence.function == "load/0"
      assert occurrence.line == 6
    end)
  end

  test "classifies repository calls through singleton static for generators" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load do
              for repo <- [OfficeGraph.Repo], do: repo.query!("SELECT 1", [])
            end
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.function == "load/0"
    assert occurrence.line == 3
  end

  test "classifies repository calls through every distinct static for generator value" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load do
              for repo <- [Example.NotARepo, OfficeGraph.Repo, OfficeGraph.Repo] do
                repo.query!("SELECT 1", [])
              end
            end
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.function == "load/0"
    assert occurrence.line == 4
  end

  test "expands static for generators for every accepted bare database receiver" do
    cases = [
      {"Repo", ~s'receiver.query!("SELECT 1", [])', :raw_sql, "Repo.query!"},
      {"Multi", ~s'receiver.run(:step, fn _repo, changes -> {:ok, changes} end)', :direct_ecto,
       "Ecto.Multi.run"}
    ]

    Enum.each(cases, fn {receiver, call, class, construct} ->
      [occurrence] =
        DatabaseBoundaryScanner.scan_sources([
          %{
            path: "lib/example.ex",
            source: """
            defmodule Example do
              def load do
                for receiver <- [Example.NotDatabase, #{receiver}], do: #{call}
              end
            end
            """
          }
        ])

      assert occurrence.class == class
      assert occurrence.construct == construct
      assert occurrence.function == "load/0"
      assert occurrence.line == 3
    end)
  end

  test "binds statically matched with generators into SQL fingerprints" do
    fingerprints =
      ["SELECT 1", "SELECT 2"]
      |> Enum.map(fn generated_statement ->
        [occurrence] =
          DatabaseBoundaryScanner.scan_sources([
            %{
              path: "lib/example.ex",
              source: """
              defmodule Example do
                def load do
                  statement = "SELECT outer"

                  with {:ok, statement} <- {:ok, #{inspect(generated_statement)}} do
                    OfficeGraph.Repo.query!(statement, [])
                  end
                end
              end
              """
            }
          ])

        assert occurrence.construct == "Repo.query!"
        occurrence.fingerprint
      end)

    assert Enum.uniq(fingerprints) == fingerprints
  end

  test "does not bind statically mismatched generator patterns into SQL fingerprints" do
    [
      "with {:ok, statement} <- {:error, __STATEMENT__}, do: OfficeGraph.Repo.query!(statement, [])",
      "for {:ok, statement} <- [{:error, __STATEMENT__}], do: OfficeGraph.Repo.query!(statement, [])"
    ]
    |> Enum.each(fn generator_source ->
      fingerprints =
        ["SELECT 1", "SELECT 2"]
        |> Enum.map(fn statement ->
          source = String.replace(generator_source, "__STATEMENT__", inspect(statement))

          [occurrence] =
            DatabaseBoundaryScanner.scan_sources([
              %{
                path: "lib/example.ex",
                source: """
                defmodule Example do
                  def load do
                    #{source}
                  end
                end
                """
              }
            ])

          assert occurrence.construct == "Repo.query!"
          occurrence.fingerprint
        end)

      assert length(Enum.uniq(fingerprints)) == 1
    end)
  end

  test "binds static case discriminants into clause SQL fingerprints" do
    fingerprints =
      ["SELECT 1", "SELECT 2"]
      |> Enum.map(fn statement ->
        [occurrence] =
          DatabaseBoundaryScanner.scan_sources([
            %{
              path: "lib/example.ex",
              source: """
              defmodule Example do
                def load do
                  case {:ok, #{inspect(statement)}} do
                    {:ok, statement} -> OfficeGraph.Repo.query!(statement, [])
                  end
                end
              end
              """
            }
          ])

        assert occurrence.construct == "Repo.query!"
        occurrence.fingerprint
      end)

    assert Enum.uniq(fingerprints) == fingerprints
  end

  test "binds static cons-pattern case discriminants into SQL fingerprints" do
    fingerprints =
      ["SELECT 1", "SELECT 2"]
      |> Enum.map(fn statement ->
        [occurrence] =
          DatabaseBoundaryScanner.scan_sources([
            %{
              path: "lib/example.ex",
              source: """
              defmodule Example do
                def load do
                  case [#{inspect(statement)}, :ignored] do
                    [statement | _rest] -> OfficeGraph.Repo.query!(statement, [])
                  end
                end
              end
              """
            }
          ])

        assert occurrence.construct == "Repo.query!"
        occurrence.fingerprint
      end)

    assert Enum.uniq(fingerprints) == fingerprints
  end

  test "binds default SQL only for generated lower-arity function fingerprints" do
    fingerprints_by_default =
      ["SELECT 1", "SELECT 2"]
      |> Enum.map(fn statement ->
        occurrences =
          DatabaseBoundaryScanner.scan_sources([
            %{
              path: "lib/example.ex",
              source: """
              defmodule Example do
                def load(statement \\\\ #{inspect(statement)}) do
                  OfficeGraph.Repo.query!(statement, [])
                end
              end
              """
            }
          ])

        assert Enum.all?(occurrences, &(&1.construct == "Repo.query!"))
        Map.new(occurrences, &{&1.function, &1.fingerprint})
      end)

    assert Enum.all?(
             fingerprints_by_default,
             &(Map.keys(&1) |> Enum.sort() == ["load/0", "load/1"])
           )

    [first, second] = fingerprints_by_default
    refute first["load/0"] == second["load/0"]
    assert first["load/1"] == second["load/1"]
    refute first["load/0"] == first["load/1"]
  end

  test "does not treat bitstring modifiers as clause-bound variables" do
    fingerprints =
      ["SELECT 1", "SELECT 2"]
      |> Enum.map(fn statement ->
        [occurrence] =
          DatabaseBoundaryScanner.scan_sources([
            %{
              path: "lib/example.ex",
              source: """
              defmodule Example do
                def load(input) do
                  binary = #{inspect(statement)}

                  case input do
                    <<_value::binary>> -> OfficeGraph.Repo.query!(binary, [])
                  end
                end
              end
              """
            }
          ])

        assert occurrence.construct == "Repo.query!"
        occurrence.fingerprint
      end)

    assert Enum.uniq(fingerprints) == fingerprints
  end

  test "binds module aliases from static with generators" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load do
              with repo <- OfficeGraph.Repo do
                repo.query!("SELECT 1", [])
              end
            end
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.function == "load/0"
    assert occurrence.line == 4
  end

  test "expression-headed clauses retain outer SQL bindings" do
    [
      """
      cond do
        is_binary(statement) -> OfficeGraph.Repo.query!(statement, [])
      end
      """,
      """
      receive do
        :done -> :ok
      after
        statement -> OfficeGraph.Repo.query!(statement, [])
      end
      """
    ]
    |> Enum.each(fn clause_source ->
      fingerprints =
        ["SELECT 1", "SELECT 2"]
        |> Enum.map(fn statement ->
          [occurrence] =
            DatabaseBoundaryScanner.scan_sources([
              %{
                path: "lib/example.ex",
                source: """
                defmodule Example do
                  def load do
                    statement = #{inspect(statement)}
                    #{clause_source}
                  end
                end
                """
              }
            ])

          occurrence.fingerprint
        end)

      assert Enum.uniq(fingerprints) == fingerprints
    end)
  end

  test "binds map, struct, and cons SQL values into migration option fingerprints" do
    [
      "%{statement: statement} = %{statement: __STATEMENT__}",
      "%Example.Query{statement: statement} = %Example.Query{statement: __STATEMENT__}",
      "[statement | _rest] = [__STATEMENT__, :ignored]",
      "[:query, statement | _rest] = [:query, __STATEMENT__, :ignored]"
    ]
    |> Enum.each(fn binding_source ->
      fingerprints =
        ["deleted_at IS NULL", "archived_at IS NULL"]
        |> Enum.map(fn statement ->
          source = String.replace(binding_source, "__STATEMENT__", inspect(statement))

          [occurrence] =
            DatabaseBoundaryScanner.scan_sources([
              %{
                path: "priv/repo/migrations/20260728000000_example.exs",
                source: """
                defmodule ExampleMigration do
                  use Ecto.Migration

                  def change do
                    #{source}
                    create index(:examples, [:code], where: statement)
                  end
                end
                """
              }
            ])

          assert occurrence.construct == "migration.where"
          occurrence.fingerprint
        end)

      assert Enum.uniq(fingerprints) == fingerprints
    end)
  end

  test "resolves struct aliases before binding destructured SQL values" do
    fingerprints =
      ["SELECT 1", "SELECT 2"]
      |> Enum.map(fn statement ->
        [occurrence] =
          DatabaseBoundaryScanner.scan_sources([
            %{
              path: "lib/example.ex",
              source: """
              defmodule Example do
                alias Example.Query, as: Query

                def load do
                  %Query{statement: statement} =
                    %Example.Query{statement: #{inspect(statement)}}

                  OfficeGraph.Repo.query!(statement, [])
                end
              end
              """
            }
          ])

        assert occurrence.construct == "Repo.query!"
        occurrence.fingerprint
      end)

    assert Enum.uniq(fingerprints) == fingerprints
  end

  test "binds migration option fingerprints to the enclosing DDL identity" do
    fingerprints =
      [
        "create index(:examples, [:code], options: \"fillfactor = 70\")",
        "create index(:examples, [:name], options: \"fillfactor = 70\")",
        "create_if_not_exists index(:examples, [:code], options: \"fillfactor = 70\")"
      ]
      |> Enum.map(fn migration_statement ->
        [occurrence] =
          DatabaseBoundaryScanner.scan_sources([
            %{
              path: "priv/repo/migrations/20260728000000_example.exs",
              source: """
              defmodule ExampleMigration do
                use Ecto.Migration

                def change do
                  #{migration_statement}
                end
              end
              """
            }
          ])

        occurrence.fingerprint
      end)

    assert Enum.uniq(fingerprints) == fingerprints
  end

  test "fingerprints local helpers with their definition-time module attributes" do
    fingerprints =
      ["DELETE FROM second", "DELETE FROM third"]
      |> Enum.map(fn trailing_sql ->
        [occurrence] =
          DatabaseBoundaryScanner.scan_sources([
            %{
              path: "lib/example.ex",
              source: """
              defmodule Example do
                @sql "DELETE FROM first"
                defp query(repo), do: repo.query!(@sql, [])

                @sql #{inspect(trailing_sql)}
                def load, do: query(OfficeGraph.Repo)
              end
              """
            }
          ])

        assert occurrence.class == :raw_sql
        assert occurrence.construct == "Repo.query!"
        occurrence.fingerprint
      end)

    assert length(Enum.uniq(fingerprints)) == 1
  end

  test "resolves compile-time bindings before storing module attributes" do
    [
      """
      repo = OfficeGraph.Repo
      @repo repo
      """,
      "@repo (repo = OfficeGraph.Repo)"
    ]
    |> Enum.each(fn module_setup ->
      [occurrence] =
        DatabaseBoundaryScanner.scan_sources([
          %{
            path: "lib/example.ex",
            source: """
            defmodule Example do
              #{module_setup}

              def load, do: @repo.query!("DELETE FROM events", [])
            end
            """
          }
        ])

      assert occurrence.class == :raw_sql
      assert occurrence.construct == "Repo.query!"
      assert occurrence.function == "load/0"
    end)
  end

  test "does not reclassify executable module attribute expressions at references" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            @repo OfficeGraph.Repo

            @rows @repo.query!("SELECT 1", [])

            def rows, do: @rows
            def cached_rows, do: @rows
          end
          """
        }
      ])

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.function == nil
    assert occurrence.line == 4
  end

  test "fingerprints every value of an accumulated SQL module attribute" do
    fingerprints =
      ["SELECT 1", "SELECT 2"]
      |> Enum.map(fn first_statement ->
        [occurrence] =
          DatabaseBoundaryScanner.scan_sources([
            %{
              path: "lib/example.ex",
              source: """
              defmodule Example do
                Module.register_attribute(__MODULE__, :sql, accumulate: true)

                @sql #{inspect(first_statement)}
                @sql "; SELECT 3"

                def load, do: OfficeGraph.Repo.query!(@sql, [])
              end
              """
            }
          ])

        refute Map.has_key?(occurrence, :approval)
        occurrence.fingerprint
      end)

    assert Enum.uniq(fingerprints) == fingerprints

    [literal_occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            def load, do: OfficeGraph.Repo.query!(["; SELECT 3", "SELECT 1"], [])
          end
          """
        }
      ])

    assert hd(fingerprints) == literal_occurrence.fingerprint
  end

  test "fails closed when module attribute accumulation cannot be determined" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "lib/example.ex",
          source: """
          defmodule Example do
            Module.register_attribute(__MODULE__, :sql,
              accumulate: System.get_env("ACCUMULATE_SQL") == "true"
            )

            @sql "SELECT 1"
            @sql "; SELECT 2"

            def load, do: OfficeGraph.Repo.query!(@sql, [])
          end
          """
        }
      ])

    assert occurrence.approval == :unresolved_sql
  end

  test "ignores where and check keywords outside SQL-bearing migration constructs" do
    assert DatabaseBoundaryScanner.scan_sources([
             %{
               path: "priv/repo/migrations/20260728000000_example.exs",
               source: """
               defmodule ExampleMigration do
                 use Ecto.Migration

                 def change do
                   metadata = [where: :archive]
                   options = [check: false]
                   {metadata, options}
                 end
               end
               """
             }
           ]) == []
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

  test "rejects reversible migration execute when either command is nonliteral" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "priv/repo/migrations/20260728000000_example.exs",
          source: """
          defmodule ExampleMigration do
            use Ecto.Migration

            def change do
              execute("CREATE INDEX examples_code_index ON examples (code)", System.fetch_env!("ROLLBACK_SQL"))
              Ecto.Migration.execute(System.fetch_env!("FORWARD_SQL"), "DROP INDEX examples_code_index")
              execute("CREATE INDEX examples_label_index ON examples (label)", "DROP INDEX examples_label_index")
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, fn occurrence ->
             {occurrence.construct, occurrence.line, Map.get(occurrence, :approval)}
           end) == [
             {"migration.execute", 5, :unresolved_sql},
             {"migration.execute", 6, :unresolved_sql},
             {"migration.execute", 7, nil}
           ]
  end

  test "classifies migration execute_file contents as raw SQL payloads" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "priv/repo/migrations/20260728000000_example.exs",
          source: """
          defmodule ExampleMigration do
            use Ecto.Migration

            def change(runtime_path) do
              execute_file("priv/repo/sql/change.pgsql")
              Ecto.Migration.execute_file("priv/repo/sql/up.pgsql", "priv/repo/sql/down.pgsql")
              execute_file(runtime_path)
            end
          end
          """
        },
        %{path: "priv/repo/sql/change.pgsql", source: "SELECT 1"},
        %{path: "priv/repo/sql/up.pgsql", source: "SELECT 2"},
        %{path: "priv/repo/sql/down.pgsql", source: "SELECT 3"}
      ])

    assert Enum.map(occurrences, fn occurrence ->
             {occurrence.construct, occurrence.line, Map.get(occurrence, :approval)}
           end) == [
             {"migration.execute_file", 5, nil},
             {"migration.execute_file", 6, nil},
             {"migration.execute_file", 7, :unresolved_sql}
           ]
  end

  test "invalidates execute_file fingerprints when referenced contents change" do
    fingerprints =
      ["SELECT 1", "SELECT 2"]
      |> Enum.map(fn file_contents ->
        [occurrence] =
          DatabaseBoundaryScanner.scan_sources([
            %{
              path: "priv/repo/migrations/20260728000000_example.exs",
              source: """
              defmodule ExampleMigration do
                use Ecto.Migration

                def change do
                  execute_file("priv/repo/sql/change.pgsql")
                end
              end
              """
            },
            %{path: "priv/repo/sql/change.pgsql", source: file_contents}
          ])

        refute Map.has_key?(occurrence, :approval)
        occurrence.fingerprint
      end)

    assert Enum.uniq(fingerprints) == fingerprints

    [missing_file_occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "priv/repo/migrations/20260728000000_example.exs",
          source: """
          defmodule ExampleMigration do
            use Ecto.Migration

            def change do
              execute_file("priv/repo/sql/missing.pgsql")
            end
          end
          """
        }
      ])

    assert missing_file_occurrence.approval == :unresolved_sql
  end

  test "does not resolve execute_file paths that escape the scan root" do
    [occurrence] =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "priv/repo/migrations/20260728000000_example.exs",
          source: """
          defmodule ExampleMigration do
            use Ecto.Migration

            def change do
              execute_file("../priv/repo/sql/change.pgsql")
            end
          end
          """
        },
        %{path: "priv/repo/sql/change.pgsql", source: "SELECT 1"}
      ])

    assert occurrence.construct == "migration.execute_file"
    assert occurrence.approval == :unresolved_sql
  end

  test "classifies expression index fields as target-bound raw SQL" do
    occurrences =
      DatabaseBoundaryScanner.scan_sources([
        %{
          path: "priv/repo/migrations/20260728000000_example.exs",
          source: """
          defmodule ExampleMigration do
            use Ecto.Migration

            def change(runtime_expression) do
              create index(:users, ["lower(email)"])
              create unique_index(:accounts, [:tenant_id, "lower(email)"])
              create index(:profiles, [runtime_expression])
            end
          end
          """
        }
      ])

    assert Enum.map(occurrences, fn occurrence ->
             {occurrence.construct, occurrence.line, Map.get(occurrence, :approval)}
           end) == [
             {"migration.index_expression", 5, nil},
             {"migration.index_expression", 6, nil},
             {"migration.index_expression", 7, :unresolved_sql}
           ]

    assert occurrences |> Enum.map(& &1.fingerprint) |> Enum.uniq() |> length() == 3
  end

  test "classifies migration execute and data insertion constructs" do
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

    assert Enum.count(occurrences, &(&1.construct == "migration.insert")) == 1
    assert Enum.count(occurrences, &(&1.construct == "migration.execute")) == 2
  end

  test "ignores SQL phrases in non-executable migration strings" do
    assert DatabaseBoundaryScanner.scan_sources([
             %{
               path: "priv/repo/migrations/20260728000000_example.exs",
               source: """
               defmodule ExampleMigration do
                 use Ecto.Migration

                 @moduledoc "Never use INSERT INTO from a migration"
                 @migration_note "The legacy migration used md5(value)"

                 def change do
                   explanation = "INSERT INTO is documentation here"
                   create table(:examples), do: add(:explanation, :text, default: explanation)
                 end
               end
               """
             }
           ]) == []
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

  test "repository scans bind execute_file fingerprints to tracked file contents" do
    with_git_repository(fn root ->
      migration_path = "priv/repo/migrations/20260804000000_execute_file.exs"
      sql_path = "priv/repo/sql/change.pgsql"

      Enum.each([migration_path, sql_path], fn path ->
        root |> Path.join(path) |> Path.dirname() |> File.mkdir_p!()
      end)

      File.write!(
        Path.join(root, migration_path),
        """
        defmodule ExecuteFileMigration do
          use Ecto.Migration

          def change do
            execute_file("priv/repo/sql/change.pgsql")
          end
        end
        """
      )

      File.write!(Path.join(root, sql_path), "SELECT 1")
      {_output, 0} = System.cmd("git", ["add", "--", migration_path, sql_path], cd: root)

      [first] = DatabaseBoundaryScanner.scan_repository(root)
      File.write!(Path.join(root, sql_path), "SELECT 2")
      [second] = DatabaseBoundaryScanner.scan_repository(root)

      refute first.fingerprint == second.fingerprint
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
