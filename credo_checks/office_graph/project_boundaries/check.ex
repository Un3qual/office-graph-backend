defmodule OfficeGraph.Credo.Check.ProjectBoundaries do
  @moduledoc """
  Enforces repository-wide planning and database-access boundaries.

  This check intentionally evaluates the complete Git-tracked repository even
  when Credo is invoked with a narrowed source list. SQL sources, deleted
  inventory entries, and parallel planning paths are global repository
  properties rather than per-Elixir-file concerns.
  """

  use Credo.Check,
    id: "OG1001",
    run_on_all: true,
    base_priority: :high,
    category: :warning,
    tags: [:project_boundaries],
    explanations: [
      check: """
      OpenSpec is the only durable planning system, and direct database access
      must match the reviewed debt or approved-exception inventories.
      """
    ]

  alias Credo.Execution
  alias Credo.Execution.ExecutionIssues
  alias Credo.IssueMeta
  alias Credo.SourceFile
  alias OfficeGraph.ProjectQuality.DatabaseBoundaryGate
  alias OfficeGraph.ProjectQuality.PlanningBoundary

  @approved_path "openspec/specs/ecto-sql-boundaries/approved-database-exceptions.json"

  @doc false
  @impl true
  def run_on_all_source_files(exec, _source_files, params) do
    root = Execution.working_dir(exec)

    issues =
      root
      |> diagnostics()
      |> Enum.map(&issue_for(&1, root, params))

    ExecutionIssues.append(exec, issues)
    :ok
  end

  defp diagnostics(root) do
    PlanningBoundary.check_repository(root) ++
      DatabaseBoundaryGate.check_repository(root)
  end

  defp issue_for(%{kind: :parallel_planning, path: path}, root, params) do
    format_boundary_issue(
      root,
      path,
      params,
      "parallel_planning: OpenSpec is the only durable planning system"
    )
  end

  defp issue_for(
         %{kind: :invalid_inventory, duplicate_locator: locator} = diagnostic,
         root,
         params
       ) do
    path = inventory_path(diagnostic.inventory)

    format_boundary_issue(
      root,
      path,
      params,
      "invalid_inventory #{inventory_name(diagnostic.inventory)} entries " <>
        "#{Enum.join(diagnostic.entries, ", ")} duplicate locator " <>
        "#{locator.path} #{locator.function || "<module>"} #{locator.construct} " <>
        "(#{locator.class}) ordinal #{locator.ordinal}"
    )
  end

  defp issue_for(
         %{kind: :invalid_inventory, invalid_fields: fields} = diagnostic,
         root,
         params
       ) do
    path = inventory_path(diagnostic.inventory)

    format_boundary_issue(
      root,
      path,
      params,
      "invalid_inventory #{inventory_name(diagnostic.inventory)} entry #{diagnostic.entry}: " <>
        "invalid #{Enum.join(fields, ", ")}"
    )
  end

  defp issue_for(%{kind: :invalid_inventory} = diagnostic, root, params) do
    path = inventory_path(diagnostic.inventory)

    format_boundary_issue(
      root,
      path,
      params,
      "invalid_inventory #{inventory_name(diagnostic.inventory)} entry #{diagnostic.entry}: " <>
        "missing #{Enum.join(diagnostic.missing_fields, ", ")}"
    )
  end

  defp issue_for(%{kind: :invalid_approval_provenance} = diagnostic, root, params) do
    path = inventory_path(diagnostic.inventory)

    format_boundary_issue(
      root,
      path,
      params,
      "invalid_approval_provenance #{inventory_name(diagnostic.inventory)} " <>
        "entry #{diagnostic.entry}: change #{diagnostic.approving_change} does not record " <>
        "fingerprint #{diagnostic.fingerprint} (#{diagnostic.reason})"
    )
  end

  defp issue_for(%{kind: :stale} = diagnostic, root, params) do
    path = inventory_path(diagnostic.inventory)

    format_boundary_issue(
      root,
      path,
      params,
      "stale database boundary: #{source_locator(diagnostic)} #{diagnostic.construct} " <>
        "(#{diagnostic.class}); fingerprint #{diagnostic.fingerprint}"
    )
  end

  defp issue_for(%{kind: :changed} = diagnostic, root, params) do
    format_boundary_issue(
      root,
      diagnostic.path,
      params,
      "changed database boundary: #{diagnostic.construct} (#{diagnostic.class}) at " <>
        "#{function_name(diagnostic)}; fingerprint #{diagnostic.fingerprint} replaced " <>
        diagnostic.recorded_fingerprint,
      diagnostic.line
    )
  end

  defp issue_for(%{kind: :unresolved} = diagnostic, root, params) do
    format_boundary_issue(
      root,
      diagnostic.path,
      params,
      "unresolved database boundary: #{diagnostic.construct} (#{diagnostic.class}) at " <>
        "#{function_name(diagnostic)}; the SQL payload is not statically fingerprintable " <>
        "and cannot be approved",
      diagnostic.line
    )
  end

  defp issue_for(%{kind: :new} = diagnostic, root, params) do
    format_boundary_issue(
      root,
      diagnostic.path,
      params,
      "new database boundary: #{diagnostic.construct} (#{diagnostic.class}) at " <>
        "#{function_name(diagnostic)}; fingerprint #{diagnostic.fingerprint}",
      diagnostic.line
    )
  end

  defp format_boundary_issue(root, path, params, message, line \\ nil) do
    source =
      root
      |> Path.join(path)
      |> File.read()
      |> case do
        {:ok, contents} -> contents
        {:error, :enoent} -> ""
        {:error, reason} -> raise File.Error, action: "read file", path: path, reason: reason
      end

    source
    |> SourceFile.parse(path)
    |> IssueMeta.for(params)
    |> format_issue(message: message, line_no: line)
  end

  defp inventory_path(:approved_exceptions), do: @approved_path

  defp inventory_name(:approved_exceptions), do: "approved_database_exceptions"

  defp source_locator(diagnostic) do
    "#{diagnostic.path}:#{diagnostic.line || 1} #{function_name(diagnostic)}"
  end

  defp function_name(%{function: nil}), do: "<module>"
  defp function_name(diagnostic), do: diagnostic.function
end
