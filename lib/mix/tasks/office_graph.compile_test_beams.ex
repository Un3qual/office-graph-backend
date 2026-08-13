defmodule Mix.Tasks.OfficeGraph.CompileTestBeams do
  @shortdoc "Compiles tracked ExUnit modules for database dependency auditing"

  @project_quality_sources [
    "credo_checks/office_graph/project_boundaries/database_dependency_audit.ex",
    "credo_checks/office_graph/project_boundaries/database_boundary_scanner.ex",
    "credo_checks/office_graph/project_boundaries/database_boundary_gate.ex",
    "credo_checks/office_graph/project_boundaries/planning_boundary.ex",
    "credo_checks/office_graph/project_boundaries/check.ex"
  ]

  use Boundary, top_level?: true, check: [in: false, out: false]
  use Mix.Task

  @impl Mix.Task
  def run(_arguments) do
    ExUnit.start(autorun: false)
    Enum.each(@project_quality_sources, &Code.require_file/1)

    destination = Mix.Project.compile_path() |> Path.dirname() |> Path.join("test_ebin")
    File.rm_rf!(destination)
    File.mkdir_p!(destination)

    case Kernel.ParallelCompiler.compile_to_path(test_files!(), destination,
           debug_info: true,
           return_diagnostics: true
         ) do
      {:ok, _modules, %{compile_warnings: [], runtime_warnings: []}} ->
        :ok

      {:ok, _modules, warnings} ->
        warning_count = Enum.sum_by(warnings, fn {_kind, entries} -> length(entries) end)

        Mix.raise("test-module compilation emitted #{warning_count} warnings")

      {:error, errors, _warnings} ->
        Mix.raise("test-module compilation failed with #{length(errors)} errors")
    end
  end

  defp test_files! do
    root = File.cwd!()

    case System.cmd("git", ["ls-files", "-z", "test"], cd: root, stderr_to_stdout: true) do
      {output, 0} ->
        files =
          output
          |> String.split(<<0>>, trim: true)
          |> Enum.filter(&String.ends_with?(&1, "_test.exs"))
          |> Enum.map(&Path.join(root, &1))

        if files == [], do: Mix.raise("no tracked ExUnit modules found")
        files

      {output, status} ->
        Mix.raise("git ls-files failed with status #{status}: #{String.trim(output)}")
    end
  end
end
