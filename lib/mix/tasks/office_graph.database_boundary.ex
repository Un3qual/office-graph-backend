defmodule Mix.Tasks.OfficeGraph.DatabaseBoundary do
  @shortdoc "Checks finite source and compiled database boundaries"

  use Mix.Task
  use Boundary, top_level?: true, deps: []

  @impl Mix.Task
  def run(_args) do
    root = File.cwd!()

    for path <- [
          "credo_checks/office_graph/project_boundaries/database_boundary_scanner.ex",
          "credo_checks/office_graph/project_boundaries/database_boundary_gate.ex",
          "credo_checks/office_graph/project_boundaries/database_primitive_policy.ex",
          "credo_checks/office_graph/project_boundaries/database_primitive_scanner.ex",
          "credo_checks/office_graph/project_boundaries/database_dependency_audit.ex",
          "credo_checks/office_graph/project_boundaries/database_structural_gate.ex"
        ] do
      Code.require_file(Path.join(root, path))
    end

    case apply(
           OfficeGraph.ProjectQuality.DatabaseStructuralGate,
           :check_repository,
           [root]
         ) do
      [] ->
        :ok

      diagnostics ->
        formatted = Enum.map_join(diagnostics, "\n", &inspect/1)
        Mix.raise("database structural boundary failed:\n#{formatted}")
    end
  end
end
