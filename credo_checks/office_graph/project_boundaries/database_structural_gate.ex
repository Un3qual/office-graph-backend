defmodule OfficeGraph.ProjectQuality.DatabaseStructuralGate do
  @moduledoc """
  Combines the finite source scanner with module-level BEAM dependency evidence.

  The existing database boundary remains active while this additive gate is
  proven. Compiler imports reconcile only with an explicit source target in the
  same tracked file; the gate performs no source or instruction dataflow.
  """

  alias OfficeGraph.ProjectQuality.DatabaseBoundaryGate
  alias OfficeGraph.ProjectQuality.DatabaseDependencyAudit
  alias OfficeGraph.ProjectQuality.DatabasePrimitiveScanner

  @spec check_repository(Path.t()) :: [map()]
  def check_repository(root \\ File.cwd!()) do
    source = DatabasePrimitiveScanner.scan_repository(root)
    compiled = DatabaseDependencyAudit.scan(root)

    approved_path =
      Path.join(root, "openspec/specs/ecto-sql-boundaries/approved-database-exceptions.json")

    approved = DatabaseBoundaryGate.load_approved_inventory!(approved_path)

    DatabaseBoundaryGate.compare(source, approved) ++ compiled_diagnostics(source, compiled)
  end

  @spec compiled_diagnostics([map()], [map()]) :: [map()]
  def compiled_diagnostics(source, compiled) do
    source_targets =
      MapSet.new(source, fn occurrence ->
        {
          occurrence.path,
          Map.get(occurrence, :target_module),
          Map.get(occurrence, :target_function),
          Map.get(occurrence, :target_arity)
        }
      end)

    Enum.flat_map(compiled, fn occurrence ->
      target = {
        occurrence.path,
        occurrence.target_module,
        occurrence.target_function,
        occurrence.target_arity
      }

      if MapSet.member?(source_targets, target) do
        []
      else
        [
          occurrence
          |> Map.drop([:approval])
          |> Map.put(:kind, :compiled_reference)
        ]
      end
    end)
  end
end
