defmodule OfficeGraph.ProjectQuality.ProjectBoundariesCredoCheckTest do
  use ExUnit.Case, async: false

  alias Credo.Execution
  alias Credo.Execution.ExecutionIssues
  alias OfficeGraph.ProjectQuality.DatabaseBoundaryScanner

  @check OfficeGraph.Credo.Check.ProjectBoundaries
  @debt_path "openspec/specs/ecto-sql-boundaries/database-access-debt.json"
  @approved_path "openspec/specs/ecto-sql-boundaries/approved-database-exceptions.json"

  setup_all do
    {:ok, _applications} = Application.ensure_all_started(:credo)
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
      write_debt!(root, [debt_entry(occurrence, "sha256:recorded")])

      issue = root |> run_check() |> issue_with("changed", "lib/example.ex")

      assert issue.line_no == 2
      assert issue.message =~ occurrence.fingerprint
      assert issue.message =~ "sha256:recorded"
    end)
  end

  test "reports stale debt at the debt inventory with its former locator" do
    with_repository(fn root ->
      write_debt!(
        root,
        [
          %{
            "fingerprint" => "sha256:stale",
            "class" => "raw_sql",
            "construct" => "Repo.query!",
            "function" => "load/1",
            "ordinal" => 1,
            "owner" => "OfficeGraph.Example",
            "path" => "lib/removed.ex",
            "remediation_change" => "remove-direct-database-access"
          }
        ]
      )

      issue = root |> run_check() |> issue_with("stale", @debt_path)

      assert issue.message =~ "lib/removed.ex"
      assert issue.message =~ "load/1"
      assert issue.message =~ "Repo.query!"
      assert issue.message =~ "sha256:stale"
    end)
  end

  test "reports malformed debt at the inventory that owns it" do
    with_repository(fn root ->
      write_debt!(
        root,
        [
          %{
            "fingerprint" => "sha256:invalid",
            "class" => "raw_sql",
            "construct" => "Repo.query!",
            "function" => "load/1",
            "ordinal" => 1,
            "owner" => "",
            "path" => "lib/removed.ex",
            "remediation_change" => "remove-direct-database-access"
          }
        ]
      )

      issue = root |> run_check() |> issue_with("invalid_inventory", @debt_path)

      assert issue.message =~ "entry 1"
      assert issue.message =~ "owner"
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

  test "the focused Credo invocation loads and selects the project boundary check" do
    with_repository(fn root ->
      path = "docs/superpowers/plans/focused-check.md"
      write_file!(root, path, "# Parallel plan\n")

      {output, status} =
        System.cmd(
          "mix",
          [
            "credo",
            "--strict",
            "--config-file",
            Path.join(File.cwd!(), ".credo.exs"),
            "--only",
            inspect(@check),
            "--working-dir",
            root
          ],
          env: [{"MIX_ENV", "test"}],
          stderr_to_stdout: true
        )

      assert status != 0
      assert output =~ path
      assert output =~ "parallel_planning"
      assert length(:binary.matches(output, path)) == 1
    end)
  end

  defp run_check(root) do
    exec =
      Execution.build()
      |> Map.put(:cli_options, %{path: root})

    :ok = apply(@check, :run_on_all_source_files, [exec, [], []])

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
    write_debt!(root, [])
    write_approved!(root, [])

    test.(root)
  end

  defp write_debt!(root, entries) do
    files =
      entries
      |> Enum.group_by(&Map.fetch!(&1, "path"))
      |> Enum.map(fn {path, occurrences} ->
        first = hd(occurrences)

        %{
          "path" => path,
          "owner" => Map.fetch!(first, "owner"),
          "remediation_change" => Map.fetch!(first, "remediation_change"),
          "occurrences" =>
            Enum.map(occurrences, fn occurrence ->
              [
                Map.fetch!(occurrence, "fingerprint"),
                Map.fetch!(occurrence, "class"),
                Map.fetch!(occurrence, "construct"),
                Map.get(occurrence, "function"),
                Map.fetch!(occurrence, "ordinal")
              ]
            end)
        }
      end)

    write_json!(
      root,
      @debt_path,
      %{
        "version" => 1,
        "status" => "unapproved_removal_debt",
        "occurrence_fields" => [
          "fingerprint",
          "class",
          "construct",
          "function",
          "ordinal"
        ],
        "files" => files
      }
    )
  end

  defp write_approved!(root, entries) do
    write_json!(root, @approved_path, %{"version" => 1, "exceptions" => entries})
  end

  defp write_json!(root, path, value) do
    write_file!(root, path, Jason.encode!(value))
  end

  defp write_tracked!(root, path, contents) do
    write_file!(root, path, contents)
    {_output, 0} = System.cmd("git", ["add", path], cd: root)
  end

  defp write_file!(root, path, contents) do
    full_path = Path.join(root, path)
    File.mkdir_p!(Path.dirname(full_path))
    File.write!(full_path, contents)
  end

  defp debt_entry(occurrence, fingerprint) do
    %{
      "fingerprint" => fingerprint,
      "class" => to_string(occurrence.class),
      "construct" => occurrence.construct,
      "function" => occurrence.function,
      "ordinal" => occurrence.ordinal,
      "owner" => "OfficeGraph.Example",
      "path" => occurrence.path,
      "remediation_change" => "remove-direct-database-access"
    }
  end
end
