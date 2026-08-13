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
  @ecto_sql_raw_sql_operations MapSet.new([
                                 :execute,
                                 :execute_ddl,
                                 :into,
                                 :query,
                                 :query!,
                                 :query_many,
                                 :query_many!,
                                 :reduce,
                                 :stream
                               ])
  @ecto_sql_direct_operations MapSet.new([
                                :checked_out?,
                                :checkout,
                                :disconnect_all,
                                :explain,
                                :in_transaction?,
                                :insert_all,
                                :rollback,
                                :table_exists?,
                                :to_sql,
                                :transaction
                              ])
  @postgrex_raw_sql_operations MapSet.new([
                                 :execute,
                                 :execute!,
                                 :prepare,
                                 :prepare!,
                                 :prepare_execute,
                                 :prepare_execute!,
                                 :query,
                                 :query!,
                                 :stream
                               ])
  @postgrex_direct_operations MapSet.new([
                                :call,
                                :child_spec,
                                :close,
                                :close!,
                                :listen,
                                :listen!,
                                :parameters,
                                :rollback,
                                :start_link,
                                :transaction,
                                :unlisten,
                                :unlisten!
                              ])
  @postgrex_modules MapSet.new([
                      "Postgrex",
                      "Postgrex.Notifications",
                      "Postgrex.ReplicationConnection",
                      "Postgrex.SimpleConnection"
                    ])
  @db_connection_raw_sql_operations MapSet.new([
                                      :execute,
                                      :execute!,
                                      :prepare,
                                      :prepare!,
                                      :prepare_execute,
                                      :prepare_execute!,
                                      :prepare_stream,
                                      :reduce,
                                      :stream
                                    ])
  @db_connection_direct_operations MapSet.new([
                                     :child_spec,
                                     :close,
                                     :close!,
                                     :disconnect_all,
                                     :get_connection_metrics,
                                     :rollback,
                                     :run,
                                     :start_link,
                                     :status,
                                     :transaction
                                   ])
  @postgres_connection_raw_sql_operations MapSet.new([
                                            :execute,
                                            :execute_ddl,
                                            :prepare_execute,
                                            :query
                                          ])
  @postgres_adapter_operations MapSet.new([
                                 :execute,
                                 :lock_for_migrations,
                                 :storage_down,
                                 :storage_status,
                                 :storage_up,
                                 :structure_dump,
                                 :structure_load
                               ])
  @ecto_migrator_operations MapSet.new([
                              :down,
                              :migrated_versions,
                              :migrations,
                              :run,
                              :start_link,
                              :up,
                              :with_repo
                            ])
  @multi_operations MapSet.new([
                      :all,
                      :append,
                      :delete,
                      :delete_all,
                      :error,
                      :exists?,
                      :insert,
                      :insert_all,
                      :insert_or_update,
                      :merge,
                      :one,
                      :prepend,
                      :put,
                      :run,
                      :update,
                      :update_all
                    ])
  @private_direct_modules MapSet.new([
                            "DBConnection.Holder",
                            "Ecto.Migration.Runner",
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
                            :explain,
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
      |> Enum.uniq_by(
        &{&1.path, &1.line, &1.class, &1.construct, &1.function, &1.ordinal, &1.caller, &1.module,
         &1.arity}
      )

    (occurrences ++ Enum.map(missing_environments, &missing_environment_occurrence/1))
    |> Enum.sort_by(&{&1.path, &1.construct, &1.caller, &1.module, &1.arity})
    |> assign_ordinals()
  end

  defp beam_paths(root, opts) do
    case Keyword.fetch(opts, :paths) do
      {:ok, paths} ->
        {paths, []}

      :error ->
        environments = Keyword.get(opts, :environments, @required_environments)

        builds =
          Enum.map(environments, fn environment ->
            {environment, "_build/#{environment}/lib/office_graph/ebin"}
          end)

        builds =
          if Keyword.get(opts, :include_test_modules, :test in environments) do
            builds ++ [{:test_modules, "_build/test/lib/office_graph/test_ebin"}]
          else
            builds
          end

        Enum.reduce(builds, {[], []}, fn {build, relative_path}, {paths, missing} ->
          environment_paths = root |> Path.join(relative_path <> "/*.beam") |> Path.wildcard()

          if environment_paths == [] do
            {paths, [{build, relative_path} | missing]}
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
            case compiled_occurrences(path, chunks[:imports], module, source) do
              {:ok, occurrences} ->
                occurrences
                |> Enum.reject(&allowed_import?(source, &1))
                |> assign_call_ordinals()

              {:error, reason} ->
                [metadata_occurrence(path, module, reason, root)]
            end
          end
        else
          false -> []
          {:error, reason} -> [metadata_occurrence(path, module, reason, root)]
        end

      {:error, reason} ->
        [metadata_occurrence(path, nil, reason, root)]
    end
  end

  defp compiled_occurrences(path, imports, caller, source) do
    classified_imports = Enum.flat_map(imports, &import_occurrence(&1, caller, source))

    case disassembled_calls(path, caller, source) do
      {:ok, calls} ->
        called_targets = MapSet.new(calls, &{&1.module, &1.operation, &1.arity})

        import_fallbacks =
          Enum.reject(
            classified_imports,
            &MapSet.member?(called_targets, {&1.module, &1.operation, &1.arity})
          )

        {:ok, calls ++ import_fallbacks}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp disassembled_calls(path, caller, source) do
    case :beam_disasm.file(String.to_charlist(path)) do
      {:beam_file, _module, _exports, _attributes, _compile_info, functions} ->
        calls =
          Enum.flat_map(functions, fn
            {:function, function, arity, _label, instructions} ->
              disassembled_function_calls(instructions, caller, source, function, arity)

            _unknown_entry ->
              []
          end)

        {:ok, calls}

      {:error, reason} ->
        {:error, {:disassembly_failed, reason}}

      other ->
        {:error, {:unexpected_disassembly, other}}
    end
  rescue
    error -> {:error, {:disassembly_failed, Exception.message(error)}}
  catch
    kind, reason -> {:error, {:disassembly_failed, {kind, reason}}}
  end

  defp disassembled_function_calls(instructions, caller, source, function, function_arity) do
    {calls, _line} =
      Enum.map_reduce(instructions, nil, fn instruction, line ->
        case instruction do
          {:line, locations} ->
            {[], source_line(locations, line)}

          _other ->
            calls =
              case external_call(instruction) do
                nil ->
                  []

                target ->
                  import_occurrence(target, caller, source,
                    function: compiled_function(function, function_arity),
                    line: line || 1
                  )
              end

            {calls, line}
        end
      end)

    List.flatten(calls)
  end

  defp source_line(locations, fallback) when is_list(locations) do
    Enum.find_value(locations, fallback, fn
      {:location, _path, line} when is_integer(line) and line > 0 -> line
      _other -> nil
    end)
  end

  defp source_line(_locations, fallback), do: fallback

  defp external_call({kind, _arity, {:extfunc, module, function, arity}})
       when kind in [:call_ext, :call_ext_only],
       do: {module, function, arity}

  defp external_call({:call_ext_last, _arity, {:extfunc, module, function, arity}, _deallocate}),
    do: {module, function, arity}

  defp external_call(_instruction), do: nil

  defp compiled_function(function, arity) do
    name = to_string(function)

    case Regex.run(~r/\A-(.+)\/(\d+)-fun-\d+-\z/, name) do
      [_full, outer_name, outer_arity] -> "#{outer_name}/#{outer_arity}"
      _ordinary_function -> "#{name}/#{arity}"
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

  defp import_occurrence(target, caller, source, opts \\ [])

  defp import_occurrence({module, function, arity}, caller, source, opts) do
    module = canonical_module(module)

    case operation_class(module, function) do
      nil -> []
      class -> [occurrence(source, caller, module, function, arity, class, opts)]
    end
  end

  defp operation_class(module, function) do
    cond do
      module == "OfficeGraph.Repo" and MapSet.member?(@repo_raw_sql_operations, function) ->
        :raw_sql

      module == "OfficeGraph.Repo" and MapSet.member?(@repo_direct_operations, function) ->
        :direct_ecto

      module == "Ecto.Adapters.SQL" and
          MapSet.member?(@ecto_sql_raw_sql_operations, function) ->
        :raw_sql

      module == "Ecto.Adapters.SQL" and
          MapSet.member?(@ecto_sql_direct_operations, function) ->
        :direct_ecto

      module == "Ecto.Adapters.Postgres.Connection" and
          MapSet.member?(@postgres_connection_raw_sql_operations, function) ->
        :raw_sql

      MapSet.member?(@postgrex_modules, module) and
          MapSet.member?(@postgrex_raw_sql_operations, function) ->
        :raw_sql

      MapSet.member?(@postgrex_modules, module) and
          MapSet.member?(@postgrex_direct_operations, function) ->
        :direct_ecto

      module == "DBConnection" and
          MapSet.member?(@db_connection_raw_sql_operations, function) ->
        :raw_sql

      module == "DBConnection" and
          MapSet.member?(@db_connection_direct_operations, function) ->
        :direct_ecto

      module == "Ecto.Adapters.Postgres" and
          MapSet.member?(@postgres_adapter_operations, function) ->
        :direct_ecto

      module == "Ecto.Migrator" and MapSet.member?(@ecto_migrator_operations, function) ->
        :direct_ecto

      module == "Ecto.Multi" and MapSet.member?(@multi_operations, function) ->
        :direct_ecto

      MapSet.member?(@private_direct_modules, module) ->
        :direct_ecto

      true ->
        nil
    end
  end

  defp allowed_import?(source, occurrence) do
    source
    |> then(&Map.get(@allowed_imports, &1, MapSet.new()))
    |> MapSet.member?({occurrence.module, occurrence.operation, occurrence.arity})
  end

  defp occurrence(source, caller, module, operation, arity, class, opts) do
    construct = construct(module, operation)

    %{
      arity: arity,
      caller: canonical_module(caller),
      class: class,
      construct: construct,
      fingerprint_input: {caller, module, operation, arity, opts[:function], opts[:line]},
      function: opts[:function],
      line: opts[:line] || 1,
      module: module,
      operation: operation,
      ordinal: 1,
      path: source
    }
  end

  defp metadata_occurrence(path, caller, reason, root) do
    %{
      arity: 0,
      caller: canonical_module(caller),
      class: :direct_ecto,
      construct: "compiled.metadata_unavailable",
      fingerprint_input: {Path.relative_to(path, root), reason},
      function: nil,
      line: 1,
      module: "unknown",
      operation: nil,
      ordinal: 1,
      path: Path.relative_to(path, root)
    }
  end

  defp missing_environment_occurrence({environment, path}) do
    %{
      arity: 0,
      caller: "unknown",
      class: :direct_ecto,
      construct: "compiled.environment_missing",
      fingerprint_input: environment,
      function: nil,
      line: 1,
      module: to_string(environment),
      operation: nil,
      ordinal: 1,
      path: path
    }
  end

  defp construct("OfficeGraph.Repo", function), do: "Repo.#{function}"
  defp construct(module, function), do: "#{module}.#{function}"

  defp canonical_module(nil), do: "unknown"

  defp canonical_module(module) when is_atom(module) do
    module |> Atom.to_string() |> String.trim_leading("Elixir.")
  end

  defp canonical_module(module), do: to_string(module)

  defp assign_call_ordinals(occurrences) do
    {occurrences, _counts} =
      Enum.map_reduce(occurrences, %{}, fn occurrence, counts ->
        key =
          {occurrence.path, occurrence.line, occurrence.class, occurrence.construct,
           occurrence.function}

        ordinal = Map.get(counts, key, 0) + 1
        {%{occurrence | ordinal: ordinal}, Map.put(counts, key, ordinal)}
      end)

    occurrences
  end

  defp assign_ordinals(occurrences) do
    {occurrences, _counts} =
      Enum.map_reduce(occurrences, %{}, fn occurrence, counts ->
        key =
          {occurrence.path, occurrence.line, occurrence.class, occurrence.construct,
           occurrence.function}

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
