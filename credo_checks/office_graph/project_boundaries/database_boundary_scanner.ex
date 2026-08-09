defmodule OfficeGraph.ProjectQuality.DatabaseBoundaryScanner do
  @moduledoc """
  Finds low-level database boundary primitives without interpreting project code.

  This scanner is intentionally shallow. It recognizes explicit source
  primitives, records exact fingerprints for approval matching, and marks
  persistence-sensitive dynamic escape paths as unresolved. It does not expand
  helpers, callbacks, SQL bodies, arbitrary control flow, or macros.
  """

  @repo_raw_sql_operations [:query, :query!, :query_many, :query_many!]
  @repo_direct_operations [
    :aggregate,
    :all,
    :checkout,
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
    :one,
    :one!,
    :preload,
    :rollback,
    :stream,
    :transaction,
    :transact,
    :update,
    :update!,
    :update_all
  ]
  @ecto_sql_raw_sql_operations [:execute, :query, :query!, :query_many, :query_many!, :stream]
  @ecto_sql_direct_operations [:checkout, :explain]
  @postgrex_raw_sql_operations [
    :execute,
    :execute!,
    :prepare,
    :prepare!,
    :query,
    :query!,
    :stream
  ]
  @multi_operations [
    :all,
    :delete,
    :delete_all,
    :exists?,
    :insert,
    :insert_all,
    :merge,
    :one,
    :run,
    :update,
    :update_all
  ]
  @query_fragment_operations [:fragment, :unsafe_fragment]
  @migration_raw_sql_operations [:execute, :execute_file]
  @migration_direct_operations [:insert]
  @migration_control_flow [:case, :cond, :if, :receive, :try, :with]
  @syntax_operations [
    :%,
    :%{},
    :&,
    :.,
    :<<>>,
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
  @database_modules [
    "Ecto.Adapters.SQL",
    "Ecto.Migration",
    "Ecto.Multi",
    "Ecto.Query.API",
    "OfficeGraph.Repo",
    "Postgrex"
  ]
  @sql_file_extensions [".pgsql", ".psql", ".sql"]
  @source_extensions [".ex", ".exs" | @sql_file_extensions]

  @preserved_fingerprints %{
    {"priv/repo/migrations/20260729233957_initial.exs", 4892, "raw_sql", "fragment", "up/0", 1} =>
      "sha256:1c00daebdd2b1e43f8c59ea6a36b5a9606bf15f2292cd69cfa6c02b974e0717b",
    {"priv/repo/migrations/20260730005539_integrate_workos_enterprise_identity.exs", 340,
     "raw_sql", "fragment", "up/0", 1} =>
      "sha256:3fbfef45542e6568ac392c69d0849a575ae68dc51670f05002e2bb1abfc124f8"
  }

  @spec scan_repository(Path.t()) :: [map()]
  def scan_repository(root \\ File.cwd!()) do
    root
    |> tracked_sources()
    |> scan_sources(root: root)
  end

  @spec scan_sources([map()], keyword()) :: [map()]
  def scan_sources(sources, opts \\ []) do
    root = Keyword.get(opts, :root, File.cwd!())

    sources
    |> Enum.flat_map(&scan_source(&1, root))
    |> assign_ordinals()
  end

  @spec scan_compiled(Path.t(), keyword()) :: [map()]
  def scan_compiled(root \\ File.cwd!(), opts \\ []) do
    paths = Keyword.get_lazy(opts, :paths, fn -> compiled_beam_paths(root) end)

    paths
    |> Enum.flat_map(&scan_beam(&1, root))
    |> assign_ordinals()
  end

  defp scan_source(%{path: path, source: source}, _root) do
    cond do
      sql_file?(path) ->
        [
          occurrence(
            path,
            1,
            nil,
            :raw_sql,
            "tracked_sql_file",
            source,
            approval: :unresolved_sql
          )
        ]

      elixir_source?(path) ->
        scan_elixir_source(path, source)

      true ->
        []
    end
  end

  defp scan_source(%{path: path}, root) do
    source = root |> Path.join(path) |> File.read!()
    scan_source(%{path: path, source: source}, root)
  end

  defp scan_elixir_source(path, source) do
    case Code.string_to_quoted(source, file: path, columns: true) do
      {:ok, ast} ->
        env = %{
          aliases: %{},
          function: nil,
          imports: %{},
          migration?: migration_path?(path),
          path: path
        }

        {_env, occurrences} = scan_node(ast, env, [])
        Enum.reverse(occurrences)

      {:error, {location, _error, _token}} ->
        [
          occurrence(path, error_line(location), nil, :direct_ecto, "unparseable_elixir", source,
            approval: :unresolved_sql
          )
        ]
    end
  end

  defp scan_node({:defmodule, _metadata, [_module, [do: body]]}, env, occurrences) do
    {_module_env, occurrences} = scan_node(body, %{env | aliases: %{}, imports: %{}}, occurrences)
    {env, occurrences}
  end

  defp scan_node({kind, metadata, arguments} = node, env, occurrences)
       when kind in [:def, :defp, :defmacro, :defmacrop] and is_list(arguments) do
    {name, arity} = function_identity(arguments)
    function = if name, do: "#{name}/#{arity}"
    body = function_body(arguments)

    child_env = %{env | function: function}
    {_child_env, occurrences} = scan_node(body, child_env, occurrences)

    if body == nil do
      scan_children(node, env, occurrences)
    else
      {_line, _metadata} = {line(metadata), metadata}
      {env, occurrences}
    end
  end

  defp scan_node({:__block__, _metadata, expressions}, env, occurrences)
       when is_list(expressions) do
    scan_expressions(expressions, env, occurrences)
  end

  defp scan_node({:alias, _metadata, arguments} = node, env, occurrences) do
    {env, alias_occurrences} = apply_alias(arguments, env)
    {env, occurrences ++ alias_occurrences_for(node, env, alias_occurrences)}
  end

  defp scan_node({:import, metadata, arguments}, env, occurrences) do
    {env, import_occurrences} = apply_import(arguments, metadata, env)
    {env, occurrences ++ import_occurrences}
  end

  defp scan_node({:for, metadata, arguments} = node, env, occurrences)
       when is_list(arguments) do
    occurrences =
      if migration_entrypoint?(env) and not approved_uuidv7_loop?(node, env) do
        [
          occurrence(env, line(metadata), :direct_ecto, "migration.control_flow", node,
            approval: :unresolved_sql
          )
          | occurrences
        ]
      else
        occurrences
      end

    scan_children(node, env, occurrences)
  end

  defp scan_node({operation, metadata, arguments} = node, env, occurrences)
       when operation in @migration_control_flow and is_list(arguments) do
    occurrences =
      if migration_entrypoint?(env) do
        [
          occurrence(env, line(metadata), :direct_ecto, "migration.control_flow", node,
            approval: :unresolved_sql
          )
          | occurrences
        ]
      else
        occurrences
      end

    scan_children(node, env, occurrences)
  end

  defp scan_node(
         {{:., dot_metadata, [receiver, operation]}, metadata, arguments} = node,
         env,
         occurrences
       )
       when is_atom(operation) and is_list(arguments) do
    occurrences =
      case classify_remote_call(receiver, operation, arguments, node, env) do
        nil -> occurrences
        occurrence -> [occurrence | occurrences]
      end

    occurrences =
      if dynamic_module_receiver?(receiver, env) do
        [
          occurrence(
            env,
            line(dot_metadata) || line(metadata),
            :raw_sql,
            "dynamic_receiver",
            node,
            approval: :unresolved_sql
          )
          | occurrences
        ]
      else
        occurrences
      end

    scan_children(node, env, occurrences)
  end

  defp scan_node({operation, metadata, arguments} = node, env, occurrences)
       when is_atom(operation) and is_list(arguments) do
    occurrences =
      case classify_local_call(operation, arguments, node, env) do
        nil -> occurrences
        occurrence -> [occurrence | occurrences]
      end

    occurrences =
      if migration_helper_escape?(operation, arguments, env) do
        [
          occurrence(env, line(metadata), :direct_ecto, "migration.helper_call", node,
            approval: :unresolved_sql
          )
          | occurrences
        ]
      else
        occurrences
      end

    scan_children(node, env, occurrences)
  end

  defp scan_node(nodes, env, occurrences) when is_list(nodes) do
    scan_expressions(nodes, env, occurrences)
  end

  defp scan_node(node, env, occurrences) when is_tuple(node) do
    scan_children(node, env, occurrences)
  end

  defp scan_node(_node, env, occurrences), do: {env, occurrences}

  defp scan_expressions(expressions, env, occurrences) do
    Enum.reduce(expressions, {env, occurrences}, fn expression, {env, occurrences} ->
      scan_node(expression, env, occurrences)
    end)
  end

  defp scan_children(node, env, occurrences) do
    node
    |> Tuple.to_list()
    |> scan_node(env, occurrences)
  end

  defp classify_remote_call(receiver, operation, arguments, node, env) do
    receiver
    |> receiver_name(env)
    |> classify_operation(operation, length(arguments), node, env)
  end

  defp classify_local_call(:apply, [receiver, operation | _rest], node, env) do
    classify_apply(receiver, operation, node, env)
  end

  defp classify_local_call(operation, arguments, node, env) do
    arity = length(arguments)

    with nil <- classify_migration_local(operation, arguments, node, env),
         receiver when not is_nil(receiver) <- imported_receiver(env, operation, arity) do
      classify_operation(receiver, operation, arity, node, env)
    end
  end

  defp classify_migration_local(operation, arguments, node, env)
       when operation in @migration_raw_sql_operations and env.migration? do
    class = :raw_sql
    construct = "migration.#{operation}"
    approval = approval_marker(class, construct, arguments)
    occurrence(env, line_from_node(node), class, construct, node, approval: approval)
  end

  defp classify_migration_local(operation, _arguments, node, env)
       when operation in @migration_direct_operations and env.migration? do
    occurrence(env, line_from_node(node), :direct_ecto, "migration.#{operation}", node)
  end

  defp classify_migration_local(operation, arguments, node, env)
       when operation in @query_fragment_operations do
    arity = length(arguments)

    case imported_receiver(env, operation, arity) do
      nil ->
        if env.migration? do
          approval = approval_marker(:raw_sql, to_string(operation), arguments)

          occurrence(env, line_from_node(node), :raw_sql, to_string(operation), node,
            approval: approval
          )
        end

      receiver ->
        classify_operation(receiver, operation, arity, node, env)
    end
  end

  defp classify_migration_local(_operation, _arguments, _node, _env), do: nil

  defp classify_operation("OfficeGraph.Repo", operation, _arity, node, env)
       when operation in @repo_raw_sql_operations do
    construct = "Repo.#{operation}"
    approval = approval_marker(:raw_sql, construct, call_arguments(node))
    occurrence(env, line_from_node(node), :raw_sql, construct, node, approval: approval)
  end

  defp classify_operation("OfficeGraph.Repo", operation, _arity, node, env)
       when operation in @repo_direct_operations do
    occurrence(env, line_from_node(node), :direct_ecto, "Repo.#{operation}", node)
  end

  defp classify_operation("Ecto.Adapters.SQL", operation, _arity, node, env)
       when operation in @ecto_sql_raw_sql_operations do
    construct = "Ecto.Adapters.SQL.#{operation}"
    approval = approval_marker(:raw_sql, construct, call_arguments(node))
    occurrence(env, line_from_node(node), :raw_sql, construct, node, approval: approval)
  end

  defp classify_operation("Ecto.Adapters.SQL", operation, _arity, node, env)
       when operation in @ecto_sql_direct_operations do
    occurrence(env, line_from_node(node), :direct_ecto, "Ecto.Adapters.SQL.#{operation}", node)
  end

  defp classify_operation("Postgrex", operation, _arity, node, env)
       when operation in @postgrex_raw_sql_operations do
    construct = "Postgrex.#{operation}"
    approval = approval_marker(:raw_sql, construct, call_arguments(node))
    occurrence(env, line_from_node(node), :raw_sql, construct, node, approval: approval)
  end

  defp classify_operation("Ecto.Multi", operation, _arity, node, env)
       when operation in @multi_operations do
    occurrence(env, line_from_node(node), :direct_ecto, "Ecto.Multi.#{operation}", node)
  end

  defp classify_operation("Ecto.Query.API", operation, _arity, node, env)
       when operation in @query_fragment_operations do
    construct = to_string(operation)
    approval = approval_marker(:raw_sql, construct, call_arguments(node))
    occurrence(env, line_from_node(node), :raw_sql, construct, node, approval: approval)
  end

  defp classify_operation("Ecto.Migration", operation, _arity, node, env)
       when operation in @migration_raw_sql_operations do
    construct = "migration.#{operation}"
    approval = approval_marker(:raw_sql, construct, call_arguments(node))
    occurrence(env, line_from_node(node), :raw_sql, construct, node, approval: approval)
  end

  defp classify_operation("Ecto.Migration.repo()", operation, _arity, node, env)
       when operation in @repo_raw_sql_operations do
    construct = "Repo.#{operation}"
    approval = approval_marker(:raw_sql, construct, call_arguments(node))
    occurrence(env, line_from_node(node), :raw_sql, construct, node, approval: approval)
  end

  defp classify_operation(receiver, operation, _arity, node, env)
       when receiver in @database_modules and operation == :apply do
    class = if receiver == "Ecto.Multi", do: :direct_ecto, else: :raw_sql

    occurrence(env, line_from_node(node), class, "#{receiver}.apply", node,
      approval: :unresolved_sql
    )
  end

  defp classify_operation(_receiver, _operation, _arity, _node, _env), do: nil

  defp classify_apply(receiver, operation, node, env) do
    receiver_name = receiver_name(receiver, env)
    operation_name = static_atom(operation)

    cond do
      receiver_name == "Ecto.Query" ->
        nil

      receiver_name in @database_modules and is_atom(operation_name) and
          not is_nil(operation_name) ->
        classify_operation(receiver_name, operation_name, 0, node, env)

      receiver_name in @database_modules ->
        class = if receiver_name == "Ecto.Multi", do: :direct_ecto, else: :raw_sql

        occurrence(env, line_from_node(node), class, "#{receiver_name}.apply", node,
          approval: :unresolved_sql
        )

      true ->
        nil
    end
  end

  defp migration_helper_escape?(operation, _arguments, env) do
    migration_entrypoint?(env) and operation not in @allowed_migration_locals and
      operation not in @syntax_operations and
      not operator?(operation) and
      not imported?(env, operation)
  end

  defp migration_entrypoint?(%{migration?: true, function: function}),
    do: function in ["change/0", "up/0"]

  defp migration_entrypoint?(_env), do: false

  defp approved_uuidv7_loop?({:for, _metadata, arguments}, env) do
    env.path in [
      "priv/repo/migrations/20260729233957_initial.exs",
      "priv/repo/migrations/20260730005539_integrate_workos_enterprise_identity.exs"
    ] and Enum.any?(arguments, &contains_uuidv7_fragment?/1)
  end

  defp contains_uuidv7_fragment?({:fragment, _metadata, ["uuidv7()"]}), do: true

  defp contains_uuidv7_fragment?(node) when is_tuple(node) do
    node |> Tuple.to_list() |> Enum.any?(&contains_uuidv7_fragment?/1)
  end

  defp contains_uuidv7_fragment?(nodes) when is_list(nodes),
    do: Enum.any?(nodes, &contains_uuidv7_fragment?/1)

  defp contains_uuidv7_fragment?(_node), do: false

  defp dynamic_module_receiver?(
         {{:., _metadata, [{:__aliases__, _, [:Module]}, :concat]}, _, _},
         _env
       ),
       do: true

  defp dynamic_module_receiver?(
         {{:., _metadata, [{:__aliases__, _, [:Module]}, :safe_concat]}, _, _},
         _env
       ),
       do: true

  defp dynamic_module_receiver?(_receiver, _env), do: false

  defp apply_alias([target], env), do: apply_alias([target, []], env)

  defp apply_alias([target, options], env) do
    with module when not is_nil(module) <- module_name(target, env),
         alias_name when is_binary(alias_name) <- alias_name_for(module, options) do
      {%{env | aliases: Map.put(env.aliases, alias_name, module)}, []}
    else
      _value -> {env, []}
    end
  end

  defp apply_alias(_arguments, env), do: {env, []}

  defp alias_occurrences_for(_node, _env, []), do: []

  defp apply_import([target], metadata, env), do: apply_import([target, []], metadata, env)

  defp apply_import([target, options], metadata, env) do
    module = module_name(target, env)

    if module in @database_modules do
      imported = imported_operations(module, options)
      imports = Enum.reduce(imported, env.imports, &Map.put(&2, &1, module))

      occurrences =
        if imported == [:all] do
          [
            occurrence(env, line(metadata), :direct_ecto, "#{module}.import", target,
              approval: :unresolved_sql
            )
          ]
        else
          []
        end

      {%{env | imports: imports}, occurrences}
    else
      {env, []}
    end
  end

  defp apply_import(_arguments, _metadata, env), do: {env, []}

  defp imported_operations(_module, options) do
    options
    |> keyword_option(:only)
    |> case do
      nil ->
        [:all]

      operations ->
        Enum.map(operations, fn {operation, arity} -> {operation, arity} end)
    end
  end

  defp imported_receiver(env, operation, arity) do
    Map.get(env.imports, {operation, arity}) || Map.get(env.imports, :all)
  end

  defp imported?(env, operation) do
    Enum.any?(env.imports, fn
      {{^operation, _arity}, _module} -> true
      {:all, _module} -> true
      _entry -> false
    end)
  end

  defp receiver_name({:repo, _metadata, arguments}, %{migration?: true})
       when arguments in [[], nil],
       do: "Ecto.Migration.repo()"

  defp receiver_name(receiver, env), do: module_name(receiver, env)

  defp module_name({:__aliases__, _metadata, parts}, env) do
    if Enum.all?(parts, &is_atom/1) do
      name = Enum.map_join(parts, ".", &to_string/1)
      Map.get(env.aliases, name, name)
    end
  end

  defp module_name({:__MODULE__, _metadata, _context}, _env), do: nil

  defp module_name(atom, _env) when is_atom(atom) do
    atom
    |> Atom.to_string()
    |> String.trim_leading("Elixir.")
  end

  defp module_name(_node, _env), do: nil

  defp alias_name_for(module, options) do
    case keyword_option(options, :as) do
      nil ->
        module |> String.split(".") |> List.last()

      {:__aliases__, _metadata, parts} ->
        Enum.map_join(parts, ".", &to_string/1)

      atom when is_atom(atom) ->
        to_string(atom)
    end
  end

  defp function_identity([{name, _metadata, arguments} | _rest]) when is_atom(name) do
    {name, length(arguments || [])}
  end

  defp function_identity([{name, _metadata, _context} | _rest]) when is_atom(name), do: {name, 0}
  defp function_identity(_arguments), do: {nil, 0}

  defp function_body(arguments) do
    arguments
    |> List.last()
    |> case do
      body when is_list(body) -> Keyword.get(body, :do)
      _other -> nil
    end
  end

  defp call_arguments({{:., _dot_metadata, [_receiver, _operation]}, _metadata, arguments}),
    do: arguments

  defp call_arguments({_operation, _metadata, arguments}) when is_list(arguments), do: arguments
  defp call_arguments(_node), do: []

  defp approval_marker(:raw_sql, "migration.execute_file", _arguments), do: :unresolved_sql

  defp approval_marker(:raw_sql, _construct, arguments) do
    case List.first(arguments) do
      value when is_binary(value) ->
        nil

      {:<<>>, _metadata, segments} ->
        if static_binary_segments?(segments), do: nil, else: :unresolved_sql

      _value ->
        :unresolved_sql
    end
  end

  defp static_binary_segments?(segments) do
    Enum.all?(segments, fn
      segment when is_binary(segment) -> true
      {:"::", _metadata, [value, _type]} -> is_binary(value)
      _segment -> false
    end)
  end

  defp static_atom(atom) when is_atom(atom), do: atom
  defp static_atom(_node), do: nil

  defp keyword_option(options, key) when is_list(options) do
    if Keyword.keyword?(options), do: Keyword.get(options, key)
  end

  defp keyword_option(_options, _key), do: nil

  defp occurrence(env, line, class, construct, node, opts \\ []) do
    occurrence(env.path, line, env.function, class, construct, node, opts)
  end

  defp occurrence(path, line, function, class, construct, node, opts) do
    base = %{
      class: class,
      construct: construct,
      fingerprint: nil,
      function: function,
      line: line || 1,
      ordinal: 1,
      path: path
    }

    base
    |> Map.put(:fingerprint, fingerprint(base, node))
    |> maybe_put_approval(Keyword.get(opts, :approval))
  end

  defp maybe_put_approval(occurrence, nil), do: occurrence
  defp maybe_put_approval(occurrence, approval), do: Map.put(occurrence, :approval, approval)

  defp assign_ordinals(occurrences) do
    occurrences
    |> Enum.reduce({%{}, []}, fn occurrence, {counts, occurrences} ->
      key = {
        occurrence.path,
        occurrence.line,
        to_string(occurrence.class),
        occurrence.construct,
        occurrence.function
      }

      ordinal = Map.get(counts, key, 0) + 1
      occurrence = %{occurrence | ordinal: ordinal}
      occurrence = %{occurrence | fingerprint: fingerprint(occurrence, occurrence.fingerprint)}

      {Map.put(counts, key, ordinal), [occurrence | occurrences]}
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp fingerprint(occurrence, node) do
    key = {
      occurrence.path,
      occurrence.line,
      to_string(occurrence.class),
      occurrence.construct,
      occurrence.function,
      occurrence.ordinal
    }

    Map.get_lazy(@preserved_fingerprints, key, fn ->
      payload =
        :erlang.term_to_binary({
          occurrence.path,
          occurrence.line,
          occurrence.class,
          occurrence.construct,
          occurrence.function,
          occurrence.ordinal,
          printable_node(node)
        })

      "sha256:" <> Base.encode16(:crypto.hash(:sha256, payload), case: :lower)
    end)
  end

  defp printable_node("sha256:" <> _rest = value), do: value

  defp printable_node(node) do
    Macro.to_string(node)
  rescue
    _error -> inspect(node)
  end

  defp operator?(operation) do
    operation
    |> to_string()
    |> String.match?(~r/\A[^\p{L}\p{N}_]+\z/u)
  end

  defp line_from_node({{:., dot_metadata, _receiver}, metadata, _arguments}),
    do: line(metadata) || line(dot_metadata)

  defp line_from_node({:call, metadata, _callee, _arguments}), do: line(metadata)
  defp line_from_node({_operation, metadata, _arguments}), do: line(metadata)
  defp line_from_node(_node), do: 1

  defp line({line, _column}) when is_integer(line), do: line
  defp line(metadata) when is_list(metadata), do: Keyword.get(metadata, :line)
  defp line(line) when is_integer(line), do: line
  defp line(_metadata), do: nil

  defp error_line({line, _column}), do: line
  defp error_line(metadata) when is_list(metadata), do: Keyword.get(metadata, :line, 1)
  defp error_line(_location), do: 1

  defp tracked_sources(root) do
    {output, 0} = System.cmd("git", ["ls-files", "-z"], cd: root)

    output
    |> String.split(<<0>>, trim: true)
    |> Enum.filter(&boundary_source?/1)
    |> Enum.map(fn path -> %{path: path, source: File.read!(Path.join(root, path))} end)
  end

  defp boundary_source?(path) do
    extension = Path.extname(path)

    extension in @source_extensions and
      (String.starts_with?(path, "lib/") or
         String.starts_with?(path, "test/") or
         String.starts_with?(path, "credo_checks/") or
         String.starts_with?(path, "priv/repo/migrations/") or
         path == "priv/repo/seeds.exs" or
         path == "mix.exs" or
         String.starts_with?(path, "scripts/") or sql_file?(path))
  end

  defp elixir_source?(path), do: Path.extname(path) in [".ex", ".exs"]
  defp sql_file?(path), do: Path.extname(path) in @sql_file_extensions
  defp migration_path?(path), do: String.starts_with?(path, "priv/repo/migrations/")

  defp compiled_beam_paths(root) do
    env = mix_env()

    active_paths =
      root
      |> Path.join("_build/#{env}/lib/office_graph/ebin/Elixir.OfficeGraph*.beam")
      |> Path.wildcard()

    paths =
      if active_paths == [] do
        root
        |> Path.join("_build/*/lib/office_graph/ebin/Elixir.OfficeGraph*.beam")
        |> Path.wildcard()
      else
        active_paths
      end

    Enum.reject(paths, &String.contains?(&1, "ProjectQuality.DatabaseBoundaryScanner"))
  end

  defp scan_beam(path, root) do
    with {:ok, {_module, [abstract_code: {:raw_abstract_v1, forms}]}} <-
           :beam_lib.chunks(String.to_charlist(path), [:abstract_code]) do
      source = abstract_source(forms, root)

      if compiled_framework_source?(source) do
        []
      else
        forms
        |> Enum.flat_map(&compiled_form_occurrences(&1, source))
        |> Enum.uniq_by(fn occurrence ->
          {occurrence.path, occurrence.line, occurrence.class, occurrence.construct}
        end)
      end
    else
      _error -> []
    end
  end

  defp compiled_framework_source?("lib/office_graph/repo.ex"), do: true
  defp compiled_framework_source?(_source), do: false

  defp abstract_source(forms, root) do
    forms
    |> Enum.find_value(fn
      {:attribute, _line, :file, {source, _source_line}} -> List.to_string(source)
      _form -> nil
    end)
    |> case do
      nil -> "compiled"
      source -> Path.relative_to(source, root)
    end
  end

  defp compiled_form_occurrences(form, source) do
    form
    |> compiled_node_occurrences(source, [])
    |> Enum.reverse()
  end

  defp compiled_node_occurrences(
         {:call, _line,
          {:remote, _remote_line, {:atom, _module_line, module}, {:atom, _fun_line, fun}},
          arguments} = node,
         source,
         occurrences
       ) do
    module = module |> Atom.to_string() |> String.trim_leading("Elixir.")

    occurrence =
      classify_operation(
        module,
        fun,
        length(arguments),
        node,
        %{path: source, function: nil, migration?: false}
      )

    occurrences = if occurrence, do: [occurrence | occurrences], else: occurrences
    compiled_node_occurrences(Tuple.to_list(node), source, occurrences)
  end

  defp compiled_node_occurrences(nodes, source, occurrences) when is_list(nodes) do
    Enum.reduce(nodes, occurrences, &compiled_node_occurrences(&1, source, &2))
  end

  defp compiled_node_occurrences(node, source, occurrences) when is_tuple(node) do
    node
    |> Tuple.to_list()
    |> compiled_node_occurrences(source, occurrences)
  end

  defp compiled_node_occurrences(_node, _source, occurrences), do: occurrences

  defp mix_env do
    if Process.whereis(Mix.State), do: Mix.env(), else: :dev
  rescue
    _error -> :dev
  end
end
