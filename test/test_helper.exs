ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(OfficeGraph.Repo, :manual)

for path <- [
      "credo_checks/office_graph/project_boundaries/database_dependency_audit.ex",
      "credo_checks/office_graph/project_boundaries/database_boundary_scanner.ex",
      "credo_checks/office_graph/project_boundaries/database_boundary_gate.ex",
      "credo_checks/office_graph/project_boundaries/planning_boundary.ex",
      "credo_checks/office_graph/project_boundaries/check.ex"
    ] do
  Code.require_file(path)
end
