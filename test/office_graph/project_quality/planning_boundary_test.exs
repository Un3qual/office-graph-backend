defmodule OfficeGraph.ProjectQuality.PlanningBoundaryTest do
  use ExUnit.Case, async: true

  alias OfficeGraph.ProjectQuality.PlanningBoundary

  test "rejects durable planning files under prohibited parallel roots" do
    diagnostics =
      PlanningBoundary.check_paths([
        "docs/reviews/completed-review.md",
        "docs/superpowers/plans/feature.md",
        "docs/plans/feature.md"
      ])

    assert diagnostics == [
             %{kind: :parallel_planning, path: "docs/plans/feature.md"},
             %{kind: :parallel_planning, path: "docs/superpowers/plans/feature.md"}
           ]
  end

  test "accepts OpenSpec artifacts and purpose-specific review evidence" do
    assert PlanningBoundary.check_paths([
             "openspec/changes/example/design.md",
             "openspec/specs/example/spec.md",
             "docs/reviews/completed-review.md"
           ]) == []
  end

  test "repository checks ignore empty prohibited directories but report files" do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_planning_boundary_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(root, "docs/superpowers/plans"))
    on_exit(fn -> File.rm_rf!(root) end)

    assert PlanningBoundary.check_repository(root) == []

    plan = Path.join(root, "docs/superpowers/plans/feature.md")
    File.write!(plan, "# Parallel plan\n")

    assert PlanningBoundary.check_repository(root) == [
             %{kind: :parallel_planning, path: "docs/superpowers/plans/feature.md"}
           ]
  end
end
