defmodule OfficeGraph.ProjectQuality.PlanningBoundary do
  @moduledoc """
  Enforces OpenSpec as the repository's only durable planning system.
  """

  @prohibited_roots [
    "designs/",
    "docs/designs/",
    "docs/plans/",
    "docs/specs/",
    "docs/superpowers/",
    "plans/",
    "specs/"
  ]

  @spec check_paths([Path.t()]) :: [map()]
  def check_paths(paths) do
    paths
    |> Enum.filter(&prohibited_path?/1)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(&%{kind: :parallel_planning, path: &1})
  end

  @spec check_repository(Path.t()) :: [map()]
  def check_repository(root \\ File.cwd!()) do
    paths =
      Enum.flat_map(@prohibited_roots, fn prohibited_root ->
        root
        |> Path.join(prohibited_root)
        |> Path.join("**/*")
        |> Path.wildcard(match_dot: true)
        |> Enum.filter(&File.regular?/1)
        |> Enum.map(&Path.relative_to(&1, root))
      end)

    check_paths(paths)
  end

  defp prohibited_path?(path) do
    Enum.any?(@prohibited_roots, &String.starts_with?(path, &1))
  end
end
