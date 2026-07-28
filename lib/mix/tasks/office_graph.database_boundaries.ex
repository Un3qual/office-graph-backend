defmodule Mix.Tasks.OfficeGraph.DatabaseBoundaries do
  use Mix.Task

  alias OfficeGraph.ProjectQuality.DatabaseBoundaryGate

  @shortdoc "Checks raw-SQL and direct-Ecto inventories"

  @impl Mix.Task
  def run(args) do
    root = parse_root!(args)

    case DatabaseBoundaryGate.check_repository(root) do
      [] ->
        Mix.shell().info("database boundaries: ok")

      diagnostics ->
        Mix.raise("""
        database boundaries failed:
        #{Enum.map_join(diagnostics, "\n", &format_diagnostic/1)}
        """)
    end
  end

  defp parse_root!(args) do
    case OptionParser.parse(args, strict: [root: :string]) do
      {[root: root], [], []} -> Path.expand(root)
      {[], [], []} -> File.cwd!()
      _invalid -> Mix.raise("usage: mix office_graph.database_boundaries [--root PATH]")
    end
  end

  defp format_diagnostic(%{kind: :invalid_inventory} = diagnostic) do
    "invalid_inventory #{diagnostic.inventory} entry #{diagnostic.entry}: missing #{Enum.join(diagnostic.missing_fields, ", ")}"
  end

  defp format_diagnostic(%{kind: :changed} = diagnostic) do
    "changed #{location(diagnostic)} #{diagnostic.construct}: #{diagnostic.fingerprint} replaced #{diagnostic.recorded_fingerprint}"
  end

  defp format_diagnostic(%{kind: kind} = diagnostic) when kind in [:new, :stale] do
    "#{kind} #{location(diagnostic)} #{diagnostic.construct}: #{diagnostic.fingerprint}"
  end

  defp location(diagnostic) do
    function = diagnostic.function || "<module>"
    "#{diagnostic.path}:#{diagnostic.line || 1} #{function}"
  end
end
