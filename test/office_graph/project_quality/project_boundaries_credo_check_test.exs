defmodule OfficeGraph.ProjectQuality.ProjectBoundariesCredoCheckTest do
  use ExUnit.Case, async: false

  alias Credo.Execution
  alias Credo.Execution.ExecutionIssues
  alias OfficeGraph.ProjectQuality.DatabaseBoundaryScanner

  @check OfficeGraph.Credo.Check.ProjectBoundaries
  @approved_path "openspec/specs/ecto-sql-boundaries/approved-database-exceptions.json"

  setup_all do
    if Process.whereis(Credo.Supervisor) == nil do
      {:ok, _applications} = Application.ensure_all_started(:credo)
    end

    :ok
  end

  test "accepts a clean repository baseline" do
    with_repository(fn root ->
      assert run_check(root) == []
    end)
  end

  test "reports a new database occurrence at its source path" do
    with_repository(fn root ->
      write_tracked!(
        root,
        "lib/example.ex",
        """
        defmodule Example do
          def load, do: OfficeGraph.Repo.query!("SELECT 1", [])
        end
        """
      )

      issue = root |> run_check() |> issue_with("new", "lib/example.ex")

      assert issue.line_no == 2
      assert issue.message =~ "Repo.query!"
      assert issue.message =~ "raw_sql"
      assert issue.message =~ "sha256:"
    end)
  end

  test "reports a changed database occurrence with both fingerprints" do
    with_repository(fn root ->
      source = """
      defmodule Example do
        def load, do: OfficeGraph.Repo.query!("SELECT 1", [])
      end
      """

      [occurrence] =
        DatabaseBoundaryScanner.scan_sources([%{path: "lib/example.ex", source: source}])

      write_tracked!(root, "lib/example.ex", source)
      write_approved!(root, [approved_entry(occurrence, "sha256:recorded")])

      issue = root |> run_check() |> issue_with("changed", "lib/example.ex")

      assert issue.line_no == 2
      assert issue.message =~ occurrence.fingerprint
      assert issue.message =~ "sha256:recorded"
    end)
  end

  test "reports a stale approved exception at its inventory with its former locator" do
    with_repository(fn root ->
      write_approved!(
        root,
        [
          %{
            "approving_change" => "approved-change",
            "fingerprint" => "sha256:stale",
            "class" => "raw_sql",
            "construct" => "Repo.query!",
            "function" => "load/1",
            "line" => 2,
            "ordinal" => 1,
            "owner" => "OfficeGraph.Example",
            "path" => "lib/removed.ex",
            "reason" => "Approved test occurrence.",
            "retirement_condition" => "Remove with the test occurrence.",
            "terminal_objects" => [],
            "verification" => "Covered by this test."
          }
        ]
      )

      issue = root |> run_check() |> issue_with("stale", @approved_path)

      assert issue.message =~ "lib/removed.ex"
      assert issue.message =~ "load/1"
      assert issue.message =~ "Repo.query!"
      assert issue.message =~ "sha256:stale"
    end)
  end

  test "reports malformed approval metadata at the inventory that owns it" do
    with_repository(fn root ->
      write_approved!(
        root,
        [
          %{
            "approving_change" => "approved-change",
            "fingerprint" => "sha256:invalid",
            "class" => "raw_sql",
            "construct" => "Repo.query!",
            "function" => "load/1",
            "line" => 2,
            "ordinal" => 1,
            "owner" => "",
            "path" => "lib/removed.ex",
            "reason" => "Approved test occurrence.",
            "retirement_condition" => "Remove with the test occurrence.",
            "terminal_objects" => [],
            "verification" => "Covered by this test."
          }
        ]
      )

      issue = root |> run_check() |> issue_with("invalid_inventory", @approved_path)

      assert issue.message =~ "entry 1"
      assert issue.message =~ "owner"
    end)
  end

  test "reports missing accepted-change approval evidence at the approved inventory" do
    with_repository(fn root ->
      source = """
      defmodule Example do
        def load, do: OfficeGraph.Repo.query!("SELECT 1", [])
      end
      """

      [occurrence] =
        DatabaseBoundaryScanner.scan_sources([%{path: "lib/example.ex", source: source}])

      write_tracked!(root, "lib/example.ex", source)

      write_json!(root, @approved_path, %{
        "version" => 1,
        "exceptions" => [approved_entry(occurrence, occurrence.fingerprint)]
      })

      issue = root |> run_check() |> issue_with("invalid_approval_provenance", @approved_path)

      assert issue.message =~ "entry 1"
      assert issue.message =~ "approved-change"
      assert issue.message =~ occurrence.fingerprint
      assert issue.message =~ "missing_change"
    end)
  end

  test "reports every conflicting approval change path at the approved inventory" do
    with_repository(fn root ->
      source = """
      defmodule Example do
        def load, do: OfficeGraph.Repo.query!("SELECT 1", [])
      end
      """

      [occurrence] =
        DatabaseBoundaryScanner.scan_sources([%{path: "lib/example.ex", source: source}])

      approved = approved_entry(occurrence, occurrence.fingerprint)

      write_tracked!(root, "lib/example.ex", source)

      write_json!(root, @approved_path, %{
        "version" => 1,
        "exceptions" => [approved]
      })

      change_paths = [
        "openspec/changes/archive/2026-08-01-approved-change",
        "openspec/changes/archive/2026-08-02-approved-change"
      ]

      Enum.each(change_paths, fn change_path ->
        write_json!(root, Path.join(change_path, "database-exception-approvals.json"), %{
          "version" => 1,
          "approvals" => [approved]
        })
      end)

      issue = root |> run_check() |> issue_with("invalid_approval_provenance", @approved_path)

      assert issue.message =~ "ambiguous_change"
      assert Enum.all?(change_paths, &String.contains?(issue.message, &1))
    end)
  end

  test "reports duplicate approved locators at the inventory that owns them" do
    with_repository(fn root ->
      source = """
      defmodule Example do
        def load, do: OfficeGraph.Repo.query!("SELECT 1", [])
      end
      """

      [occurrence] =
        DatabaseBoundaryScanner.scan_sources([%{path: "lib/example.ex", source: source}])

      write_tracked!(root, "lib/example.ex", source)

      write_approved!(root, [
        approved_entry(occurrence, "sha256:recorded"),
        approved_entry(occurrence, occurrence.fingerprint)
      ])

      issue = root |> run_check() |> issue_with("invalid_inventory", @approved_path)

      assert issue.message =~ "entries 1, 2"
      assert issue.message =~ "duplicate locator"
      assert issue.message =~ "lib/example.ex load/0 Repo.query!"
    end)
  end

  test "reports invalid locator types before formatting duplicate diagnostics" do
    with_repository(fn root ->
      source = """
      defmodule Example do
        def load, do: OfficeGraph.Repo.query!("SELECT 1", [])
      end
      """

      [occurrence] =
        DatabaseBoundaryScanner.scan_sources([%{path: "lib/example.ex", source: source}])

      malformed_path = %{"unexpected" => "object"}

      write_approved!(root, [
        approved_entry(occurrence, "sha256:first") |> Map.put("path", malformed_path),
        approved_entry(occurrence, "sha256:second") |> Map.put("path", malformed_path)
      ])

      issues = run_check(root)

      assert Enum.map(issues, & &1.message) |> Enum.sort() == [
               "invalid_inventory approved_database_exceptions entry 1: invalid path",
               "invalid_inventory approved_database_exceptions entry 2: invalid path"
             ]
    end)
  end

  test "reports a parallel planning file at the prohibited path" do
    with_repository(fn root ->
      path = "docs/superpowers/plans/feature.md"
      write_file!(root, path, "# Parallel plan\n")

      issue = root |> run_check() |> issue_with("parallel_planning", path)

      assert issue.message =~ "OpenSpec"
    end)
  end

  test "the focused Credo configuration loads and selects the project boundary check" do
    with_repository(fn root ->
      path = "docs/superpowers/plans/focused-check.md"
      write_file!(root, path, "# Parallel plan\n")

      issues =
        [
          "--strict",
          "--mute-exit-status",
          "--config-file",
          Path.join(File.cwd!(), ".credo.exs"),
          "--only",
          inspect(@check),
          "--working-dir",
          root
        ]
        |> Credo.run()
        |> Execution.get_issues()

      assert [%{filename: ^path, message: message}] = issues
      assert message =~ "parallel_planning"
    end)
  end

  defp run_check(root) do
    exec =
      Execution.build()
      |> Map.put(:cli_options, %{path: root})

    :ok = OfficeGraph.Credo.Check.ProjectBoundaries.run_on_all_source_files(exec, [], [])

    exec
    |> ExecutionIssues.to_map()
    |> Map.values()
    |> List.flatten()
  end

  defp issue_with(issues, kind, path) do
    assert issue =
             Enum.find(issues, fn issue ->
               issue.filename == path and String.contains?(issue.message, kind)
             end),
           "expected #{kind} issue at #{path}, got: #{inspect(issues)}"

    issue
  end

  defp with_repository(test) do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_project_boundaries_credo_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {_output, 0} = System.cmd("git", ["init", "--quiet"], cd: root)

    write_tracked!(root, "lib/sentinel.ex", "defmodule Sentinel do\nend\n")
    prepare_compiled_environments!(root)
    write_approved!(root, [])

    test.(root)
  end

  defp prepare_compiled_environments!(root) do
    source_path = Path.join(root, "lib/sentinel.ex")

    for env <- [Mix.env(), :prod] |> Enum.uniq() do
      ebin = Path.join(root, "_build/#{env}/lib/office_graph/ebin")
      File.mkdir_p!(ebin)

      compile_file!(source_path, ebin)
    end
  end

  defp compile_file!(source_path, ebin) do
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
                       sentinel:
                         "56951246228ec4501c98eea5b58626b89a98e18f3a612a904577e650ff6806f1"
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
                 return_diagnostics: true
               )
    after
      Code.compiler_options(compiler_options)
    end
  end

  defp write_approved!(root, entries) do
    write_json!(root, @approved_path, %{"version" => 1, "exceptions" => entries})

    entries
    |> Enum.group_by(& &1["approving_change"])
    |> Enum.each(fn {change, approvals} ->
      write_json!(
        root,
        "openspec/changes/archive/2026-08-01-#{change}/database-exception-approvals.json",
        %{"version" => 1, "approvals" => approvals}
      )
    end)
  end

  defp write_json!(root, path, value) do
    write_file!(root, path, Jason.encode!(value))
  end

  defp write_tracked!(root, path, contents) do
    write_file!(root, path, contents)
    {_output, 0} = System.cmd("git", ["add", "--intent-to-add", "--", path], cd: root)
  end

  defp write_file!(root, path, contents) do
    full_path = Path.join(root, path)
    File.mkdir_p!(Path.dirname(full_path))
    File.write!(full_path, contents)
  end

  defp approved_entry(occurrence, fingerprint) do
    %{
      "approving_change" => "approved-change",
      "fingerprint" => fingerprint,
      "class" => to_string(occurrence.class),
      "construct" => occurrence.construct,
      "function" => occurrence.function,
      "line" => occurrence.line,
      "ordinal" => occurrence.ordinal,
      "owner" => "OfficeGraph.Example",
      "path" => occurrence.path,
      "reason" => "Approved test occurrence.",
      "retirement_condition" => "Remove with the test occurrence.",
      "terminal_objects" => [],
      "verification" => "Covered by this test."
    }
  end
end
