defmodule OfficeGraph.ProjectQuality.DatabasePrimitiveScanner do
  @moduledoc """
  Finds explicit database primitives without interpreting application flow.

  Unsupported persistence indirection and executable-script database tokens
  fail closed. Compiler-resolved aliases and imports are handled by the
  independent BEAM dependency audit.
  """

  alias OfficeGraph.ProjectQuality.DatabasePrimitivePolicy, as: Policy

  @sql_file_pattern ~r/\.(?:pgsql|psql|sql)(?:\.(?:eex|heex|leex))?\z/i
  @script_extensions ~w(.bash .cjs .js .mjs .py .sh .ts .zsh)
  @database_clients ~w(
    clusterdb createdb createuser dropdb dropuser pg_basebackup pg_receivewal
    pg_recvlogical pgbench pg_dump pg_restore psql reindexdb vacuumdb
  )
  @client_pattern Regex.compile!("\\b(" <> Enum.join(@database_clients, "|") <> ")\\b")

  @migration_control_flow [:case, :cond, :for, :if, :receive, :try, :unless, :with]
  @allowed_migration_locals [
    :add,
    :add_if_not_exists,
    :alter,
    :constraint,
    :create,
    :create_if_not_exists,
    :drop,
    :drop_if_exists,
    :execute,
    :execute_file,
    :flush,
    :fragment,
    :index,
    :modify,
    :references,
    :remove,
    :remove_if_exists,
    :rename,
    :table,
    :unique_index
  ]
  @syntax_operations [
    :%,
    :%{},
    :&,
    :.,
    :<>,
    :<-,
    :=,
    :@,
    :__aliases__,
    :__block__,
    :{},
    :fn,
    :when,
    :|
  ]
  @preserved_fingerprints %{
    {"priv/repo/migrations/20260729233957_initial.exs", 4892, "raw_sql", "fragment", "up/0", 1} =>
      %{
        fingerprint: "sha256:1c00daebdd2b1e43f8c59ea6a36b5a9606bf15f2292cd69cfa6c02b974e0717b",
        payload: ~S|fragment("uuidv7()")|
      },
    {"priv/repo/migrations/20260730005539_integrate_workos_enterprise_identity.exs", 340,
     "raw_sql", "fragment", "up/0", 1} => %{
      fingerprint: "sha256:3fbfef45542e6568ac392c69d0849a575ae68dc51670f05002e2bb1abfc124f8",
      payload: ~S|fragment("uuidv7()")|
    }
  }
  @approved_migration_hashes %{
    "priv/repo/migrations/20260729233957_initial.exs" =>
      "9bc5e6aee67201982320a35c4a985fdc12dbfa03695117035fb244020a203233",
    "priv/repo/migrations/20260730005539_integrate_workos_enterprise_identity.exs" =>
      "cec2b703b975559c23619f5529b158f10de899216562cb3e716c4af0b3586b76"
  }

  @spec scan_repository(Path.t()) :: [map()]
  def scan_repository(root \\ File.cwd!()) do
    case System.cmd("git", ["ls-files", "-z"], cd: root, stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split(<<0>>, trim: true)
        |> Enum.flat_map(&tracked_source(&1, root))
        |> scan_sources()

      {output, status} ->
        raise "git ls-files failed with status #{status}: #{String.trim(output)}"
    end
  end

  @spec scan_sources([%{required(:path) => String.t(), required(:source) => String.t()}]) ::
          [map()]
  def scan_sources(sources) do
    sources
    |> Enum.flat_map(&scan_source/1)
    |> Enum.sort_by(&{&1.path, &1.line, &1.construct})
    |> assign_ordinals()
  end

  defp tracked_source(path, root) do
    full_path = Path.join(root, path)

    if boundary_path?(path) or script_shebang?(full_path) do
      [%{path: path, source: File.read!(full_path)}]
    else
      []
    end
  end

  defp boundary_path?(path) do
    extension = String.downcase(Path.extname(path))

    extension in [".ex", ".exs"] or Regex.match?(@sql_file_pattern, path) or
      String.starts_with?(path, "bin/") or extension in @script_extensions
  end

  defp script_shebang?(path) do
    case File.open(path, [:read, :binary], &IO.binread(&1, :line)) do
      {:ok, "#!" <> _command} -> true
      _other -> false
    end
  end

  defp scan_source(%{path: path, source: source}) do
    cond do
      Regex.match?(@sql_file_pattern, path) -> scan_sql_file(path, source)
      String.downcase(Path.extname(path)) in [".ex", ".exs"] -> scan_elixir(path, source)
      true -> scan_script(path, source)
    end
  end

  defp scan_sql_file(path, source) do
    executable =
      source
      |> String.replace(~r/\/\*.*?\*\//s, "")
      |> String.replace(~r/--[^\n]*/, "")
      |> String.trim()

    if executable == "" do
      []
    else
      [base_occurrence(path, 1, nil, :raw_sql, "sql_file", source)]
    end
  end

  defp scan_script(path, source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      for [_, client] <- Regex.scan(@client_pattern, line) do
        path
        |> base_occurrence(
          line_number,
          nil,
          :database_client,
          "script.#{client}",
          String.trim(line)
        )
        |> Map.put(:approval, :unsupported_script_token)
      end
    end)
  end

  defp scan_elixir(path, source) do
    case Code.string_to_quoted(source, file: path, columns: true) do
      {:ok, ast} ->
        env = %{
          function: nil,
          migration?: String.starts_with?(path, "priv/repo/migrations/"),
          migration_entrypoint?: false,
          path: path,
          preserve_uuidv7?: approved_migration?(path, source)
        }

        scan_node(ast, env)

      {:error, {location, error, token}} ->
        [
          path
          |> base_occurrence(
            error_line(location),
            nil,
            :direct_ecto,
            "source.parse_error",
            "#{error}#{token}"
          )
          |> Map.put(:approval, :unsupported_source)
        ]
    end
  end

  defp scan_node({:quote, _metadata, _arguments}, _env), do: []

  defp scan_node({kind, _metadata, arguments}, env) when kind in [:def, :defp] do
    {name, arity} = function_identity(arguments)
    function = if name, do: "#{name}/#{arity}"
    entrypoint? = env.migration? and name in [:up, :down, :change]

    helper_occurrences =
      if env.migration? and name not in [:up, :down, :change] do
        [unsupported(env, line_from(arguments), "migration.helper_definition", {kind, arguments})]
      else
        []
      end

    body = function_body(arguments)
    defaults = function_defaults(arguments)
    child_env = %{env | function: function, migration_entrypoint?: entrypoint?}

    helper_occurrences ++ scan_node(defaults, child_env) ++ scan_node(body, child_env)
  end

  defp scan_node({:defdelegate, metadata, arguments} = node, env) do
    target = arguments |> List.last() |> keyword_value(:to) |> module_name()

    if target && Policy.low_level_module?(target) do
      [unsupported(env, line(metadata), "source.unsupported_delegate", node)]
    else
      scan_children(node, env)
    end
  end

  defp scan_node(
         {:&, metadata,
          [{:/, _slash_metadata, [{{:., _, [receiver, _operation]}, _, _}, _arity]}]} =
           node,
         env
       ) do
    if receiver |> module_name() |> low_level_module?() do
      [unsupported(env, line(metadata), "source.unsupported_capture", node)]
    else
      []
    end
  end

  defp scan_node({:apply, metadata, [receiver, _operation, _arguments]} = node, env) do
    if receiver |> module_name() |> low_level_module?() do
      [unsupported(env, line(metadata), "source.unsupported_reflection", node)]
    else
      scan_children(node, env)
    end
  end

  defp scan_node(
         {{:., _, [apply_module, :apply]}, metadata, [receiver, _operation, _arguments]} = node,
         env
       ) do
    if module_name(apply_module) in ["Kernel", "erlang"] and
         receiver |> module_name() |> low_level_module?() do
      [unsupported(env, line(metadata), "source.unsupported_reflection", node)]
    else
      scan_children(node, env)
    end
  end

  defp scan_node({:for, metadata, _arguments} = node, env)
       when env.migration_entrypoint? do
    occurrences =
      if env.preserve_uuidv7? and contains_uuidv7_fragment?(node) do
        []
      else
        [unsupported(env, line(metadata), "migration.unsupported_control_flow", node)]
      end

    occurrences ++ scan_children(node, env)
  end

  defp scan_node({operation, metadata, _arguments} = node, env)
       when operation in @migration_control_flow and env.migration_entrypoint? do
    [unsupported(env, line(metadata), "migration.unsupported_control_flow", node)] ++
      scan_children(node, env)
  end

  defp scan_node({{:., _, [receiver, operation]}, metadata, arguments} = node, env)
       when is_atom(operation) and is_list(arguments) do
    module = module_name(receiver)

    occurrence =
      case module && Policy.classify(module, operation) do
        nil -> migration_remote_occurrence(module, operation, node, metadata, env)
        class -> classified_occurrence(module, operation, arguments, node, metadata, env, class)
      end

    List.wrap(occurrence) ++ scan_node(arguments, env)
  end

  defp scan_node({operation, metadata, arguments} = node, env)
       when is_atom(operation) and is_list(arguments) do
    occurrence = migration_local_occurrence(operation, arguments, node, metadata, env)
    List.wrap(occurrence) ++ scan_node(arguments, env)
  end

  defp scan_node(nodes, env) when is_list(nodes), do: Enum.flat_map(nodes, &scan_node(&1, env))
  defp scan_node(node, env) when is_tuple(node), do: scan_children(node, env)
  defp scan_node(_node, _env), do: []

  defp scan_children(node, env) do
    node
    |> Tuple.to_list()
    |> Enum.flat_map(&scan_node(&1, env))
  end

  defp classified_occurrence(module, operation, arguments, node, metadata, env, class) do
    construct = Policy.construct(module, operation)

    env.path
    |> base_occurrence(line(metadata), env.function, class, construct, node,
      target_module: module,
      target_function: operation,
      target_arity: length(arguments),
      preserve_fingerprint?: env.preserve_uuidv7?
    )
    |> maybe_mark_dynamic_sql(class, module, arguments)
  end

  defp migration_local_occurrence(:fragment, arguments, node, metadata, env)
       when env.migration_entrypoint? do
    classified_occurrence("Ecto.Migration", :fragment, arguments, node, metadata, env, :raw_sql)
    |> Map.put(:construct, "fragment")
  end

  defp migration_local_occurrence(operation, arguments, node, metadata, env)
       when env.migration_entrypoint? and operation in [:execute, :execute_file] do
    env.path
    |> base_occurrence(
      line(metadata),
      env.function,
      :raw_sql,
      "migration.#{operation}",
      node,
      target_module: "Ecto.Migration",
      target_function: operation,
      target_arity: length(arguments)
    )
    |> maybe_mark_dynamic_sql(:raw_sql, "Ecto.Migration", arguments)
  end

  defp migration_local_occurrence(operation, arguments, node, metadata, env)
       when env.migration_entrypoint? and operation in [:insert, :repo] do
    base_occurrence(
      env.path,
      line(metadata),
      env.function,
      :direct_ecto,
      "migration.#{operation}",
      node,
      target_module: "Ecto.Migration",
      target_function: operation,
      target_arity: length(arguments)
    )
  end

  defp migration_local_occurrence(operation, _arguments, node, metadata, env)
       when env.migration_entrypoint? and operation not in @allowed_migration_locals and
              operation not in @syntax_operations do
    if operator?(operation) do
      nil
    else
      unsupported(env, line(metadata), "migration.unsupported_call", node)
    end
  end

  defp migration_local_occurrence(_operation, _arguments, _node, _metadata, _env), do: nil

  defp migration_remote_occurrence("Oban.Migrations", operation, _node, _metadata, env)
       when env.migration_entrypoint? and operation in [:up, :down],
       do: nil

  defp migration_remote_occurrence(module, _operation, node, metadata, env)
       when env.migration_entrypoint? and is_binary(module) do
    unsupported(env, line(metadata), "migration.unsupported_remote_call", node)
  end

  defp migration_remote_occurrence(_module, _operation, _node, _metadata, _env), do: nil

  defp unsupported(env, line, construct, node) do
    env.path
    |> base_occurrence(line, env.function, :direct_ecto, construct, node)
    |> Map.put(:approval, :unsupported_indirection)
  end

  defp maybe_mark_dynamic_sql(occurrence, :raw_sql, module, arguments) do
    payload = sql_payload(module, occurrence.target_function, arguments)

    if static_sql?(payload) do
      occurrence
    else
      Map.put(occurrence, :approval, :unresolved_sql)
    end
  end

  defp maybe_mark_dynamic_sql(occurrence, _class, _module, _arguments), do: occurrence

  defp sql_payload("Ecto.Adapters.SQL", _operation, [_repo, sql | _rest]), do: sql
  defp sql_payload(_module, _operation, [sql | _rest]), do: sql
  defp sql_payload(_module, _operation, _arguments), do: nil

  defp static_sql?(value) when is_binary(value), do: true
  defp static_sql?({:<<>>, _metadata, segments}), do: Enum.all?(segments, &is_binary/1)

  defp static_sql?({sigil, _metadata, [{:<<>>, _, segments}, modifiers]})
       when sigil in [:sigil_S, :sigil_s] and is_list(modifiers),
       do: Enum.all?(segments, &is_binary/1)

  defp static_sql?(_value), do: false

  defp low_level_module?(nil), do: false
  defp low_level_module?(module), do: Policy.low_level_module?(module)

  defp module_name({:__aliases__, _metadata, parts}) do
    if Enum.all?(parts, &is_atom/1), do: Enum.join(parts, ".")
  end

  defp module_name(atom) when is_atom(atom),
    do: atom |> Atom.to_string() |> String.trim_leading("Elixir.")

  defp module_name(_node), do: nil

  defp function_identity([{:when, _metadata, [signature | _guards]} | _rest]),
    do: function_signature(signature)

  defp function_identity([signature | _rest]), do: function_signature(signature)
  defp function_identity(_arguments), do: {nil, 0}

  defp function_signature({name, _metadata, arguments}) when is_atom(name) and is_list(arguments),
    do: {name, length(arguments)}

  defp function_signature({name, _metadata, _context}) when is_atom(name), do: {name, 0}
  defp function_signature(_signature), do: {nil, 0}

  defp function_body(arguments) do
    arguments
    |> List.last()
    |> case do
      options when is_list(options) -> Keyword.get(options, :do)
      _other -> nil
    end
  end

  defp function_defaults([signature | _rest]) do
    signature
    |> unwrap_guard()
    |> case do
      {_name, _metadata, arguments} when is_list(arguments) ->
        Enum.flat_map(arguments, fn
          {:\\, _metadata, [_pattern, default]} -> [default]
          _argument -> []
        end)

      _signature ->
        []
    end
  end

  defp function_defaults(_arguments), do: []
  defp unwrap_guard({:when, _metadata, [signature | _guards]}), do: signature
  defp unwrap_guard(signature), do: signature

  defp keyword_value(value, key) when is_list(value) do
    if Keyword.keyword?(value), do: Keyword.get(value, key)
  end

  defp keyword_value(_value, _key), do: nil

  defp contains_uuidv7_fragment?({:fragment, _metadata, ["uuidv7()"]}), do: true

  defp contains_uuidv7_fragment?(node) when is_tuple(node) do
    node |> Tuple.to_list() |> Enum.any?(&contains_uuidv7_fragment?/1)
  end

  defp contains_uuidv7_fragment?(nodes) when is_list(nodes),
    do: Enum.any?(nodes, &contains_uuidv7_fragment?/1)

  defp contains_uuidv7_fragment?(_node), do: false

  defp operator?(operation),
    do: operation |> to_string() |> String.match?(~r/\A[^\p{L}\p{N}_]+\z/u)

  defp line_from(arguments) do
    arguments
    |> List.first()
    |> case do
      {_name, metadata, _arguments} when is_list(metadata) -> line(metadata)
      _signature -> 1
    end
  end

  defp line(metadata) when is_list(metadata), do: Keyword.get(metadata, :line, 1)
  defp line(line) when is_integer(line), do: line
  defp line(_metadata), do: 1
  defp error_line({line, _column}) when is_integer(line), do: line
  defp error_line(line) when is_integer(line), do: line
  defp error_line(_location), do: 1

  defp approved_migration?(path, source) do
    case Map.fetch(@approved_migration_hashes, path) do
      {:ok, hash} -> sha256(source) == hash
      :error -> false
    end
  end

  defp base_occurrence(path, line, function, class, construct, node, opts \\ []) do
    %{
      path: path,
      line: line || 1,
      function: function,
      class: class,
      construct: construct,
      normalized: printable_node(node),
      preserve_fingerprint?: Keyword.get(opts, :preserve_fingerprint?, false),
      target_module: Keyword.get(opts, :target_module),
      target_function: Keyword.get(opts, :target_function),
      target_arity: Keyword.get(opts, :target_arity)
    }
  end

  defp assign_ordinals(occurrences) do
    {occurrences, _counts} =
      Enum.map_reduce(occurrences, %{}, fn occurrence, counts ->
        key = {occurrence.path, occurrence.class, occurrence.construct, occurrence.function}
        ordinal = Map.get(counts, key, 0) + 1
        occurrence = Map.put(occurrence, :ordinal, ordinal)
        occurrence = Map.put(occurrence, :fingerprint, fingerprint(occurrence))

        occurrence =
          occurrence
          |> Map.drop([:normalized, :preserve_fingerprint?])
          |> drop_nil_targets()

        {occurrence, Map.put(counts, key, ordinal)}
      end)

    occurrences
  end

  defp fingerprint(occurrence) do
    preserved_key = {
      occurrence.path,
      occurrence.line,
      to_string(occurrence.class),
      occurrence.construct,
      occurrence.function,
      occurrence.ordinal
    }

    case Map.get(@preserved_fingerprints, preserved_key) do
      %{payload: payload, fingerprint: fingerprint}
      when payload == occurrence.normalized and occurrence.preserve_fingerprint? ->
        fingerprint

      _other ->
        [
          occurrence.path,
          occurrence.class,
          occurrence.construct,
          occurrence.function || "<module>",
          occurrence.ordinal,
          occurrence.normalized
        ]
        |> Enum.join("\n")
        |> sha256()
        |> then(&"sha256:#{&1}")
    end
  end

  defp drop_nil_targets(occurrence) do
    Enum.reduce([:target_module, :target_function, :target_arity], occurrence, fn key, result ->
      if is_nil(Map.get(result, key)), do: Map.delete(result, key), else: result
    end)
  end

  defp printable_node(value) when is_binary(value), do: value

  defp printable_node(node) do
    Macro.to_string(node)
  rescue
    _error -> inspect(node)
  end

  defp sha256(value), do: Base.encode16(:crypto.hash(:sha256, value), case: :lower)
end
