defmodule OfficeGraph.ProjectQuality.QualityBoundaryMixTasksTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  test "database-boundary command accepts the reviewed repository baseline" do
    Mix.Task.reenable("office_graph.database_boundaries")

    assert capture_io(fn ->
             Mix.Tasks.OfficeGraph.DatabaseBoundaries.run([])
           end) =~ "database boundaries: ok"
  end

  test "database-boundary command rejects unclassified SQL with an actionable diagnostic" do
    with_temporary_root(fn root ->
      File.mkdir_p!(Path.join(root, "lib"))
      File.mkdir_p!(Path.join(root, "openspec/specs/ecto-sql-boundaries"))
      File.write!(Path.join(root, "lib/example.ex"), "OfficeGraph.Repo.query!(\"SELECT 1\", [])")

      File.write!(
        Path.join(root, "openspec/specs/ecto-sql-boundaries/database-access-debt.json"),
        Jason.encode!(%{
          "version" => 1,
          "status" => "unapproved_removal_debt",
          "occurrence_fields" => [
            "fingerprint",
            "class",
            "construct",
            "function",
            "ordinal"
          ],
          "files" => []
        })
      )

      File.write!(
        Path.join(root, "openspec/specs/ecto-sql-boundaries/approved-database-exceptions.json"),
        Jason.encode!(%{"version" => 1, "exceptions" => []})
      )

      {_output, 0} = System.cmd("git", ["add", "lib/example.ex"], cd: root)
      Mix.Task.reenable("office_graph.database_boundaries")

      assert_raise Mix.Error, ~r/new.*lib\/example\.ex.*Repo\.query!/s, fn ->
        Mix.Tasks.OfficeGraph.DatabaseBoundaries.run(["--root", root])
      end
    end)
  end

  test "planning-boundary command rejects a parallel plan path" do
    with_temporary_root(fn root ->
      plan = Path.join(root, "docs/superpowers/plans/feature.md")
      File.mkdir_p!(Path.dirname(plan))
      File.write!(plan, "# Parallel plan\n")
      Mix.Task.reenable("office_graph.planning_boundaries")

      assert_raise Mix.Error, ~r/docs\/superpowers\/plans\/feature\.md/, fn ->
        Mix.Tasks.OfficeGraph.PlanningBoundaries.run(["--root", root])
      end
    end)
  end

  defp with_temporary_root(test) do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_quality_mix_task_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {_output, 0} = System.cmd("git", ["init", "--quiet"], cd: root)
    test.(root)
  end
end
