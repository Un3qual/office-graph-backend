defmodule Mix.Tasks.OfficeGraph.PlanningBoundaries do
  use Mix.Task

  alias OfficeGraph.ProjectQuality.PlanningBoundary

  @shortdoc "Checks that durable planning lives only in OpenSpec"

  @impl Mix.Task
  def run(args) do
    root = parse_root!(args)

    case PlanningBoundary.check_repository(root) do
      [] ->
        Mix.shell().info("planning boundaries: ok")

      diagnostics ->
        paths = Enum.map_join(diagnostics, "\n", &"parallel_planning #{&1.path}")
        Mix.raise("planning boundaries failed:\n#{paths}")
    end
  end

  defp parse_root!(args) do
    case OptionParser.parse(args, strict: [root: :string]) do
      {[root: root], [], []} -> Path.expand(root)
      {[], [], []} -> File.cwd!()
      _invalid -> Mix.raise("usage: mix office_graph.planning_boundaries [--root PATH]")
    end
  end
end
