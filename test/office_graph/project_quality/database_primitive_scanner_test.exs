defmodule OfficeGraph.ProjectQuality.DatabasePrimitiveScannerTest do
  use ExUnit.Case, async: true

  alias OfficeGraph.ProjectQuality.DatabasePrimitiveScanner

  test "preserves the two approved UUIDv7 source fingerprints" do
    occurrences = DatabasePrimitiveScanner.scan_repository(File.cwd!())

    assert Enum.map(occurrences, &Map.take(&1, [:path, :line, :fingerprint])) == [
             %{
               path: "priv/repo/migrations/20260729233957_initial.exs",
               line: 4892,
               fingerprint:
                 "sha256:1c00daebdd2b1e43f8c59ea6a36b5a9606bf15f2292cd69cfa6c02b974e0717b"
             },
             %{
               path:
                 "priv/repo/migrations/20260730005539_integrate_workos_enterprise_identity.exs",
               line: 340,
               fingerprint:
                 "sha256:3fbfef45542e6568ac392c69d0849a575ae68dc51670f05002e2bb1abfc124f8"
             }
           ]
  end

  test "classifies an explicit low-level call without following dataflow" do
    [occurrence] =
      scan("lib/example.ex", """
      defmodule Example do
        def load(query), do: OfficeGraph.Repo.all(query)
      end
      """)

    assert Map.take(occurrence, [
             :path,
             :line,
             :function,
             :class,
             :construct,
             :target_module,
             :target_function,
             :target_arity
           ]) == %{
             path: "lib/example.ex",
             line: 2,
             function: "load/1",
             class: :direct_ecto,
             construct: "Repo.all",
             target_module: "OfficeGraph.Repo",
             target_function: :all,
             target_arity: 1
           }
  end

  test "rejects explicit low-level source indirection instead of resolving it" do
    sources = [
      {"lib/delegate.ex", "defdelegate all(query), to: OfficeGraph.Repo"},
      {"lib/capture.ex", "fun = &OfficeGraph.Repo.all/1"},
      {"lib/apply.ex", "apply(OfficeGraph.Repo, :all, [query])"}
    ]

    occurrences =
      Enum.flat_map(sources, fn {path, source} -> scan(path, source) end)

    assert Enum.map(occurrences, &{&1.path, &1.approval}) == [
             {"lib/delegate.ex", :unsupported_indirection},
             {"lib/capture.ex", :unsupported_indirection},
             {"lib/apply.ex", :unsupported_indirection}
           ]
  end

  test "does not classify inert Elixir syntax" do
    assert scan("lib/inert.ex", ~S'''
           defmodule Inert do
             @moduledoc "OfficeGraph.Repo.all(query)"
             # OfficeGraph.Repo.all(query)
             @example "Postgrex.query!(connection, sql, [])"

             def quoted do
               quote do
                 OfficeGraph.Repo.all(query)
               end
             end
           end
           ''') == []
  end

  test "marks dynamic SQL as unapprovable" do
    [occurrence] =
      scan("lib/example.ex", """
      defmodule Example do
        def run(sql), do: OfficeGraph.Repo.query!(sql, [])
      end
      """)

    assert occurrence.class == :raw_sql
    assert occurrence.construct == "Repo.query!"
    assert occurrence.approval == :unresolved_sql
  end

  test "uses one conservative token rule for executable scripts" do
    [occurrence] =
      scan("bin/example.py", """
      # The gate intentionally does not parse comments or heredocs in scripts.
      payload = '''
      psql --file migration.sql
      '''
      """)

    assert occurrence.class == :database_client
    assert occurrence.construct == "script.psql"
    assert occurrence.approval == :unsupported_script_token
  end

  test "ignores empty and comment-only SQL-like files" do
    assert scan("scripts/empty.sql", "-- no executable SQL\n/* still inert */\n") == []
  end

  test "ignores a tracked source deleted from the worktree" do
    root = Path.join(System.tmp_dir!(), "primitive-scan-#{System.unique_integer([:positive])}")
    path = Path.join(root, "lib/deleted.ex")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "OfficeGraph.Repo.all(query)")
    assert {_, 0} = System.cmd("git", ["init", "--quiet"], cd: root)
    assert {_, 0} = System.cmd("git", ["add", "lib/deleted.ex"], cd: root)
    File.rm!(path)

    try do
      assert DatabasePrimitiveScanner.scan_repository(root) == []
    after
      File.rm_rf!(root)
    end
  end

  defp scan(path, source) do
    DatabasePrimitiveScanner.scan_sources([%{path: path, source: source}])
  end
end
