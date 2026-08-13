defmodule OfficeGraph.ProjectQuality.DatabaseDependencyAudit do
  @moduledoc """
  Audits compiler-resolved direct database dependencies in project BEAMs.

  BEAM import metadata catches ordinary aliases, imports, and macro-generated
  direct calls. It intentionally does not inspect callback targets or abstract
  control flow.
  """

  @required_environments [:test, :prod]
  @allowed_imports %{
    "lib/office_graph/application.ex" => MapSet.new([{"Ecto.DevLogger", :install, 1}])
  }
  @fully_owned_sources MapSet.new(["lib/office_graph/repo.ex"])
  @raw_sql_modules MapSet.new([
                     "DBConnection",
                     "Ecto.Adapters.SQL",
                     "Postgrex",
                     "Postgrex.Notifications",
                     "Postgrex.SimpleConnection"
                   ])
  @direct_modules MapSet.new([
                    "Ecto.Adapters.Postgres",
                    "Ecto.Migration.Runner",
                    "Ecto.Migrator",
                    "Ecto.Multi",
                    "Ecto.Repo.Queryable",
                    "Ecto.Repo.Registry",
                    "Ecto.Repo.Schema",
                    "Ecto.Repo.Supervisor",
                    "Ecto.Repo.Transaction"
                  ])
  @repo_raw_sql_operations MapSet.new([:query, :query!, :query_many, :query_many!])
  @repo_direct_operations MapSet.new([
                            :aggregate,
                            :all,
                            :all_by,
                            :checked_out?,
                            :checkout,
                            :delete,
                            :delete!,
                            :delete_all,
                            :disconnect_all,
                            :exists?,
                            :get,
                            :get!,
                            :get_by,
                            :get_by!,
                            :get_dynamic_repo,
                            :in_transaction?,
                            :insert,
                            :insert!,
                            :insert_all,
                            :insert_or_update,
                            :insert_or_update!,
                            :load,
                            :one,
                            :one!,
                            :preload,
                            :preload!,
                            :put_dynamic_repo,
                            :reload,
                            :reload!,
                            :rollback,
                            :start_link,
                            :stop,
                            :stream,
                            :transact,
                            :transaction,
                            :update,
                            :update!,
                            :update_all
                          ])

  @spec scan(Path.t(), keyword()) :: [map()]
  def scan(root \\ File.cwd!(), opts \\ []) do
    {paths, missing_environments} = beam_paths(root, opts)
    tracked_paths = Keyword.get_lazy(opts, :tracked_paths, fn -> tracked_paths(root) end)

    occurrences =
      paths
      |> Enum.flat_map(&scan_beam(&1, root, tracked_paths))
      |> Enum.uniq_by(&{&1.path, &1.class, &1.construct, &1.module, &1.arity})

    (occurrences ++ Enum.map(missing_environments, &missing_environment_occurrence/1))
    |> Enum.sort_by(&{&1.path, &1.construct, &1.module, &1.arity})
    |> assign_ordinals()
  end

  defp beam_paths(root, opts) do
    case Keyword.fetch(opts, :paths) do
      {:ok, paths} ->
        {paths, []}

      :error ->
        default_environments =
          if Path.expand(root) == Path.expand(File.cwd!()), do: @required_environments, else: []

        environments = Keyword.get(opts, :environments, default_environments)

        Enum.reduce(environments, {[], []}, fn environment, {paths, missing} ->
          environment_paths =
            root
            |> Path.join("_build/#{environment}/lib/office_graph/ebin/Elixir.OfficeGraph*.beam")
            |> Path.wildcard()

          if environment_paths == [] do
            {paths, [environment | missing]}
          else
            {environment_paths ++ paths, missing}
          end
        end)
    end
  end

  defp tracked_paths(root) do
    case System.cmd("git", ["ls-files", "-z"], cd: root, stderr_to_stdout: true) do
      {output, 0} ->
        output |> String.split(<<0>>, trim: true) |> MapSet.new()

      {output, status} ->
        raise "git ls-files failed with status #{status}: #{String.trim(output)}"
    end
  end

  defp scan_beam(path, root, tracked_paths) do
    case :beam_lib.chunks(String.to_charlist(path), [:imports, :compile_info]) do
      {:ok, {module, chunks}} ->
        with {:ok, source} <- source_path(chunks[:compile_info], root),
             true <- MapSet.member?(tracked_paths, source) do
          if MapSet.member?(@fully_owned_sources, source) do
            []
          else
            chunks[:imports]
            |> Enum.flat_map(&import_occurrence(&1, module, source))
            |> Enum.reject(&allowed_import?(source, &1))
          end
        else
          false -> []
          {:error, reason} -> [metadata_occurrence(path, module, reason, root)]
        end

      {:error, reason} ->
        [metadata_occurrence(path, nil, reason, root)]
    end
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

    if source == root or String.starts_with?(source, root <> "/") do
      {:ok, Path.relative_to(source, root)}
    else
      {:error, :source_outside_repository}
    end
  end

  defp import_occurrence({module, function, arity}, caller, source) do
    module = canonical_module(module)

    cond do
      module == "OfficeGraph.Repo" and MapSet.member?(@repo_raw_sql_operations, function) ->
        [occurrence(source, caller, module, function, arity, :raw_sql)]

      module == "OfficeGraph.Repo" and MapSet.member?(@repo_direct_operations, function) ->
        [occurrence(source, caller, module, function, arity, :direct_ecto)]

      MapSet.member?(@raw_sql_modules, module) ->
        [occurrence(source, caller, module, function, arity, :raw_sql)]

      MapSet.member?(@direct_modules, module) ->
        [occurrence(source, caller, module, function, arity, :direct_ecto)]

      true ->
        []
    end
  end

  defp allowed_import?(source, occurrence) do
    source
    |> then(&Map.get(@allowed_imports, &1, MapSet.new()))
    |> MapSet.member?({occurrence.module, occurrence.operation, occurrence.arity})
  end

  defp occurrence(source, caller, module, function, arity, class) do
    construct = construct(module, function)

    %{
      arity: arity,
      class: class,
      construct: construct,
      fingerprint_input: {caller, module, function, arity},
      function: nil,
      line: 1,
      module: module,
      operation: function,
      ordinal: 1,
      path: source
    }
  end

  defp metadata_occurrence(path, caller, reason, root) do
    %{
      arity: 0,
      class: :direct_ecto,
      construct: "compiled.metadata_unavailable",
      fingerprint_input: {Path.relative_to(path, root), reason},
      function: nil,
      line: 1,
      module: canonical_module(caller),
      operation: nil,
      ordinal: 1,
      path: Path.relative_to(path, root)
    }
  end

  defp missing_environment_occurrence(environment) do
    %{
      arity: 0,
      class: :direct_ecto,
      construct: "compiled.environment_missing",
      fingerprint_input: environment,
      function: nil,
      line: 1,
      module: to_string(environment),
      operation: nil,
      ordinal: 1,
      path: "_build/#{environment}/lib/office_graph/ebin"
    }
  end

  defp construct("OfficeGraph.Repo", function), do: "Repo.#{function}"
  defp construct(module, function), do: "#{module}.#{function}"

  defp canonical_module(nil), do: "unknown"

  defp canonical_module(module) when is_atom(module) do
    module |> Atom.to_string() |> String.trim_leading("Elixir.")
  end

  defp canonical_module(module), do: to_string(module)

  defp assign_ordinals(occurrences) do
    {occurrences, _counts} =
      Enum.map_reduce(occurrences, %{}, fn occurrence, counts ->
        key = {occurrence.path, occurrence.class, occurrence.construct, occurrence.function}
        ordinal = Map.get(counts, key, 0) + 1

        fingerprint =
          {
            occurrence.path,
            occurrence.class,
            occurrence.construct,
            occurrence.function,
            ordinal,
            occurrence.fingerprint_input
          }
          |> :erlang.term_to_binary()
          |> then(&:crypto.hash(:sha256, &1))
          |> Base.encode16(case: :lower)
          |> then(&"sha256:#{&1}")

        occurrence =
          occurrence
          |> Map.drop([:fingerprint_input])
          |> Map.merge(%{fingerprint: fingerprint, ordinal: ordinal})

        {occurrence, Map.put(counts, key, ordinal)}
      end)

    occurrences
  end
end
