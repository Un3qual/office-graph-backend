defmodule OfficeGraph.TestSupport.MigrationConformanceSupport do
  @moduledoc false

  @table_create_operations [:create, :create_if_not_exists]
  @table_drop_operations [:drop, :drop_if_exists]
  @table_definition_operations [:alter | @table_create_operations]
  @table_lifecycle_operations @table_create_operations ++ @table_drop_operations
  @foreign_key_definition_operations [:add, :add_if_not_exists, :modify]

  def migration_tables do
    repository_helpers = repository_migration_helpers()

    "priv/repo/migrations/*.exs"
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.reduce(MapSet.new(), fn path, tables ->
      path
      |> File.read!()
      |> migration_forward_ast(repository_helpers)
      |> migration_table_operations()
      |> Enum.reduce(tables, &apply_table_operation/2)
    end)
    |> MapSet.to_list()
    |> Enum.sort()
  end

  def resource_table_identities(expected_resources) do
    expected_resources
    |> Enum.map(fn {table, {_domain, resource}} -> resource_table_identity(table, resource) end)
    |> Enum.sort()
  end

  def migration_foreign_key_relationship_errors(expected_resources) do
    resources_by_table =
      Map.new(expected_resources, fn {table, {_domain, resource}} ->
        {resource_table_identity(table, resource), resource}
      end)

    migration_foreign_keys()
    |> Enum.flat_map(fn {source_table, source_attribute, destination_table, destination_attribute} ->
      with source when not is_nil(source) <- Map.get(resources_by_table, source_table),
           destination when not is_nil(destination) <-
             Map.get(resources_by_table, destination_table),
           source_attribute <- String.to_existing_atom(source_attribute),
           destination_attribute <- String.to_existing_atom(destination_attribute),
           nil <-
             Enum.find(Ash.Resource.Info.relationships(source), fn relationship ->
               match?(%Ash.Resource.Relationships.BelongsTo{}, relationship) and
                 relationship.source_attribute == source_attribute and
                 relationship.destination == destination and
                 relationship.destination_attribute == destination_attribute
             end) do
        [
          "#{source_table}.#{source_attribute} references #{destination_table}.#{destination_attribute} without a matching belongs_to"
        ]
      else
        %Ash.Resource.Relationships.BelongsTo{} -> []
        _table_without_resource -> []
      end
    end)
    |> Enum.sort()
  end

  defp migration_foreign_keys do
    repository_helpers = repository_migration_helpers()

    "priv/repo/migrations/*.exs"
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.reduce(%{}, fn path, foreign_keys ->
      path
      |> File.read!()
      |> migration_forward_ast(repository_helpers)
      |> migration_foreign_key_operations()
      |> Enum.reduce(foreign_keys, &apply_foreign_key_operation/2)
    end)
    |> Map.values()
    |> Enum.flat_map(&MapSet.to_list/1)
    |> Enum.map(fn {source_table, source_attribute, destination_table, destination_attribute,
                    _constraint_name} ->
      {source_table, source_attribute, destination_table, destination_attribute}
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp migration_forward_ast(source, repository_helpers) do
    ast = Code.string_to_quoted!(source)
    module_body = migration_module_body(ast)

    repository_helper_imports =
      repository_migration_helper_imports(module_body, repository_helpers)

    functions = migration_functions(ast)

    forward_ast =
      case migration_entrypoint(functions, {:up, 0}) ||
             migration_entrypoint(functions, {:change, 0}) do
        definitions when is_list(definitions) ->
          definitions
          |> Enum.map(fn %{body: body, key: key} ->
            expand_local_calls(body, functions, [key])
          end)
          |> block()
          |> resolve_local_bindings()

        nil ->
          {:__block__, [], []}
      end

    forward_ast
    |> reject_schema_ownership_sql!()
    |> reject_repository_migration_helpers!(repository_helpers, repository_helper_imports)
  end

  defp reject_schema_ownership_sql!(ast) do
    Macro.prewalk(ast, fn node ->
      with {:ok, sql_payload} <- migration_inline_sql_payload(node),
           {:ok, sql} <- static_migration_sql(sql_payload),
           true <- schema_ownership_sql?(sql) do
        raise ArgumentError,
              "migration SQL changes table or foreign-key ownership; " <>
                "use declarative Ecto migration constructs so conformance can inventory it"
      end

      with {:ok, arguments} <- migration_execute_file_arguments(node),
           {:ok, path} <- arguments |> List.first() |> static_migration_file_path(),
           sql <- File.read!(path),
           true <- schema_ownership_sql?(sql) do
        raise ArgumentError,
              "migration execute SQL changes table or foreign-key ownership; " <>
                "use declarative Ecto migration constructs so conformance can inventory it"
      end

      node
    end)
  end

  defp repository_migration_helpers do
    ["lib/**/*.ex", "lib/**/*.exs"]
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.sort()
    |> Enum.reduce(%{}, fn path, helpers ->
      path
      |> File.read!()
      |> Code.string_to_quoted!(file: path)
      |> collect_repository_helper_modules(nil, helpers)
    end)
  end

  defp collect_repository_helper_modules(
         {:defmodule, _metadata, [module, [do: body]]},
         parent_module,
         helpers
       ) do
    module = repository_module_name(module, parent_module)

    helpers =
      if is_binary(module) do
        keys = repository_public_function_keys(body)
        Map.update(helpers, module, keys, &MapSet.union(&1, keys))
      else
        helpers
      end

    body
    |> module_expressions()
    |> Enum.reduce(helpers, fn expression, helpers ->
      collect_repository_helper_modules(expression, module, helpers)
    end)
  end

  defp collect_repository_helper_modules(nodes, parent_module, helpers) when is_list(nodes) do
    Enum.reduce(nodes, helpers, fn node, helpers ->
      collect_repository_helper_modules(node, parent_module, helpers)
    end)
  end

  defp collect_repository_helper_modules(node, parent_module, helpers) when is_tuple(node) do
    node
    |> Tuple.to_list()
    |> collect_repository_helper_modules(parent_module, helpers)
  end

  defp collect_repository_helper_modules(_node, _parent_module, helpers), do: helpers

  defp repository_module_name(module, parent_module) do
    case module_name(module) do
      nil ->
        nil

      module when is_binary(parent_module) ->
        if String.contains?(module, "."), do: module, else: "#{parent_module}.#{module}"

      module ->
        module
    end
  end

  defp repository_public_function_keys(body) do
    body
    |> module_expressions()
    |> Enum.reduce(MapSet.new(), fn
      {kind, _metadata, [head, body_options]}, keys
      when kind in [:def, :defmacro] and is_list(body_options) ->
        case {local_function_head(head), Keyword.fetch(body_options, :do)} do
          {{key, parameters, guards}, {:ok, body}} ->
            key
            |> local_function_definitions(kind, parameters, guards, body)
            |> Enum.reduce(keys, &MapSet.put(&2, &1.key))

          _not_a_public_definition ->
            keys
        end

      _expression, keys ->
        keys
    end)
  end

  defp repository_migration_helper_imports(body, repository_helpers) do
    {_aliases, imports} =
      body
      |> module_expressions()
      |> Enum.reduce({%{}, []}, fn
        {:alias, _metadata, arguments}, {aliases, imports} ->
          {put_module_aliases(aliases, arguments), imports}

        {:import, _metadata, [target | _options]}, {aliases, imports} ->
          module = resolve_module_name(target, aliases)

          if Map.has_key?(repository_helpers, module),
            do: {aliases, [module | imports]},
            else: {aliases, imports}

        _expression, accumulator ->
          accumulator
      end)

    Enum.uniq(imports)
  end

  defp reject_repository_migration_helpers!(ast, repository_helpers, imported_helpers) do
    Macro.prewalk(ast, fn
      {:import, _metadata, [target | _options]} = node ->
        module = migration_module_name(target)

        if Map.has_key?(repository_helpers, module) do
          raise ArgumentError, repository_migration_helper_message(module)
        end

        node

      {{:., _dot_metadata, [receiver, operation]}, _metadata, arguments} = node
      when is_atom(operation) and is_list(arguments) ->
        module = migration_module_name(receiver)

        if repository_helper_call?(
             repository_helpers,
             module,
             {operation, length(arguments)}
           ) do
          raise ArgumentError,
                repository_migration_helper_message(module, operation, length(arguments))
        end

        node

      {operation, _metadata, arguments} = node
      when is_atom(operation) and is_list(arguments) ->
        case Enum.find(imported_helpers, fn module ->
               repository_helper_call?(
                 repository_helpers,
                 module,
                 {operation, length(arguments)}
               )
             end) do
          nil ->
            :ok

          module ->
            raise ArgumentError,
                  repository_migration_helper_message(module, operation, length(arguments))
        end

        node

      node ->
        node
    end)

    ast
  end

  defp repository_helper_call?(repository_helpers, module, key) when is_binary(module) do
    repository_helpers
    |> Map.get(module, MapSet.new())
    |> MapSet.member?(key)
  end

  defp repository_helper_call?(_repository_helpers, _module, _key), do: false

  defp repository_migration_helper_message(module),
    do:
      "migration imports repository migration helper #{module}; " <>
        "inline declarative Ecto migration constructs so conformance can inventory them"

  defp repository_migration_helper_message(module, operation, arity),
    do:
      "migration delegates lifecycle analysis to repository migration helper " <>
        "#{module}.#{operation}/#{arity}; inline declarative Ecto migration constructs " <>
        "so conformance can inventory them"

  defp migration_inline_sql_payload(node) do
    case migration_execute_arguments(node) do
      {:ok, arguments} ->
        arguments |> List.first() |> then(&{:ok, &1})

      :error ->
        migration_query_sql_payload(node)
    end
  end

  defp migration_query_sql_payload(
         {{:., _dot_metadata, [receiver, operation]}, _metadata, arguments}
       )
       when operation in [:query, :query!] and is_list(arguments) do
    if migration_repo_query_receiver?(receiver) and arguments != [],
      do: {:ok, List.first(arguments)},
      else: migration_sql_adapter_payload(receiver, operation, arguments)
  end

  defp migration_query_sql_payload(_node), do: :error

  defp migration_sql_adapter_payload(receiver, operation, [_repo, sql | _arguments])
       when operation in [:query, :query!] do
    if migration_module_name(receiver) == "Ecto.Adapters.SQL",
      do: {:ok, sql},
      else: :error
  end

  defp migration_sql_adapter_payload(_receiver, _operation, _arguments), do: :error

  defp migration_repo_query_receiver?({:repo, _metadata, arguments})
       when arguments in [nil, []],
       do: true

  defp migration_repo_query_receiver?(
         {{:., _dot_metadata, [receiver, :repo]}, _metadata, arguments}
       )
       when arguments in [nil, []],
       do: migration_module_name(receiver) == "Ecto.Migration"

  defp migration_repo_query_receiver?(receiver) do
    case migration_module_name(receiver) do
      nil -> false
      name -> name |> String.split(".") |> List.last() |> String.ends_with?("Repo")
    end
  end

  defp migration_module_name({:__aliases__, _metadata, parts}) when is_list(parts),
    do: Enum.join(parts, ".")

  defp migration_module_name(module) when is_binary(module), do: module
  defp migration_module_name(module) when is_atom(module), do: Atom.to_string(module)
  defp migration_module_name(_module), do: nil

  defp migration_execute_arguments({:execute, _metadata, arguments}) when is_list(arguments),
    do: {:ok, arguments}

  defp migration_execute_arguments(
         {{:., _dot_metadata, [_receiver, :execute]}, _metadata, arguments}
       )
       when is_list(arguments),
       do: {:ok, arguments}

  defp migration_execute_arguments({:apply, _metadata, [_receiver, :execute, arguments]})
       when is_list(arguments),
       do: {:ok, arguments}

  defp migration_execute_arguments(
         {{:., _dot_metadata, [_apply_receiver, :apply]}, _metadata,
          [_receiver, :execute, arguments]}
       )
       when is_list(arguments),
       do: {:ok, arguments}

  defp migration_execute_arguments(_node), do: :error

  defp migration_execute_file_arguments({:execute_file, _metadata, arguments})
       when is_list(arguments),
       do: {:ok, arguments}

  defp migration_execute_file_arguments(
         {{:., _dot_metadata, [_receiver, :execute_file]}, _metadata, arguments}
       )
       when is_list(arguments),
       do: {:ok, arguments}

  defp migration_execute_file_arguments(
         {:apply, _metadata, [_receiver, :execute_file, arguments]}
       )
       when is_list(arguments),
       do: {:ok, arguments}

  defp migration_execute_file_arguments(
         {{:., _dot_metadata, [_apply_receiver, :apply]}, _metadata,
          [_receiver, :execute_file, arguments]}
       )
       when is_list(arguments),
       do: {:ok, arguments}

  defp migration_execute_file_arguments(_node), do: :error

  defp static_migration_sql(sql) when is_binary(sql), do: {:ok, sql}

  defp static_migration_sql({:<>, _metadata, [left, right]}) do
    with {:ok, left} <- static_migration_sql(left),
         {:ok, right} <- static_migration_sql(right),
         do: {:ok, left <> right}
  end

  defp static_migration_sql({:<<>>, _metadata, segments}) when is_list(segments) do
    segments
    |> Enum.reduce_while({:ok, []}, fn segment, {:ok, values} ->
      case static_migration_sql_segment(segment) do
        {:ok, value} -> {:cont, {:ok, [value | values]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, values |> Enum.reverse() |> IO.iodata_to_binary()}
      :error -> :error
    end
  end

  defp static_migration_sql(_sql), do: :error

  defp static_migration_file_path(path) do
    with {:ok, path} when is_binary(path) <- static_migration_sql(path),
         :relative <- Path.type(path),
         expanded <- Path.expand(path, "/"),
         normalized <- Path.relative_to(expanded, "/"),
         false <- normalized in ["", ".", ".."],
         false <- String.starts_with?(normalized, "../") do
      {:ok, normalized}
    else
      _unavailable -> :error
    end
  end

  defp static_migration_sql_segment(segment) when is_binary(segment), do: {:ok, segment}

  defp static_migration_sql_segment(
         {:"::", _metadata,
          [
            {{:., _dot_metadata, [Kernel, :to_string]}, interpolation_metadata, [value]},
            {:binary, _binary_metadata, nil}
          ]}
       ) do
    if Keyword.get(interpolation_metadata, :from_interpolation, false),
      do: static_interpolation_string(value),
      else: :error
  end

  defp static_migration_sql_segment(_segment), do: :error

  defp static_interpolation_string(value)
       when is_atom(value) or is_binary(value) or is_number(value),
       do: {:ok, to_string(value)}

  defp static_interpolation_string(value) when is_list(value) do
    if Enum.all?(value, &is_integer/1), do: {:ok, List.to_string(value)}, else: :error
  end

  defp static_interpolation_string(_value), do: :error

  defp schema_ownership_sql?(sql) do
    sql = sql_code_without_comments_or_literals(sql)

    Regex.match?(
      ~r/\b(?:CREATE\s+(?:(?:GLOBAL|LOCAL)\s+)?(?:(?:TEMP|TEMPORARY|UNLOGGED)\s+)?|ALTER\s+|DROP\s+)(?:FOREIGN\s+)?TABLE\b/i,
      sql
    )
  end

  defp sql_code_without_comments_or_literals(sql) do
    sql
    |> do_sql_code_without_comments_or_literals([])
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  defp do_sql_code_without_comments_or_literals(<<>>, code), do: code

  defp do_sql_code_without_comments_or_literals(<<"--", rest::binary>>, code),
    do: skip_sql_line_comment(rest, [" " | code])

  defp do_sql_code_without_comments_or_literals(<<"/*", rest::binary>>, code),
    do: skip_sql_block_comment(rest, 1, [" " | code])

  defp do_sql_code_without_comments_or_literals(<<"'", rest::binary>>, code) do
    cond do
      sql_do_block_prefix?(code) ->
        preserve_sql_single_quoted_code(rest, code)

      sql_dynamic_execute_prefix?(code) ->
        preserve_sql_single_quoted_code(rest, code)

      true ->
        skip_sql_single_quoted(rest, [" " | code])
    end
  end

  defp do_sql_code_without_comments_or_literals(<<"\"", rest::binary>>, code),
    do: skip_sql_double_quoted(rest, [" " | code])

  defp do_sql_code_without_comments_or_literals(<<"$", _rest::binary>> = sql, code) do
    case sql_dollar_quote_delimiter(sql) do
      nil ->
        consume_sql_codepoint(sql, code)

      delimiter ->
        cond do
          sql_do_block_prefix?(code) ->
            preserve_sql_dollar_quoted_code(sql, delimiter, code)

          sql_dynamic_execute_prefix?(code) ->
            preserve_sql_dollar_quoted_code(sql, delimiter, code)

          true ->
            skip_sql_dollar_quoted(sql, delimiter, [" " | code])
        end
    end
  end

  defp do_sql_code_without_comments_or_literals(sql, code),
    do: consume_sql_codepoint(sql, code)

  defp consume_sql_codepoint(<<codepoint::utf8, rest::binary>>, code),
    do: do_sql_code_without_comments_or_literals(rest, [<<codepoint::utf8>> | code])

  defp skip_sql_line_comment(<<>>, code), do: code

  defp skip_sql_line_comment(<<line_break, rest::binary>>, code)
       when line_break in [?\n, ?\r],
       do: do_sql_code_without_comments_or_literals(rest, [" " | code])

  defp skip_sql_line_comment(<<_codepoint::utf8, rest::binary>>, code),
    do: skip_sql_line_comment(rest, code)

  defp skip_sql_block_comment(<<>>, _depth, code), do: code

  defp skip_sql_block_comment(<<"/*", rest::binary>>, depth, code),
    do: skip_sql_block_comment(rest, depth + 1, code)

  defp skip_sql_block_comment(<<"*/", rest::binary>>, 1, code),
    do: do_sql_code_without_comments_or_literals(rest, code)

  defp skip_sql_block_comment(<<"*/", rest::binary>>, depth, code),
    do: skip_sql_block_comment(rest, depth - 1, code)

  defp skip_sql_block_comment(<<_codepoint::utf8, rest::binary>>, depth, code),
    do: skip_sql_block_comment(rest, depth, code)

  defp skip_sql_single_quoted(<<>>, code), do: code

  defp skip_sql_single_quoted(<<"''", rest::binary>>, code),
    do: skip_sql_single_quoted(rest, code)

  defp skip_sql_single_quoted(<<"'", rest::binary>>, code),
    do: do_sql_code_without_comments_or_literals(rest, code)

  defp skip_sql_single_quoted(<<_codepoint::utf8, rest::binary>>, code),
    do: skip_sql_single_quoted(rest, code)

  defp preserve_sql_single_quoted_code(sql, code) do
    case take_sql_single_quoted(sql, []) do
      {:ok, body, trailing} ->
        body_code = sql_code_without_comments_or_literals(body)
        do_sql_code_without_comments_or_literals(trailing, [" ", body_code, " " | code])

      :error ->
        code
    end
  end

  defp take_sql_single_quoted(<<>>, _body), do: :error

  defp take_sql_single_quoted(<<"''", rest::binary>>, body),
    do: take_sql_single_quoted(rest, ["'" | body])

  defp take_sql_single_quoted(<<"'", rest::binary>>, body),
    do: {:ok, body |> Enum.reverse() |> IO.iodata_to_binary(), rest}

  defp take_sql_single_quoted(<<codepoint::utf8, rest::binary>>, body),
    do: take_sql_single_quoted(rest, [<<codepoint::utf8>> | body])

  defp skip_sql_double_quoted(<<>>, code), do: code

  defp skip_sql_double_quoted(<<"\"\"", rest::binary>>, code),
    do: skip_sql_double_quoted(rest, code)

  defp skip_sql_double_quoted(<<"\"", rest::binary>>, code),
    do: do_sql_code_without_comments_or_literals(rest, code)

  defp skip_sql_double_quoted(<<_codepoint::utf8, rest::binary>>, code),
    do: skip_sql_double_quoted(rest, code)

  defp sql_dollar_quote_delimiter(sql) do
    case Regex.run(~r/\A\$(?:[A-Za-z_][A-Za-z0-9_]*)?\$/, sql) do
      [delimiter] -> delimiter
      nil -> nil
    end
  end

  defp skip_sql_dollar_quoted(sql, delimiter, code) do
    delimiter_size = byte_size(delimiter)
    rest = binary_part(sql, delimiter_size, byte_size(sql) - delimiter_size)

    case :binary.match(rest, delimiter) do
      {closing_offset, ^delimiter_size} ->
        trailing_offset = closing_offset + delimiter_size
        trailing_size = byte_size(rest) - trailing_offset
        trailing = binary_part(rest, trailing_offset, trailing_size)
        do_sql_code_without_comments_or_literals(trailing, code)

      :nomatch ->
        code
    end
  end

  defp preserve_sql_dollar_quoted_code(sql, delimiter, code) do
    delimiter_size = byte_size(delimiter)
    rest = binary_part(sql, delimiter_size, byte_size(sql) - delimiter_size)

    case :binary.match(rest, delimiter) do
      {closing_offset, ^delimiter_size} ->
        body = binary_part(rest, 0, closing_offset)
        trailing_offset = closing_offset + delimiter_size
        trailing_size = byte_size(rest) - trailing_offset
        trailing = binary_part(rest, trailing_offset, trailing_size)
        body_code = sql_code_without_comments_or_literals(body)

        do_sql_code_without_comments_or_literals(trailing, [" ", body_code, " " | code])

      :nomatch ->
        code
    end
  end

  defp sql_do_block_prefix?(code) do
    code = code |> Enum.reverse() |> IO.iodata_to_binary()

    Regex.match?(
      ~r/(?:^|;)\s*DO(?:\s+LANGUAGE\s+[A-Za-z_][A-Za-z0-9_$]*)?\s*\z/i,
      code
    )
  end

  defp sql_dynamic_execute_prefix?(code) do
    code = code |> Enum.reverse() |> IO.iodata_to_binary()

    case Regex.run(~r/\bEXECUTE\b([^;]*)\z/is, code, capture: :all_but_first) do
      [expression] -> dynamic_execute_literal_prefix?(expression)
      nil -> false
    end
  end

  defp dynamic_execute_literal_prefix?(expression) do
    expression = String.trim(expression)

    direct_literal? = Regex.match?(~r/\A(?:\(\s*)*\z/, expression)

    format_template? =
      Regex.match?(
        ~r/\A(?:\(\s*)*(?:pg_catalog\.)?format\s*\(\s*\z/i,
        expression
      )

    concatenated_fragment? =
      String.ends_with?(expression, "||") and
        expression
        |> binary_part(0, byte_size(expression) - 2)
        |> dynamic_execute_concat_literal_context?()

    direct_literal? or format_template? or concatenated_fragment?
  end

  defp dynamic_execute_concat_literal_context?(expression) do
    expression
    |> dynamic_execute_open_frames([], "", false)
    |> Enum.all?(fn
      :group -> true
      {:format, 0} -> true
      _function_or_format_argument -> false
    end)
  end

  defp dynamic_execute_open_frames(<<>>, frames, _identifier, _separated?), do: frames

  defp dynamic_execute_open_frames(<<codepoint, rest::binary>>, frames, identifier, separated?)
       when codepoint in ?a..?z or codepoint in ?A..?Z or codepoint in ?0..?9 or
              codepoint in [?_, ?$, ?.] do
    next = <<codepoint>>
    identifier = if separated? and identifier != "", do: next, else: identifier <> next
    dynamic_execute_open_frames(rest, frames, identifier, false)
  end

  defp dynamic_execute_open_frames(<<codepoint, rest::binary>>, frames, identifier, _separated?)
       when codepoint in [32, ?\t, ?\n, ?\r] do
    dynamic_execute_open_frames(rest, frames, identifier, true)
  end

  defp dynamic_execute_open_frames(<<"(", rest::binary>>, frames, identifier, _separated?) do
    frame =
      case String.downcase(identifier) do
        "" ->
          :group

        "format" ->
          {:format, 0}

        identifier ->
          if String.ends_with?(identifier, ".format"), do: {:format, 0}, else: :function
      end

    dynamic_execute_open_frames(rest, [frame | frames], "", false)
  end

  defp dynamic_execute_open_frames(
         <<")", rest::binary>>,
         [_frame | frames],
         _identifier,
         _separated?
       ),
       do: dynamic_execute_open_frames(rest, frames, "", false)

  defp dynamic_execute_open_frames(<<")", rest::binary>>, [], _identifier, _separated?),
    do: dynamic_execute_open_frames(rest, [], "", false)

  defp dynamic_execute_open_frames(<<",", rest::binary>>, frames, _identifier, _separated?) do
    frames =
      case frames do
        [{:format, argument_index} | outer_frames] ->
          [{:format, argument_index + 1} | outer_frames]

        frames ->
          frames
      end

    dynamic_execute_open_frames(rest, frames, "", false)
  end

  defp dynamic_execute_open_frames(
         <<_codepoint, rest::binary>>,
         frames,
         _identifier,
         _separated?
       ),
       do: dynamic_execute_open_frames(rest, frames, "", false)

  defp migration_entrypoint(functions, key) do
    case functions
         |> Map.get(key, [])
         |> Enum.filter(&(&1.kind == :function and &1.visibility == :public)) do
      [] -> nil
      definitions -> definitions
    end
  end

  defp migration_functions(ast) do
    expressions = ast |> migration_module_body() |> module_expressions()
    local_function_keys = migration_local_function_keys(expressions)

    {functions, _attributes, _aliases} =
      Enum.reduce(expressions, {%{}, %{}, %{}}, fn
        {:alias, _metadata, arguments}, {functions, attributes, aliases} ->
          {functions, attributes, put_module_aliases(aliases, arguments)}

        {:@, _metadata, [{name, _name_metadata, [value]}]}, {functions, attributes, aliases}
        when is_atom(name) ->
          attributes = Map.put(attributes, name, resolve_module_attributes(value, attributes))
          {functions, attributes, aliases}

        {kind, _meta, [head, body_options]}, {functions, attributes, aliases}
        when kind in [:def, :defp, :defmacro, :defmacrop] and is_list(body_options) ->
          head = resolve_module_attributes(head, attributes)

          case {local_function_head(head), Keyword.fetch(body_options, :do)} do
            {{key, parameters, guards}, {:ok, body}} ->
              functions =
                key
                |> local_function_definitions(
                  kind,
                  parameters,
                  guards,
                  body
                  |> resolve_module_attributes(attributes)
                  |> normalize_migration_calls(aliases, local_function_keys)
                )
                |> Enum.reduce(functions, fn definition, functions ->
                  Map.update(functions, definition.key, [definition], fn definitions ->
                    [definition | definitions]
                  end)
                end)

              {functions, attributes, aliases}

            _not_a_function_definition ->
              {functions, attributes, aliases}
          end

        _module_expression, accumulator ->
          accumulator
      end)

    Map.new(functions, fn {key, definitions} -> {key, Enum.reverse(definitions)} end)
  end

  defp migration_module_body({:__block__, _metadata, expressions}) do
    Enum.find_value(expressions, &migration_module_body/1)
  end

  defp migration_module_body({:defmodule, _metadata, [_module, [do: body]]}) do
    if uses_ecto_migration?(body), do: body
  end

  defp migration_module_body(_ast), do: nil

  defp uses_ecto_migration?(body) do
    body
    |> module_expressions()
    |> Enum.reduce_while(%{}, fn
      {:alias, _metadata, arguments}, aliases ->
        {:cont, put_module_aliases(aliases, arguments)}

      {:use, _metadata, [target | _options]}, aliases ->
        if resolve_module_name(target, aliases) == "Ecto.Migration",
          do: {:halt, true},
          else: {:cont, aliases}

      _module_expression, aliases ->
        {:cont, aliases}
    end)
    |> Kernel.==(true)
  end

  defp module_expressions({:__block__, _metadata, expressions}), do: expressions
  defp module_expressions(nil), do: []
  defp module_expressions(expression), do: [expression]

  defp migration_local_function_keys(expressions) do
    Enum.reduce(expressions, MapSet.new(), fn
      {kind, _metadata, [head, body_options]}, keys
      when kind in [:def, :defp, :defmacro, :defmacrop] and is_list(body_options) ->
        case local_function_head(head) do
          {{name, arity}, _parameters, _guards} -> MapSet.put(keys, {name, arity})
          nil -> keys
        end

      _expression, keys ->
        keys
    end)
  end

  defp normalize_migration_calls(
         {:__block__, metadata, expressions},
         aliases,
         local_function_keys
       ) do
    {expressions, _aliases} =
      Enum.map_reduce(expressions, aliases, fn expression, aliases ->
        normalized = normalize_migration_calls(expression, aliases, local_function_keys)

        aliases =
          case expression do
            {:alias, _metadata, arguments} -> put_module_aliases(aliases, arguments)
            _expression -> aliases
          end

        {normalized, aliases}
      end)

    {:__block__, metadata, expressions}
  end

  defp normalize_migration_calls(
         {:|>, _metadata, _arguments} = pipeline,
         aliases,
         local_function_keys
       ) do
    pipeline
    |> expand_pipeline()
    |> normalize_migration_calls(aliases, local_function_keys)
  end

  defp normalize_migration_calls(
         {:import, metadata, [target | options]},
         aliases,
         local_function_keys
       ) do
    target = resolve_module_name(target, aliases) || target

    options =
      Enum.map(options, &normalize_migration_calls(&1, aliases, local_function_keys))

    {:import, metadata, [target | options]}
  end

  defp normalize_migration_calls(
         {:apply, metadata, [receiver, operation, arguments]},
         aliases,
         local_function_keys
       ) do
    arguments = normalize_migration_calls(arguments, aliases, local_function_keys)
    fallback = {:apply, metadata, [receiver, operation, arguments]}

    if MapSet.member?(local_function_keys, {:apply, 3}) do
      fallback
    else
      normalize_static_migration_apply(
        receiver,
        operation,
        arguments,
        metadata,
        fallback,
        aliases
      )
    end
  end

  defp normalize_migration_calls(
         {{:., dot_metadata, [apply_receiver, :apply]}, metadata,
          [receiver, operation, arguments]},
         aliases,
         local_function_keys
       ) do
    arguments = normalize_migration_calls(arguments, aliases, local_function_keys)

    fallback =
      {{:., dot_metadata, [apply_receiver, :apply]}, metadata, [receiver, operation, arguments]}

    if migration_apply_receiver?(apply_receiver, aliases) do
      normalize_static_migration_apply(
        receiver,
        operation,
        arguments,
        metadata,
        fallback,
        aliases
      )
    else
      fallback
    end
  end

  defp normalize_migration_calls(
         {{:., dot_metadata, [receiver, operation]}, metadata, arguments} = node,
         aliases,
         local_function_keys
       )
       when is_atom(operation) and is_list(arguments) do
    arguments =
      Enum.map(arguments, &normalize_migration_calls(&1, aliases, local_function_keys))

    case resolve_module_name(receiver, aliases) do
      "Ecto.Migration" ->
        {operation, metadata, arguments}

      receiver when is_binary(receiver) ->
        {{:., dot_metadata, [receiver, operation]}, metadata, arguments}

      _unresolved_receiver ->
        put_elem(node, 2, arguments)
    end
  end

  defp normalize_migration_calls(nodes, aliases, local_function_keys) when is_list(nodes),
    do: Enum.map(nodes, &normalize_migration_calls(&1, aliases, local_function_keys))

  defp normalize_migration_calls(node, aliases, local_function_keys) when is_tuple(node) do
    node
    |> Tuple.to_list()
    |> Enum.map(&normalize_migration_calls(&1, aliases, local_function_keys))
    |> List.to_tuple()
  end

  defp normalize_migration_calls(node, _aliases, _local_function_keys), do: node

  defp normalize_static_migration_apply(
         receiver,
         operation,
         arguments,
         metadata,
         fallback,
         aliases
       )
       when is_atom(operation) and is_list(arguments) do
    if resolve_module_name(receiver, aliases) == "Ecto.Migration",
      do: {operation, metadata, arguments},
      else: fallback
  end

  defp normalize_static_migration_apply(
         _receiver,
         _operation,
         _arguments,
         _metadata,
         fallback,
         _aliases
       ),
       do: fallback

  defp migration_apply_receiver?(:erlang, _aliases), do: true

  defp migration_apply_receiver?(receiver, aliases),
    do: resolve_module_name(receiver, aliases) == "Kernel"

  defp expand_pipeline(pipeline) do
    [{first, _position} | rest] = Macro.unpipe(pipeline)

    Enum.reduce(rest, first, fn {call, position}, piped ->
      Macro.pipe(piped, call, position)
    end)
  end

  defp put_module_aliases(aliases, [target]),
    do: apply_module_aliases(aliases, target, [])

  defp put_module_aliases(aliases, [target, options]) when is_list(options),
    do: apply_module_aliases(aliases, target, options)

  defp put_module_aliases(aliases, _arguments), do: aliases

  defp apply_module_aliases(aliases, target, options) do
    target
    |> module_alias_target_names()
    |> Enum.reduce(aliases, fn target_name, aliases ->
      resolved_target = resolve_module_name(target_name, aliases)

      alias_name =
        case Keyword.get(options, :as) do
          nil -> target_name |> String.split(".") |> List.last()
          explicit_alias -> module_name(explicit_alias)
        end

      if is_binary(alias_name) and is_binary(resolved_target),
        do: Map.put(aliases, alias_name, resolved_target),
        else: aliases
    end)
  end

  defp module_alias_target_names({{:., _dot_metadata, [prefix, :{}]}, _metadata, suffixes})
       when is_list(suffixes) do
    case module_name(prefix) do
      nil ->
        []

      prefix_name ->
        Enum.flat_map(suffixes, fn suffix ->
          case module_name(suffix) do
            nil -> []
            suffix_name -> ["#{prefix_name}.#{suffix_name}"]
          end
        end)
    end
  end

  defp module_alias_target_names(target) do
    case module_name(target) do
      nil -> []
      target_name -> [target_name]
    end
  end

  defp resolve_module_name(target, aliases) when is_binary(target) do
    case String.split(target, ".", parts: 2) do
      [alias_name] -> Map.get(aliases, alias_name, target)
      [alias_name, rest] -> "#{Map.get(aliases, alias_name, alias_name)}.#{rest}"
    end
  end

  defp resolve_module_name(target, aliases) do
    case module_name(target) do
      nil -> nil
      target_name -> resolve_module_name(target_name, aliases)
    end
  end

  defp module_name({:__aliases__, _metadata, parts}) do
    if Enum.all?(parts, &is_atom/1), do: Enum.join(parts, ".")
  end

  defp module_name(_target), do: nil

  defp resolve_module_attributes(node, attributes),
    do: resolve_module_attributes(node, attributes, [])

  defp resolve_module_attributes(
         {:@, _metadata, [{name, _name_metadata, nil}]} = reference,
         attributes,
         resolving
       )
       when is_atom(name) do
    if name in resolving do
      reference
    else
      case Map.fetch(attributes, name) do
        {:ok, value} ->
          resolve_module_attributes(value, attributes, [name | resolving])

        :error ->
          reference
      end
    end
  end

  defp resolve_module_attributes(nodes, attributes, resolving) when is_list(nodes) do
    Enum.map(nodes, &resolve_module_attributes(&1, attributes, resolving))
  end

  defp resolve_module_attributes(node, attributes, resolving) when is_tuple(node) do
    node
    |> Tuple.to_list()
    |> Enum.map(&resolve_module_attributes(&1, attributes, resolving))
    |> List.to_tuple()
  end

  defp resolve_module_attributes(node, _attributes, _resolving), do: node

  defp local_function_head({:when, _meta, [head | guards]}) do
    case local_function_head(head) do
      {key, parameters, []} -> {key, parameters, guards}
      nil -> nil
    end
  end

  defp local_function_head({name, _meta, parameters})
       when is_atom(name) and (is_list(parameters) or is_nil(parameters)) do
    parameters = parameters || []
    {{name, length(parameters)}, parameters, []}
  end

  defp local_function_head(_head), do: nil

  defp local_function_definitions({name, _arity} = key, kind, parameters, guards, body) do
    {parameters, defaults} = normalize_default_parameters(parameters)

    definition = %{
      body: body,
      guards: guards,
      key: key,
      kind: definition_kind(kind),
      parameters: parameters,
      visibility: definition_visibility(kind)
    }

    defaults_by_index = Map.new(defaults)

    wrappers =
      defaults
      |> Enum.with_index(1)
      |> Enum.map(fn {_default, omitted_count} ->
        omitted_indexes =
          defaults
          |> Enum.take(-omitted_count)
          |> MapSet.new(fn {index, _default} -> index end)

        wrapper_parameters =
          parameters
          |> Enum.with_index()
          |> Enum.reject(fn {_parameter, index} -> MapSet.member?(omitted_indexes, index) end)
          |> Enum.map(&elem(&1, 0))

        call_arguments =
          parameters
          |> Enum.with_index()
          |> Enum.map(fn {parameter, index} ->
            if MapSet.member?(omitted_indexes, index),
              do: Map.fetch!(defaults_by_index, index),
              else: parameter
          end)

        %{
          body: {name, [], call_arguments},
          guards: [],
          key: {name, length(wrapper_parameters)},
          kind: :function,
          parameters: wrapper_parameters,
          visibility: definition.visibility
        }
      end)

    [definition | wrappers]
  end

  defp normalize_default_parameters(parameters) do
    parameters
    |> Stream.with_index()
    |> Enum.reduce({[], []}, fn
      {{:\\, _metadata, [parameter, default]}, index}, {parameters, defaults} ->
        {[parameter | parameters], [{index, default} | defaults]}

      {parameter, _index}, {parameters, defaults} ->
        {[parameter | parameters], defaults}
    end)
    |> then(fn {parameters, defaults} ->
      {Enum.reverse(parameters), Enum.reverse(defaults)}
    end)
  end

  defp expand_local_calls({name, metadata, arguments}, functions, call_stack)
       when is_atom(name) and is_list(arguments) do
    key = {name, length(arguments)}

    case Map.get(functions, key) do
      definitions when is_list(definitions) ->
        if key in call_stack do
          {name, metadata, expand_local_calls(arguments, functions, call_stack)}
        else
          definitions
          |> matching_definitions(arguments)
          |> Enum.map(&expand_definition(&1, functions, [key | call_stack]))
          |> block()
        end

      _not_a_reachable_helper ->
        {name, metadata, expand_local_calls(arguments, functions, call_stack)}
    end
  end

  defp expand_local_calls({name, _metadata, nil} = node, functions, call_stack)
       when is_atom(name) do
    key = {name, 0}

    case Map.get(functions, key) do
      definitions when is_list(definitions) ->
        if key in call_stack do
          node
        else
          definitions
          |> matching_definitions([])
          |> Enum.map(&expand_definition(&1, functions, [key | call_stack]))
          |> block()
        end

      _variable_or_recursive_call ->
        node
    end
  end

  defp expand_local_calls(nodes, functions, call_stack) when is_list(nodes) do
    Enum.map(nodes, &expand_local_calls(&1, functions, call_stack))
  end

  defp expand_local_calls(node, functions, call_stack) when is_tuple(node) do
    node
    |> Tuple.to_list()
    |> expand_local_calls(functions, call_stack)
    |> List.to_tuple()
  end

  defp expand_local_calls(node, _functions, _call_stack), do: node

  defp expand_definition(
         %{bindings: bindings, body: body, kind: :function},
         functions,
         call_stack
       ) do
    body
    |> substitute_bindings(bindings)
    |> resolve_local_bindings()
    |> expand_local_calls(functions, call_stack)
  end

  defp expand_definition(%{bindings: bindings, body: body, kind: :macro}, functions, call_stack) do
    body
    |> expand_macro_body(bindings)
    |> expand_local_calls(functions, call_stack)
  end

  defp expand_macro_body({:quote, _metadata, arguments}, bindings) when is_list(arguments) do
    options = quote_options(arguments)

    body =
      if quote_unquotes?(options) do
        options
        |> Keyword.get(:do)
        |> Macro.postwalk(fn
          {:unquote, _metadata, [expression]} -> substitute_bindings(expression, bindings)
          node -> node
        end)
      else
        Keyword.get(options, :do)
      end

    {body, _macro_bindings} =
      resolve_local_bindings(body, bind_quoted_bindings(options, bindings))

    body
  end

  defp expand_macro_body(body, bindings), do: substitute_bindings(body, bindings)

  defp quote_options(arguments) do
    Enum.flat_map(arguments, fn
      options when is_list(options) ->
        if Keyword.keyword?(options), do: options, else: []

      _argument ->
        []
    end)
  end

  defp quote_unquotes?(options) do
    Keyword.get(options, :unquote, not Keyword.has_key?(options, :bind_quoted))
  end

  defp bind_quoted_bindings(options, call_bindings) do
    options
    |> Keyword.get(:bind_quoted, [])
    |> Enum.reduce(%{}, fn
      {name, expression}, bindings when is_atom(name) ->
        Map.put(bindings, name, substitute_bindings(expression, call_bindings))

      _binding, bindings ->
        bindings
    end)
  end

  defp definition_kind(kind) when kind in [:defmacro, :defmacrop], do: :macro
  defp definition_kind(kind) when kind in [:def, :defp], do: :function

  defp definition_visibility(kind) when kind in [:def, :defmacro], do: :public
  defp definition_visibility(kind) when kind in [:defp, :defmacrop], do: :private

  defp matching_definitions(definitions, arguments) do
    definitions
    |> Enum.reduce_while([], fn definition, matches ->
      {pattern_status, bindings} = match_parameters(definition.parameters, arguments)
      bindings = Map.merge(Map.get(definition, :captured_bindings, %{}), bindings)
      guard_status = guards_match(definition.guards, bindings)
      definition = Map.put(definition, :bindings, bindings)

      case {pattern_status, guard_status} do
        {:no_match, _guard_status} ->
          {:cont, matches}

        {_pattern_status, :no_match} ->
          {:cont, matches}

        {:match, :match} ->
          {:halt, [definition | matches]}

        {_possible_pattern, _possible_guard} ->
          {:cont, [definition | matches]}
      end
    end)
    |> Enum.reverse()
  end

  defp match_parameters(patterns, arguments) do
    match_parameter_elements(patterns, arguments, %{})
  end

  defp match_parameter_pattern({:^, _metadata, [_pattern]}, _argument, bindings),
    do: {:unknown, bindings}

  defp match_parameter_pattern({name, _metadata, binding_context}, argument, bindings)
       when is_atom(name) and (is_atom(binding_context) or is_nil(binding_context)) do
    cond do
      name == :_ ->
        {:match, bindings}

      Map.has_key?(bindings, name) ->
        {repeated_binding_status(Map.fetch!(bindings, name), argument), bindings}

      true ->
        {:match, Map.put(bindings, name, argument)}
    end
  end

  defp match_parameter_pattern(
         {:{}, _pattern_metadata, patterns},
         {:{}, _argument_metadata, arguments},
         bindings
       ) do
    if length(patterns) == length(arguments),
      do: match_parameter_elements(patterns, arguments, bindings),
      else: {:no_match, bindings}
  end

  defp match_parameter_pattern(
         {left_pattern, right_pattern},
         {left_argument, right_argument},
         bindings
       ) do
    {left_status, bindings} =
      match_parameter_pattern(left_pattern, left_argument, bindings)

    {right_status, bindings} =
      match_parameter_pattern(right_pattern, right_argument, bindings)

    {combine_match_status(left_status, right_status), bindings}
  end

  defp match_parameter_pattern(patterns, arguments, bindings)
       when is_list(patterns) and is_list(arguments) do
    if length(patterns) == length(arguments),
      do: match_parameter_elements(patterns, arguments, bindings),
      else: {:no_match, bindings}
  end

  defp match_parameter_pattern(pattern, argument, bindings)
       when is_atom(pattern) or is_binary(pattern) or is_number(pattern) do
    status =
      cond do
        pattern == argument -> :match
        is_atom(argument) or is_binary(argument) or is_number(argument) -> :no_match
        true -> :unknown
      end

    {status, bindings}
  end

  defp match_parameter_pattern(_pattern, _argument, bindings), do: {:unknown, bindings}

  defp match_parameter_elements(patterns, arguments, bindings) do
    patterns
    |> Enum.zip(arguments)
    |> Enum.reduce({:match, bindings}, fn {pattern, argument}, {status, bindings} ->
      {next_status, bindings} = match_parameter_pattern(pattern, argument, bindings)
      {combine_match_status(status, next_status), bindings}
    end)
  end

  defp combine_match_status(:no_match, _status), do: :no_match
  defp combine_match_status(_status, :no_match), do: :no_match
  defp combine_match_status(:unknown, _status), do: :unknown
  defp combine_match_status(_status, :unknown), do: :unknown
  defp combine_match_status(:match, :match), do: :match

  defp repeated_binding_status(existing, argument) do
    if Macro.to_string(existing) == Macro.to_string(argument) do
      :match
    else
      with {:known, existing} <- static_guard_value(existing),
           {:known, argument} <- static_guard_value(argument) do
        if existing === argument, do: :match, else: :no_match
      end
    end
  end

  defp block([body]), do: body
  defp block(bodies), do: {:__block__, [], bodies}

  defp substitute_bindings(body, bindings) do
    Macro.postwalk(body, fn
      {name, _metadata, binding_context} = node
      when is_atom(name) and (is_atom(binding_context) or is_nil(binding_context)) ->
        Map.get(bindings, name, node)

      node ->
        node
    end)
  end

  defp resolve_local_bindings(ast) do
    {ast, _bindings} = resolve_local_bindings(ast, %{})
    ast
  end

  defp resolve_local_bindings({:__block__, metadata, expressions}, bindings) do
    {expressions, bindings} =
      Enum.map_reduce(expressions, bindings, &resolve_local_bindings/2)

    {{:__block__, metadata, expressions}, bindings}
  end

  defp resolve_local_bindings({:=, _metadata, [pattern, value]}, bindings) do
    resolved_value = resolve_assignment_value(value, bindings)

    bindings =
      case match_parameter_pattern(pattern, resolved_value, %{}) do
        {:no_match, _new_bindings} -> bindings
        {_status, new_bindings} -> Map.merge(bindings, new_bindings)
      end

    emitted_value =
      if static_migration_closure?(resolved_value),
        do: {:__block__, [], []},
        else: resolved_value

    {emitted_value, bindings}
  end

  defp resolve_local_bindings(
         {{:., _dot_metadata, [callee]}, _metadata, arguments} = node,
         bindings
       )
       when is_list(arguments) do
    callee = substitute_bindings(callee, bindings)

    arguments =
      Enum.map(arguments, fn argument ->
        {argument, _argument_bindings} = resolve_local_bindings(argument, bindings)
        substitute_bindings(argument, bindings)
      end)

    case normalize_migration_closure(callee, bindings) do
      {:ok, clauses, captured_bindings} ->
        {expand_migration_closure(clauses, arguments, captured_bindings), bindings}

      :error ->
        resolve_local_binding_tuple(node, bindings)
    end
  end

  defp resolve_local_bindings({:case, _metadata, [value, options]} = node, bindings)
       when is_list(options) do
    case Keyword.fetch(options, :do) do
      {:ok, clauses} when is_list(clauses) ->
        {value, _value_bindings} = resolve_local_bindings(value, bindings)
        value = substitute_bindings(value, bindings)

        case resolve_static_case_bodies(clauses, value, bindings) do
          {:ok, bodies} -> {block([value | bodies]), bindings}
          :unknown -> resolve_local_binding_tuple(node, bindings)
        end

      _not_a_case_expression ->
        resolve_local_binding_tuple(node, bindings)
    end
  end

  defp resolve_local_bindings({:for, _metadata, arguments} = node, bindings)
       when is_list(arguments) do
    case static_for_parts(arguments) do
      {:ok, qualifiers, body} ->
        case static_for_bindings(qualifiers, [{:definite, bindings}]) do
          {:known, iteration_bindings} ->
            resolve_static_for_bodies(body, iteration_bindings, bindings)

          {:unknown, partial_iteration_bindings} ->
            partial_iteration_bindings =
              Enum.map(partial_iteration_bindings, fn {_certainty, iteration_bindings} ->
                {:possible, iteration_bindings}
              end)

            resolve_static_for_bodies(body, partial_iteration_bindings, bindings)
        end

      :unknown ->
        resolve_local_binding_tuple(node, bindings)
    end
  end

  defp resolve_local_bindings(nodes, bindings) when is_list(nodes) do
    nodes =
      Enum.map(nodes, fn node ->
        {node, _child_bindings} = resolve_local_bindings(node, bindings)
        node
      end)

    {nodes, bindings}
  end

  defp resolve_local_bindings(node, bindings) when is_tuple(node) do
    resolve_local_binding_tuple(node, bindings)
  end

  defp resolve_local_bindings(node, bindings), do: {node, bindings}

  defp resolve_assignment_value({:fn, metadata, clauses}, bindings) when is_list(clauses),
    do: {:__migration_closure__, metadata, [clauses, bindings]}

  defp resolve_assignment_value(value, bindings), do: substitute_bindings(value, bindings)

  defp static_migration_closure?({:__migration_closure__, _metadata, [_clauses, _bindings]}),
    do: true

  defp static_migration_closure?(_value), do: false

  defp normalize_migration_closure(
         {:__migration_closure__, _metadata, [clauses, captured_bindings]},
         _bindings
       )
       when is_list(clauses) and is_map(captured_bindings),
       do: {:ok, clauses, captured_bindings}

  defp normalize_migration_closure({:fn, _metadata, clauses}, bindings) when is_list(clauses),
    do: {:ok, clauses, bindings}

  defp normalize_migration_closure(_callee, _bindings), do: :error

  defp expand_migration_closure(clauses, arguments, captured_bindings) do
    clauses
    |> Enum.flat_map(&migration_closure_definition(&1, captured_bindings))
    |> matching_definitions(arguments)
    |> Enum.map(fn %{bindings: bindings, body: body} ->
      body
      |> substitute_bindings(bindings)
      |> resolve_local_bindings()
    end)
    |> block()
  end

  defp migration_closure_definition(
         {:->, _metadata, [heads, body]},
         captured_bindings
       )
       when is_list(heads) do
    {parameters, guards} = migration_closure_head(heads)

    [
      %{
        body: body,
        captured_bindings: captured_bindings,
        guards: guards,
        parameters: parameters
      }
    ]
  end

  defp migration_closure_definition(_clause, _captured_bindings), do: []

  defp migration_closure_head([
         {:when, _metadata, [_parameter, _guard | _remaining] = guarded_parameters}
       ]) do
    {Enum.drop(guarded_parameters, -1), [List.last(guarded_parameters)]}
  end

  defp migration_closure_head(parameters), do: {parameters, []}

  defp resolve_local_binding_tuple(node, bindings) do
    node =
      node
      |> Tuple.to_list()
      |> Enum.map(fn child ->
        {child, _child_bindings} = resolve_local_bindings(child, bindings)
        child
      end)
      |> List.to_tuple()
      |> substitute_bindings(bindings)

    {node, bindings}
  end

  defp static_for_parts(arguments) do
    case Enum.split(arguments, -1) do
      {qualifiers, [options]} when is_list(options) ->
        if Keyword.keyword?(options) and Keyword.keys(options) == [:do],
          do: {:ok, qualifiers, Keyword.fetch!(options, :do)},
          else: :unknown

      _not_a_plain_comprehension ->
        :unknown
    end
  end

  defp static_for_bindings([], bindings), do: {:known, bindings}

  defp static_for_bindings([qualifier | qualifiers], bindings) do
    case apply_static_for_qualifier(qualifier, bindings) do
      {:known, bindings} -> static_for_bindings(qualifiers, bindings)
      {:unknown, bindings} -> {:unknown, bindings}
    end
  end

  defp resolve_static_for_bodies(body, iteration_bindings, outer_bindings) do
    bodies =
      Enum.map(iteration_bindings, fn {certainty, iteration_bindings} ->
        {body, _body_bindings} = resolve_local_bindings(body, iteration_bindings)
        with_ast_certainty(body, certainty)
      end)

    {block(bodies), outer_bindings}
  end

  defp resolve_static_case_bodies(clauses, value, bindings) do
    Enum.reduce_while(clauses, {:ok, [], false}, fn clause, {:ok, bodies, preceding_possible?} ->
      case resolve_static_case_clause(clause, value, bindings) do
        :no_match ->
          {:cont, {:ok, bodies, preceding_possible?}}

        {:possible, body} ->
          {:cont, {:ok, [with_ast_certainty(body, :possible) | bodies], true}}

        {:definite, body} when preceding_possible? ->
          {:halt, {:ok, [with_ast_certainty(body, :possible) | bodies], true}}

        {:definite, body} ->
          {:halt, {:ok, [body | bodies], false}}

        :unknown ->
          {:halt, :unknown}
      end
    end)
    |> case do
      {:ok, bodies, _preceding_possible?} -> {:ok, Enum.reverse(bodies)}
      :unknown -> :unknown
    end
  end

  defp resolve_static_case_clause({:->, _metadata, [heads, body]}, value, bindings)
       when is_list(heads) do
    with {:ok, pattern, guards} <- static_case_head(heads) do
      {pattern_status, pattern_bindings} = match_parameter_pattern(pattern, value, %{})
      clause_bindings = Map.merge(bindings, pattern_bindings)
      guard_status = guards_match(guards, clause_bindings)

      case {pattern_status, guard_status} do
        {:no_match, _guard_status} ->
          :no_match

        {_pattern_status, :no_match} ->
          :no_match

        {:match, :match} ->
          resolve_static_case_body(body, clause_bindings, :definite)

        {_possible_pattern, _possible_guard} ->
          resolve_static_case_body(body, clause_bindings, :possible)
      end
    end
  end

  defp resolve_static_case_clause(_clause, _value, _bindings), do: :unknown

  defp resolve_static_case_body(body, bindings, certainty) do
    {body, _body_bindings} = resolve_local_bindings(body, bindings)
    {certainty, body}
  end

  defp static_case_head([{:when, _metadata, [pattern | guards]}]),
    do: {:ok, pattern, guards}

  defp static_case_head([pattern]), do: {:ok, pattern, []}
  defp static_case_head(_heads), do: :unknown

  defp apply_static_for_qualifier({:<-, _metadata, [pattern, source]}, bindings) do
    Enum.reduce_while(bindings, {:known, []}, fn {certainty, iteration_bindings},
                                                 {:known, reversed_matches} ->
      source = substitute_bindings(source, iteration_bindings)

      case static_for_values(source) do
        {:known, values} ->
          case bind_static_for_values(pattern, values, iteration_bindings) do
            {:known, value_bindings} ->
              value_bindings =
                Enum.map(value_bindings, &{certainty, &1})

              {:cont, {:known, Enum.reverse(value_bindings, reversed_matches)}}

            :unknown ->
              {:halt, :unknown}
          end

        :unknown ->
          {:halt, :unknown}
      end
    end)
    |> case do
      {:known, reversed_matches} -> {:known, Enum.reverse(reversed_matches)}
      :unknown -> {:unknown, bindings}
    end
  end

  defp apply_static_for_qualifier(qualifier, bindings) do
    bindings =
      Enum.reduce(bindings, [], fn {certainty, iteration_bindings}, matches ->
        qualifier = substitute_bindings(qualifier, iteration_bindings)

        case static_guard_result(qualifier) do
          :match -> [{certainty, iteration_bindings} | matches]
          :no_match -> matches
          :unknown -> [{:possible, iteration_bindings} | matches]
        end
      end)

    {:known, Enum.reverse(bindings)}
  end

  defp with_ast_certainty(body, :definite), do: body

  defp with_ast_certainty(body, :possible),
    do: {:__possible_migration_operations__, [], [body]}

  defp static_for_values(values) when is_list(values) do
    case static_guard_value(values) do
      {:known, _values} -> {:known, values}
      :unknown -> :unknown
    end
  end

  defp static_for_values(_source), do: :unknown

  defp bind_static_for_values(pattern, values, bindings) do
    Enum.reduce_while(values, {:known, []}, fn value, {:known, matches} ->
      case match_parameter_pattern(pattern, value, %{}) do
        {:match, pattern_bindings} ->
          {:cont, {:known, [Map.merge(bindings, pattern_bindings) | matches]}}

        {:no_match, _pattern_bindings} ->
          {:cont, {:known, matches}}

        {:unknown, _pattern_bindings} ->
          {:halt, :unknown}
      end
    end)
    |> case do
      {:known, matches} -> {:known, Enum.reverse(matches)}
      :unknown -> :unknown
    end
  end

  defp guards_match([], _bindings), do: :match

  defp guards_match(guards, bindings) do
    Enum.reduce(guards, :match, fn guard, status ->
      guard_status = guard |> substitute_bindings(bindings) |> static_guard_result()
      combine_guard_and(status, guard_status)
    end)
  end

  defp static_guard_result(true), do: :match
  defp static_guard_result(false), do: :no_match
  defp static_guard_result(nil), do: :no_match

  defp static_guard_result({:when, _metadata, guards}) when is_list(guards) do
    Enum.reduce(guards, :no_match, fn guard, status ->
      combine_guard_or(status, static_guard_result(guard))
    end)
  end

  defp static_guard_result({operation, _metadata, [left, right]})
       when operation in [:and, :or] do
    left_status = static_guard_result(left)
    right_status = static_guard_result(right)

    case operation do
      :and -> combine_guard_and(left_status, right_status)
      :or -> combine_guard_or(left_status, right_status)
    end
  end

  defp static_guard_result({operation, _metadata, [left, right]})
       when operation in [:==, :===, :!=, :!==] do
    with {:known, left} <- static_guard_value(left),
         {:known, right} <- static_guard_value(right) do
      result =
        case operation do
          :== -> left == right
          :=== -> left === right
          :!= -> left != right
          :!== -> left !== right
        end

      if result, do: :match, else: :no_match
    end
  end

  defp static_guard_result(_guard), do: :unknown

  defp static_guard_value(value)
       when is_atom(value) or is_binary(value) or is_number(value),
       do: {:known, value}

  defp static_guard_value(values) when is_list(values) do
    static_guard_values(values, [])
  end

  defp static_guard_value({:{}, _metadata, values}) do
    case static_guard_values(values, []) do
      {:known, values} -> {:known, List.to_tuple(values)}
      :unknown -> :unknown
    end
  end

  defp static_guard_value({left, right}) do
    with {:known, left} <- static_guard_value(left),
         {:known, right} <- static_guard_value(right),
         do: {:known, {left, right}}
  end

  defp static_guard_value(_value), do: :unknown

  defp static_guard_values([], values), do: {:known, Enum.reverse(values)}

  defp static_guard_values([value | remaining], values) do
    case static_guard_value(value) do
      {:known, value} -> static_guard_values(remaining, [value | values])
      :unknown -> :unknown
    end
  end

  defp combine_guard_and(:no_match, _status), do: :no_match
  defp combine_guard_and(_status, :no_match), do: :no_match
  defp combine_guard_and(:unknown, _status), do: :unknown
  defp combine_guard_and(_status, :unknown), do: :unknown
  defp combine_guard_and(:match, :match), do: :match

  defp combine_guard_or(:match, _status), do: :match
  defp combine_guard_or(_status, :match), do: :match
  defp combine_guard_or(:unknown, _status), do: :unknown
  defp combine_guard_or(_status, :unknown), do: :unknown
  defp combine_guard_or(:no_match, :no_match), do: :no_match

  defp migration_foreign_key_operations(ast) do
    collect_foreign_key_operations(ast, nil, :definite)
  end

  defp collect_foreign_key_operations(
         {:__possible_migration_operations__, _metadata, [body]},
         table,
         certainty
       ) do
    collect_foreign_key_operations(body, table, possible_certainty(certainty))
  end

  defp collect_foreign_key_operations(
         {operator, _metadata, [condition, options]},
         table,
         certainty
       )
       when operator in [:if, :unless] and is_list(options) do
    condition_operations = collect_foreign_key_operations(condition, table, certainty)
    do_branch = Keyword.get(options, :do)
    else_branch = Keyword.get(options, :else)

    branch_operations =
      case selected_static_branch(operator, condition) do
        :do ->
          collect_foreign_key_operations(do_branch, table, certainty)

        :else ->
          collect_foreign_key_operations(else_branch, table, certainty)

        :unknown ->
          possible_certainty = possible_certainty(certainty)

          [do_branch, else_branch]
          |> Enum.flat_map(&collect_foreign_key_operations(&1, table, possible_certainty))
      end

    condition_operations ++ branch_operations
  end

  defp collect_foreign_key_operations(
         {:rename, _metadata,
          [
            {:table, _old_table_metadata, [old_table | old_table_options]},
            [to: {:table, _new_table_metadata, [new_table | new_table_options]}]
          ]},
         _table,
         certainty
       )
       when (is_atom(old_table) or is_binary(old_table)) and
              (is_atom(new_table) or is_binary(new_table)) do
    operation =
      {:rename_table, table_identity(old_table, old_table_options),
       table_identity(new_table, new_table_options)}

    [with_certainty(operation, certainty)]
  end

  defp collect_foreign_key_operations(
         {:rename, _metadata,
          [
            {:table, _table_metadata, [table | table_options]},
            old_column,
            [to: new_column]
          ]},
         _table,
         certainty
       )
       when (is_atom(table) or is_binary(table)) and is_atom(old_column) and
              is_atom(new_column) do
    operation =
      {:rename_column, table_identity(table, table_options), Atom.to_string(old_column),
       Atom.to_string(new_column)}

    [with_certainty(operation, certainty)]
  end

  defp collect_foreign_key_operations(
         {operation, _metadata,
          [{:table, _table_metadata, [table | table_options]}, [do: block]]},
         _current_table,
         certainty
       )
       when operation in @table_definition_operations and
              (is_atom(table) or is_binary(table)) do
    collect_foreign_key_operations(block, table_identity(table, table_options), certainty)
  end

  defp collect_foreign_key_operations(
         {operation, _metadata,
          [{:constraint, _constraint_metadata, [table, name | constraint_options]}]},
         _current_table,
         certainty
       )
       when operation in @table_drop_operations and
              (is_atom(table) or is_binary(table)) and
              (is_atom(name) or is_binary(name)) do
    operation = {:drop_constraint, table_identity(table, constraint_options), to_string(name)}
    [with_certainty(operation, certainty)]
  end

  defp collect_foreign_key_operations(
         {operation, _metadata,
          [{:table, _table_metadata, [table | table_options]} | drop_options]},
         _current_table,
         certainty
       )
       when operation in @table_drop_operations and
              (is_atom(table) or is_binary(table)) do
    operation =
      {:drop_table, table_identity(table, table_options), cascading_drop?(drop_options)}

    [with_certainty(operation, certainty)]
  end

  defp collect_foreign_key_operations(
         {operation, _metadata,
          [
            column,
            {:references, _references_metadata, [destination | reference_options]}
            | _column_options
          ]},
         table,
         certainty
       )
       when operation in @foreign_key_definition_operations and is_binary(table) and
              is_atom(column) and
              (is_atom(destination) or is_binary(destination)) do
    reference_options = List.flatten(reference_options)

    destination_prefix =
      Keyword.get(reference_options, :prefix, table_prefix_from_identity(table))

    foreign_key = {
      table,
      Atom.to_string(column),
      schema_table_identity(destination, destination_prefix),
      reference_options |> Keyword.get(:column, :id) |> Atom.to_string(),
      foreign_key_constraint_name(table, column, reference_options)
    }

    [with_certainty({:put, foreign_key}, certainty)]
  end

  defp collect_foreign_key_operations(
         {operation, _metadata, [column | _options]},
         table,
         certainty
       )
       when operation in [:remove, :remove_if_exists] and is_binary(table) and is_atom(column) do
    operation = {:remove, table, Atom.to_string(column)}
    [with_certainty(operation, certainty)]
  end

  defp collect_foreign_key_operations(nodes, table, certainty) when is_list(nodes) do
    Enum.flat_map(nodes, &collect_foreign_key_operations(&1, table, certainty))
  end

  defp collect_foreign_key_operations(node, table, certainty) when is_tuple(node) do
    node
    |> Tuple.to_list()
    |> Enum.flat_map(&collect_foreign_key_operations(&1, table, certainty))
  end

  defp collect_foreign_key_operations(_node, _table, _certainty), do: []

  defp foreign_key_constraint_name(table, column, reference_options) do
    case Keyword.get(reference_options, :name) do
      nil -> "#{table_name_from_identity(table)}_#{column}_fkey"
      name when is_atom(name) or is_binary(name) -> to_string(name)
    end
  end

  defp cascading_drop?(drop_options) do
    options =
      Enum.flat_map(drop_options, fn
        options when is_list(options) -> options
        _option -> []
      end)

    Keyword.get(options, :mode) == :cascade
  end

  defp migration_table_operations(ast) do
    collect_table_operations(ast, :definite)
  end

  defp collect_table_operations(
         {:__possible_migration_operations__, _metadata, [body]},
         certainty
       ) do
    collect_table_operations(body, possible_certainty(certainty))
  end

  defp collect_table_operations(
         {operator, _metadata, [condition, options]},
         certainty
       )
       when operator in [:if, :unless] and is_list(options) do
    condition_operations = collect_table_operations(condition, certainty)

    do_branch = Keyword.get(options, :do)
    else_branch = Keyword.get(options, :else)

    branch_operations =
      case selected_static_branch(operator, condition) do
        :do ->
          collect_table_operations(do_branch, certainty)

        :else ->
          collect_table_operations(else_branch, certainty)

        :unknown ->
          possible_certainty = possible_certainty(certainty)

          [do_branch, else_branch]
          |> Enum.flat_map(&collect_table_operations(&1, possible_certainty))
      end

    condition_operations ++ branch_operations
  end

  defp collect_table_operations(nodes, certainty) when is_list(nodes) do
    Enum.flat_map(nodes, &collect_table_operations(&1, certainty))
  end

  defp collect_table_operations(node, certainty) when is_tuple(node) do
    operation =
      case table_operation(node) do
        nil -> []
        operation -> [with_certainty(operation, certainty)]
      end

    children =
      node
      |> Tuple.to_list()
      |> Enum.flat_map(&collect_table_operations(&1, certainty))

    operation ++ children
  end

  defp collect_table_operations(_node, _certainty), do: []

  defp selected_static_branch(:if, condition) do
    case static_truthiness(condition) do
      :truthy -> :do
      :falsy -> :else
      :unknown -> :unknown
    end
  end

  defp selected_static_branch(:unless, condition) do
    case static_truthiness(condition) do
      :truthy -> :else
      :falsy -> :do
      :unknown -> :unknown
    end
  end

  defp static_truthiness(condition) do
    case static_guard_result(condition) do
      :match ->
        :truthy

      :no_match ->
        :falsy

      :unknown ->
        case static_guard_value(condition) do
          {:known, value} when value in [false, nil] -> :falsy
          {:known, _value} -> :truthy
          :unknown -> :unknown
        end
    end
  end

  defp possible_certainty(_certainty), do: :possible
  defp with_certainty(operation, :definite), do: operation
  defp with_certainty(operation, :possible), do: {:possible, operation}

  defp table_operation(
         {:rename, _metadata,
          [
            {:table, _old_table_metadata, [old_table | old_table_options]},
            [to: {:table, _new_table_metadata, [new_table | new_table_options]}]
          ]}
       )
       when (is_atom(old_table) or is_binary(old_table)) and
              (is_atom(new_table) or is_binary(new_table)) do
    {:rename, table_identity(old_table, old_table_options),
     table_identity(new_table, new_table_options)}
  end

  defp table_operation(
         {operation, _metadata, [{:table, _table_metadata, [table | table_options]} | _options]}
       )
       when operation in @table_lifecycle_operations and
              (is_atom(table) or is_binary(table)) do
    lifecycle_operation = if operation in @table_create_operations, do: :create, else: :drop
    {lifecycle_operation, table_identity(table, table_options)}
  end

  defp table_operation(_node), do: nil

  defp table_identity(table, options) do
    options = List.flatten(options)

    prefix =
      case Keyword.fetch(options, :prefix) do
        {:ok, prefix} when is_nil(prefix) or is_atom(prefix) or is_binary(prefix) ->
          prefix

        {:ok, prefix} ->
          raise ArgumentError,
                "cannot statically resolve migration table prefix: #{Macro.to_string(prefix)}"

        :error ->
          nil
      end

    schema_table_identity(table, prefix)
  end

  defp schema_table_identity(table, prefix) when prefix in [nil, :public, "public"],
    do: to_string(table)

  defp schema_table_identity(table, prefix) when is_atom(prefix) or is_binary(prefix),
    do: "#{prefix}.#{table}"

  defp resource_table_identity(table, resource),
    do: schema_table_identity(table, AshPostgres.DataLayer.Info.schema(resource))

  defp table_prefix_from_identity(identity) do
    case String.split(identity, ".", parts: 2) do
      [_table] -> nil
      [prefix, _table] -> prefix
    end
  end

  defp table_name_from_identity(identity) do
    case String.split(identity, ".", parts: 2) do
      [table] -> table
      [_prefix, table] -> table
    end
  end

  defp apply_table_operation({:create, table}, tables), do: MapSet.put(tables, table)
  defp apply_table_operation({:drop, table}, tables), do: MapSet.delete(tables, table)

  defp apply_table_operation({:possible, {:create, table}}, tables),
    do: MapSet.put(tables, table)

  defp apply_table_operation({:possible, {:drop, _table}}, tables), do: tables

  defp apply_table_operation({:possible, {:rename, _old_table, new_table}}, tables),
    do: MapSet.put(tables, new_table)

  defp apply_table_operation({:rename, old_table, new_table}, tables) do
    tables
    |> MapSet.delete(old_table)
    |> MapSet.put(new_table)
  end

  defp apply_foreign_key_operation({:put, foreign_key}, foreign_keys) do
    Map.put(foreign_keys, foreign_key_identity(foreign_key), MapSet.new([foreign_key]))
  end

  defp apply_foreign_key_operation({:possible, {:put, foreign_key}}, foreign_keys) do
    Map.update(
      foreign_keys,
      foreign_key_identity(foreign_key),
      MapSet.new([foreign_key]),
      &MapSet.put(&1, foreign_key)
    )
  end

  defp apply_foreign_key_operation({:remove, table, column}, foreign_keys),
    do: Map.delete(foreign_keys, {table, column})

  defp apply_foreign_key_operation({:possible, {:remove, _table, _column}}, foreign_keys),
    do: foreign_keys

  defp apply_foreign_key_operation({:drop_table, table, cascading?}, foreign_keys) do
    reject_foreign_keys(foreign_keys, fn
      {source_table, _source_column, destination_table, _destination_column, _constraint_name} ->
        source_table == table or (cascading? and destination_table == table)
    end)
  end

  defp apply_foreign_key_operation(
         {:possible, {:drop_table, _table, _cascading?}},
         foreign_keys
       ),
       do: foreign_keys

  defp apply_foreign_key_operation({:drop_constraint, table, name}, foreign_keys) do
    reject_foreign_keys(foreign_keys, fn
      {source_table, _source_column, _destination_table, _destination_column, constraint_name} ->
        source_table == table and constraint_name == name
    end)
  end

  defp apply_foreign_key_operation(
         {:possible, {:drop_constraint, _table, _name}},
         foreign_keys
       ),
       do: foreign_keys

  defp apply_foreign_key_operation({:rename_table, old_table, new_table}, foreign_keys) do
    remap_foreign_keys(foreign_keys, &rename_foreign_key_table(&1, old_table, new_table))
  end

  defp apply_foreign_key_operation(
         {:possible, {:rename_table, old_table, new_table}},
         foreign_keys
       ) do
    add_possible_foreign_key_variants(
      foreign_keys,
      &rename_foreign_key_table(&1, old_table, new_table)
    )
  end

  defp apply_foreign_key_operation(
         {:rename_column, table, old_column, new_column},
         foreign_keys
       ) do
    remap_foreign_keys(
      foreign_keys,
      &rename_foreign_key_column(&1, table, old_column, new_column)
    )
  end

  defp apply_foreign_key_operation(
         {:possible, {:rename_column, table, old_column, new_column}},
         foreign_keys
       ) do
    add_possible_foreign_key_variants(
      foreign_keys,
      &rename_foreign_key_column(&1, table, old_column, new_column)
    )
  end

  defp foreign_key_identity({table, column, _destination_table, _destination_column, _name}),
    do: {table, column}

  defp rename_foreign_key_table(
         {source_table, source_column, destination_table, destination_column, constraint_name},
         old_table,
         new_table
       ) do
    source_table = if source_table == old_table, do: new_table, else: source_table
    destination_table = if destination_table == old_table, do: new_table, else: destination_table

    {source_table, source_column, destination_table, destination_column, constraint_name}
  end

  defp rename_foreign_key_column(
         {source_table, source_column, destination_table, destination_column, constraint_name},
         table,
         old_column,
         new_column
       ) do
    source_column =
      if source_table == table and source_column == old_column,
        do: new_column,
        else: source_column

    destination_column =
      if destination_table == table and destination_column == old_column,
        do: new_column,
        else: destination_column

    {source_table, source_column, destination_table, destination_column, constraint_name}
  end

  defp remap_foreign_keys(foreign_keys, mapper) do
    Enum.reduce(foreign_keys, %{}, fn {_identity, candidates}, remapped ->
      Enum.reduce(candidates, remapped, fn foreign_key, remapped ->
        foreign_key = mapper.(foreign_key)

        Map.update(
          remapped,
          foreign_key_identity(foreign_key),
          MapSet.new([foreign_key]),
          &MapSet.put(&1, foreign_key)
        )
      end)
    end)
  end

  defp add_possible_foreign_key_variants(foreign_keys, mapper) do
    Enum.reduce(foreign_keys, foreign_keys, fn {_identity, candidates}, expanded ->
      Enum.reduce(candidates, expanded, fn foreign_key, expanded ->
        possible_foreign_key = mapper.(foreign_key)

        Map.update(
          expanded,
          foreign_key_identity(possible_foreign_key),
          MapSet.new([possible_foreign_key]),
          &MapSet.put(&1, possible_foreign_key)
        )
      end)
    end)
  end

  defp reject_foreign_keys(foreign_keys, reject?) do
    Enum.reduce(foreign_keys, %{}, fn {identity, candidates}, remaining ->
      candidates = MapSet.reject(candidates, reject?)

      if MapSet.size(candidates) == 0,
        do: remaining,
        else: Map.put(remaining, identity, candidates)
    end)
  end
end

defmodule OfficeGraph.TestSupport.MigrationConformanceSupport.AuditParentResource do
  @moduledoc false

  use Ash.Resource, domain: nil, data_layer: AshPostgres.DataLayer

  postgres do
    table "parents"
    schema "audit"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    uuid_primary_key :id
  end
end

defmodule OfficeGraph.TestSupport.MigrationConformanceSupport.AuditChildResource do
  @moduledoc false

  use Ash.Resource, domain: nil, data_layer: AshPostgres.DataLayer

  postgres do
    table "children"
    schema "audit"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    uuid_primary_key :id
    attribute :parent_id, :uuid
  end
end
