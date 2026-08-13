defmodule OfficeGraph.ProjectQuality.DatabaseDependencyAudit do
  @moduledoc """
  Audits module-level compiler imports for direct database dependencies.

  This audit intentionally does not disassemble BEAM instructions or infer
  source lines, callbacks, aliases, or control flow.
  """

  alias OfficeGraph.ProjectQuality.DatabasePrimitivePolicy, as: Policy

  @fully_owned_sources MapSet.new(["lib/office_graph/repo.ex"])
  @allowed_imports %{
    "lib/office_graph/application.ex" => MapSet.new([{"Ecto.DevLogger", :install, 1}])
  }

  @spec scan(Path.t(), keyword()) :: [map()]
  def scan(root \\ File.cwd!(), opts \\ []) do
    environments = Keyword.get(opts, :environments, [:test, :prod])

    {paths, missing} =
      Enum.reduce(environments, {[], []}, fn environment, {paths, missing} ->
        relative = "_build/#{environment}/lib/office_graph/ebin"
        environment_paths = root |> Path.join(relative <> "/*.beam") |> Path.wildcard()

        if environment_paths == [] do
          {paths, [{environment, relative} | missing]}
        else
          {environment_paths ++ paths, missing}
        end
      end)

    scan_paths(paths, root) ++ Enum.map(missing, &missing_environment/1)
  end

  @spec scan_paths([Path.t()], Path.t()) :: [map()]
  def scan_paths(paths, root) do
    paths
    |> Enum.flat_map(&scan_beam(&1, root))
    |> Enum.uniq_by(&{&1.path, &1.caller, &1.target_module, &1.target_function, &1.target_arity})
    |> Enum.sort_by(&{&1.path, &1.construct, &1.caller, &1.target_arity})
    |> assign_fingerprints()
  end

  defp scan_beam(path, root) do
    case :beam_lib.chunks(String.to_charlist(path), [:imports, :compile_info]) do
      {:ok, {caller, chunks}} ->
        with {:ok, source} <- source_path(chunks[:compile_info], root) do
          if MapSet.member?(@fully_owned_sources, source) do
            []
          else
            chunks[:imports]
            |> Enum.flat_map(&import_occurrence(&1, caller, source))
            |> Enum.reject(&allowed_import?(source, &1))
          end
        else
          {:error, reason} -> [metadata_unavailable(path, caller, reason, root)]
        end

      {:error, reason} ->
        [metadata_unavailable(path, nil, reason, root)]
    end
  end

  defp import_occurrence({module, function, arity}, caller, source) do
    module = canonical_module(module)

    case Policy.classify(module, function) do
      nil ->
        []

      class ->
        [
          %{
            path: source,
            line: 1,
            function: nil,
            caller: canonical_module(caller),
            class: class,
            construct: Policy.construct(module, function),
            target_module: module,
            target_function: function,
            target_arity: arity,
            approval: :compiled_dependency
          }
        ]
    end
  end

  defp allowed_import?(source, occurrence) do
    source
    |> then(&Map.get(@allowed_imports, &1, MapSet.new()))
    |> MapSet.member?(
      {occurrence.target_module, occurrence.target_function, occurrence.target_arity}
    )
  end

  defp source_path(compile_info, root) when is_list(compile_info) do
    case Keyword.get(compile_info, :source) do
      source when is_list(source) -> normalize_source(List.to_string(source), root)
      source when is_binary(source) -> normalize_source(source, root)
      _missing -> {:error, :source_missing}
    end
  end

  defp source_path(_compile_info, _root), do: {:error, :compile_info_missing}

  defp normalize_source(source, root) do
    source = Path.expand(source, root)
    root = Path.expand(root)

    if source == root or String.starts_with?(source, root <> "/") do
      {:ok, Path.relative_to(source, root)}
    else
      {:error, :source_outside_repository}
    end
  end

  defp metadata_unavailable(path, caller, reason, root) do
    %{
      path: Path.relative_to(path, root),
      line: 1,
      function: nil,
      caller: canonical_module(caller),
      class: :direct_ecto,
      construct: "compiled.metadata_unavailable",
      target_module: "unknown",
      target_function: nil,
      target_arity: 0,
      approval: {:metadata_unavailable, reason}
    }
  end

  defp missing_environment({environment, path}) do
    %{
      path: path,
      line: 1,
      function: nil,
      caller: "unknown",
      class: :direct_ecto,
      construct: "compiled.environment_missing",
      target_module: to_string(environment),
      target_function: nil,
      target_arity: 0,
      ordinal: 1,
      fingerprint: fingerprint({environment, path}),
      approval: :environment_missing
    }
  end

  defp assign_fingerprints(occurrences) do
    Enum.map(occurrences, fn occurrence ->
      occurrence
      |> Map.put(:ordinal, 1)
      |> Map.put(
        :fingerprint,
        fingerprint({
          occurrence.path,
          occurrence.caller,
          occurrence.target_module,
          occurrence.target_function,
          occurrence.target_arity
        })
      )
    end)
  end

  defp fingerprint(value) do
    value
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> then(&"sha256:#{&1}")
  end

  defp canonical_module(nil), do: "unknown"

  defp canonical_module(module) when is_atom(module),
    do: module |> Atom.to_string() |> String.trim_leading("Elixir.")

  defp canonical_module(module), do: to_string(module)
end
