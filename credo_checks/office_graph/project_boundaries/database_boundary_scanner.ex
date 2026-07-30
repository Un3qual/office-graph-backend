defmodule OfficeGraph.ProjectQuality.DatabaseBoundaryScanner do
  @moduledoc """
  Finds repository-owned database access that must be removed or explicitly
  approved.

  The scanner parses Elixir syntax and returns deterministic occurrence
  fingerprints. It does not execute source files or write inventories.
  """

  @spec scan_sources([%{required(:path) => String.t(), required(:source) => String.t()}]) ::
          [map()]
  def scan_sources(sources) do
    sources
    |> Enum.filter(&eligible_source?/1)
    |> Enum.flat_map(&scan_source/1)
    |> Enum.sort_by(&{&1.path, &1.line, &1.construct})
    |> add_ordinals_and_fingerprints()
  end

  @spec scan_repository(Path.t()) :: [map()]
  def scan_repository(root \\ File.cwd!()) do
    case System.cmd("git", ["ls-files", "-z"], cd: root, stderr_to_stdout: true) do
      {tracked_files, 0} ->
        tracked_files
        |> String.split("\0", trim: true)
        |> Enum.filter(&eligible_path?/1)
        |> Enum.flat_map(fn path ->
          full_path = Path.join(root, path)

          case File.read(full_path) do
            {:ok, source} ->
              [%{path: path, source: source}]

            {:error, :enoent} ->
              []

            {:error, reason} ->
              raise File.Error, reason: reason, action: "read file", path: full_path
          end
        end)
        |> scan_sources()

      {error, status} ->
        raise "git ls-files failed with status #{status}: #{String.trim(error)}"
    end
  end

  defp scan_source(%{path: path, source: source}) when is_binary(source) do
    if Path.extname(path) == ".sql" do
      if String.trim(source) == "" do
        []
      else
        [occurrence(path, 1, nil, :raw_sql, "sql_file", String.trim(source))]
      end
    else
      scan_elixir_source(path, source)
    end
  end

  defp scan_elixir_source(path, source) do
    migration? = migration_path?(path)
    ast = Code.string_to_quoted!(source, file: path, columns: true)
    declarations = function_declarations(ast)
    aliases = database_alias_declarations(ast)

    {_ast, occurrences} =
      Macro.prewalk(ast, [], fn node, occurrences ->
        case classify_node(node, migration?, aliases) do
          nil ->
            {node, occurrences}

          {class, construct} ->
            line = node_line(node)
            function = function_at_line(declarations, line)
            occurrence = occurrence(path, line, function, class, construct, node)
            {node, [occurrence | occurrences]}
        end
      end)

    Enum.reverse(occurrences)
  end

  @direct_repo_operations [
    :aggregate,
    :all,
    :delete,
    :delete!,
    :delete_all,
    :exists?,
    :get,
    :get!,
    :get_by,
    :get_by!,
    :insert,
    :insert!,
    :insert_all,
    :insert_or_update,
    :insert_or_update!,
    :one,
    :one!,
    :stream,
    :transaction,
    :update,
    :update!,
    :update_all
  ]

  @direct_multi_operations [
    :append,
    :delete,
    :delete_all,
    :error,
    :insert,
    :insert_all,
    :insert_or_update,
    :merge,
    :prepend,
    :put,
    :run,
    :update,
    :update_all
  ]

  @database_alias_targets [
    "Ecto.Adapters.SQL",
    "Ecto.Multi",
    "OfficeGraph.Repo",
    "Postgrex"
  ]

  defp classify_node(
         {{:., _dot_metadata, [receiver, operation]}, _metadata, _arguments} = node,
         _migration?,
         aliases
       ) do
    receiver =
      receiver
      |> receiver_name()
      |> resolve_receiver(aliases, node_line(node))

    cond do
      operation in [:query, :query!] and repo_receiver?(receiver) ->
        {:raw_sql, "Repo.#{operation}"}

      operation in [:query, :query!] and receiver in ["Ecto.Adapters.SQL", "Postgrex"] ->
        {:raw_sql, "#{receiver}.#{operation}"}

      repo_receiver?(receiver) and operation in @direct_repo_operations ->
        {:direct_ecto, "Repo.#{operation}"}

      receiver in ["Ecto.Multi", "Multi"] and operation in @direct_multi_operations ->
        {:direct_ecto, "Ecto.Multi.#{operation}"}

      true ->
        nil
    end
  end

  defp classify_node({construct, _metadata, arguments}, _migration?, _aliases)
       when construct in [:fragment, :unsafe_fragment] and is_list(arguments),
       do: {:raw_sql, to_string(construct)}

  defp classify_node({:execute, _metadata, arguments}, true, _aliases)
       when is_list(arguments) do
    if Enum.any?(arguments, &sql_literal?/1), do: {:raw_sql, "migration.execute"}
  end

  defp classify_node({:insert, _metadata, arguments}, true, _aliases) when is_list(arguments),
    do: {:direct_ecto, "migration.insert"}

  defp classify_node({key, value}, true, _aliases)
       when key in [:check, :where] and is_binary(value),
       do: {:raw_sql, "migration.#{key}"}

  defp classify_node(value, true, _aliases) when is_binary(value) do
    cond do
      Regex.match?(~r/\bmd5\s*\(/i, value) ->
        {:raw_sql, "migration.md5"}

      Regex.match?(~r/\binsert\s+into\b/i, value) ->
        {:raw_sql, "migration.insert"}

      true ->
        nil
    end
  end

  defp classify_node({:unsafe_fragment, sql}, _migration?, _aliases) when is_binary(sql),
    do: {:raw_sql, "unsafe_fragment"}

  defp classify_node(_node, _migration?, _aliases), do: nil

  defp database_alias_declarations(ast) do
    {_ast, declarations} =
      Macro.prewalk(ast, [], fn
        {:alias, metadata, arguments} = node, declarations ->
          case database_alias_declaration(metadata, arguments) do
            nil -> {node, declarations}
            declaration -> {node, [declaration | declarations]}
          end

        node, declarations ->
          {node, declarations}
      end)

    Enum.sort_by(declarations, &elem(&1, 0))
  end

  defp database_alias_declaration(metadata, [target]),
    do: database_alias_declaration(metadata, target, [])

  defp database_alias_declaration(metadata, [target, options]) when is_list(options),
    do: database_alias_declaration(metadata, target, options)

  defp database_alias_declaration(_metadata, _arguments), do: nil

  defp database_alias_declaration(metadata, target, options) do
    target_name = receiver_name(target)

    if target_name in @database_alias_targets do
      alias_name =
        options
        |> Keyword.get(:as)
        |> case do
          nil -> target_name |> String.split(".") |> List.last()
          explicit_alias -> receiver_name(explicit_alias)
        end

      if is_binary(alias_name) do
        {Keyword.get(metadata, :line, 1), alias_name, target_name}
      end
    end
  end

  defp function_declarations(ast) do
    {_ast, declarations} =
      Macro.prewalk(ast, [], fn
        {kind, metadata, [head, _body]} = node, declarations when kind in [:def, :defp] ->
          {node, [{Keyword.fetch!(metadata, :line), function_signature(head)} | declarations]}

        node, declarations ->
          {node, declarations}
      end)

    Enum.sort_by(declarations, &elem(&1, 0))
  end

  defp function_signature({:when, _metadata, [head | _guards]}), do: function_signature(head)

  defp function_signature({name, _metadata, arguments}) do
    "#{name}/#{length(arguments || [])}"
  end

  defp function_at_line(declarations, line) do
    declarations
    |> Enum.take_while(fn {declaration_line, _signature} -> declaration_line <= line end)
    |> List.last()
    |> case do
      nil -> nil
      {_line, signature} -> signature
    end
  end

  defp receiver_name({:__aliases__, _metadata, parts}) do
    if Enum.all?(parts, &is_atom/1), do: Enum.join(parts, ".")
  end

  defp receiver_name({name, _metadata, context}) when is_atom(name) and is_atom(context),
    do: to_string(name)

  defp receiver_name(_receiver), do: nil

  defp resolve_receiver(nil, _aliases, _line), do: nil

  defp resolve_receiver(receiver, aliases, line) do
    aliases
    |> Enum.take_while(fn {declaration_line, _alias_name, _target_name} ->
      declaration_line <= line
    end)
    |> Enum.reverse()
    |> Enum.find_value(receiver, fn
      {_declaration_line, ^receiver, target_name} -> target_name
      _other_alias -> nil
    end)
  end

  defp repo_receiver?(receiver), do: receiver in ["Repo", "OfficeGraph.Repo"]

  defp sql_literal?(value) when is_binary(value), do: true
  defp sql_literal?(values) when is_list(values), do: Enum.any?(values, &sql_literal?/1)
  defp sql_literal?(_value), do: false

  defp node_line({{:., _dot_metadata, _receiver_and_operation}, metadata, _arguments}),
    do: Keyword.get(metadata, :line, 1)

  defp node_line({_name, metadata, _arguments}) when is_list(metadata),
    do: Keyword.get(metadata, :line, 1)

  defp node_line(_node), do: 1

  defp eligible_source?(%{path: path}), do: eligible_path?(path)

  defp eligible_path?(path) do
    path = String.trim_leading(path, "./")
    extension = Path.extname(path)

    cond do
      excluded_path?(path) ->
        false

      extension == ".sql" ->
        true

      extension not in [".ex", ".exs"] ->
        false

      true ->
        String.starts_with?(path, "lib/") or
          String.starts_with?(path, "test/") or
          String.starts_with?(path, "priv/repo/migrations/") or
          path == "priv/repo/seeds.exs"
    end
  end

  defp excluded_path?(path) do
    Enum.any?(String.split(path, "/"), &(&1 in ["_build", "deps", "node_modules"]))
  end

  defp migration_path?(path), do: String.starts_with?(path, "priv/repo/migrations/")

  defp occurrence(path, line, function, class, construct, node_or_source) do
    normalized =
      if is_binary(node_or_source),
        do: node_or_source,
        else: Macro.to_string(node_or_source)

    %{
      path: path,
      line: line,
      function: function,
      class: class,
      construct: construct,
      normalized: normalized
    }
  end

  defp add_ordinals_and_fingerprints(occurrences) do
    {occurrences, _counts} =
      Enum.map_reduce(occurrences, %{}, fn occurrence, counts ->
        locator = {
          occurrence.path,
          occurrence.class,
          occurrence.construct,
          occurrence.function
        }

        ordinal = Map.get(counts, locator, 0) + 1

        fingerprint_input =
          Enum.join(
            [
              occurrence.path,
              occurrence.class,
              occurrence.construct,
              occurrence.function || "<module>",
              ordinal,
              occurrence.normalized
            ],
            "\n"
          )

        fingerprint =
          fingerprint_input
          |> then(&:crypto.hash(:sha256, &1))
          |> Base.encode16(case: :lower)
          |> then(&"sha256:#{&1}")

        finalized =
          occurrence
          |> Map.drop([:normalized])
          |> Map.merge(%{fingerprint: fingerprint, ordinal: ordinal})

        {finalized, Map.put(counts, locator, ordinal)}
      end)

    occurrences
  end
end
