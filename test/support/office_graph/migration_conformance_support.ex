defmodule OfficeGraph.TestSupport.MigrationConformanceSupport do
  @moduledoc false

  @framework_objects %{
    table: MapSet.new(["oban_jobs", "schema_migrations"]),
    sequence: MapSet.new(["oban_jobs_id_seq"])
  }
  @allowed_extensions MapSet.new(["plpgsql"])
  @approved_exceptions_path "openspec/specs/ecto-sql-boundaries/approved-database-exceptions.json"

  def migration_tables do
    terminal_inventory().tables
    |> reject_framework_objects(:table)
    |> Enum.sort()
  end

  def resource_table_identities(expected_resources) do
    expected_resources
    |> Enum.map(fn {_table, {_domain, resource}} -> resource_table_identity(resource) end)
    |> Enum.sort()
  end

  def migration_foreign_key_relationship_errors(
        expected_resources,
        inventory \\ terminal_inventory()
      ) do
    resources_by_table =
      Map.new(expected_resources, fn {_table, {_domain, resource}} ->
        {resource_table_identity(resource), resource}
      end)

    inventory.foreign_keys
    |> Enum.flat_map(fn {source_table, source_attribute, destination_table, destination_attribute} ->
      case Map.fetch(resources_by_table, source_table) do
        :error ->
          []

        {:ok, source} ->
          case Map.fetch(resources_by_table, destination_table) do
            :error ->
              foreign_key_relationship_error(
                source_table,
                source_attribute,
                destination_table,
                destination_attribute
              )

            {:ok, destination} ->
              source_columns = identifier_list(source_attribute)
              destination_columns = identifier_list(destination_attribute)

              if matching_belongs_to?(
                   source,
                   destination,
                   destination_table,
                   source_columns,
                   destination_columns
                 ) do
                []
              else
                foreign_key_relationship_error(
                  source_table,
                  source_attribute,
                  destination_table,
                  destination_attribute
                )
              end
          end
      end
    end)
    |> Enum.sort()
  end

  def terminal_database_errors(
        expected_resources \\ expected_resource_map(),
        inventory \\ terminal_inventory(),
        approved_terminal_objects \\ approved_terminal_objects()
      ) do
    expected_tables = expected_resources |> resource_table_identities() |> MapSet.new()
    project_tables = reject_framework_objects(inventory.tables, :table)

    missing_tables =
      expected_tables
      |> MapSet.difference(project_tables)
      |> Enum.map(&"missing Ash-owned table #{&1}")

    unexpected_tables =
      project_tables
      |> MapSet.difference(expected_tables)
      |> Enum.map(&"unexpected project table #{&1}")

    expected_sequences = expected_sequences(expected_resources)
    project_sequences = reject_framework_objects(inventory.sequences, :sequence)

    missing_sequences =
      expected_sequences
      |> MapSet.difference(project_sequences)
      |> Enum.map(&"missing Ash-owned sequence #{&1}")

    unexpected_sequences =
      project_sequences
      |> MapSet.difference(expected_sequences)
      |> Enum.map(&"unexpected project sequence #{&1}")

    prohibited_objects = terminal_object_errors(inventory, approved_terminal_objects)

    (missing_tables ++
       unexpected_tables ++
       missing_sequences ++
       unexpected_sequences ++
       table_shape_errors(inventory, expected_resources, project_tables) ++
       prohibited_objects ++
       migration_foreign_key_relationship_errors(expected_resources, inventory))
    |> Enum.sort()
  end

  def verify_terminal_database! do
    case terminal_database_errors() do
      [] ->
        :ok

      errors ->
        raise "terminal database inventory does not match Ash ownership:\n" <>
                Enum.map_join(errors, "\n", &"  * #{&1}")
    end
  end

  def terminal_inventory do
    key = {__MODULE__, :terminal_inventory, File.cwd!()}

    case Process.get(key) do
      nil ->
        inventory = dump_terminal_inventory!()
        Process.put(key, inventory)
        inventory

      inventory ->
        inventory
    end
  end

  def parse_dump(dump) when is_binary(dump) do
    initial = %{
      columns: MapSet.new(),
      constraints: MapSet.new(),
      extensions: MapSet.new(),
      foreign_keys: MapSet.new(),
      grants: MapSet.new(),
      indexes: MapSet.new(),
      materialized_views: MapSet.new(),
      policies: MapSet.new(),
      primary_keys: MapSet.new(),
      routines: MapSet.new(),
      sequences: MapSet.new(),
      tables: MapSet.new(),
      terminal_objects: MapSet.new(),
      triggers: MapSet.new(),
      views: MapSet.new()
    }

    inventory =
      dump
      |> String.split("\n")
      |> Enum.reduce({initial, nil}, &parse_dump_line/2)
      |> elem(0)
      |> Map.update!(:foreign_keys, fn keys ->
        keys
        |> MapSet.to_list()
        |> Enum.sort()
      end)

    Map.put(inventory, :terminal_objects, terminal_objects(dump))
  end

  defp terminal_object_errors(inventory, approved_terminal_objects) do
    actual =
      inventory
      |> Map.get(:terminal_objects, MapSet.new())
      |> Enum.reject(fn {class, identity, _fingerprint} ->
        allowed_terminal_object?(class, identity)
      end)
      |> Enum.group_by(fn {class, identity, _fingerprint} -> {class, identity} end, fn {
                                                                                         _class,
                                                                                         _identity,
                                                                                         fingerprint
                                                                                       } ->
        fingerprint
      end)
      |> Map.new(fn {identity, fingerprints} -> {identity, MapSet.new(fingerprints)} end)

    approved =
      approved_terminal_objects
      |> Enum.map(&normalize_terminal_approval!/1)
      |> Enum.group_by(fn {class, identity, _fingerprint} -> {class, identity} end, fn {
                                                                                         _class,
                                                                                         _identity,
                                                                                         fingerprint
                                                                                       } ->
        fingerprint
      end)
      |> Map.new(fn {identity, fingerprints} -> {identity, MapSet.new(fingerprints)} end)

    actual_keys = actual |> Map.keys() |> MapSet.new()
    approved_keys = approved |> Map.keys() |> MapSet.new()

    missing_definitions =
      inventory
      |> prohibited_terminal_identities()
      |> MapSet.difference(actual_keys)
      |> Enum.map(fn {class, identity} ->
        "terminal definition unavailable for project #{class} #{identity}"
      end)

    comparison_errors =
      actual_keys
      |> MapSet.union(approved_keys)
      |> Enum.flat_map(fn {class, identity} = key ->
        case {Map.fetch(actual, key), Map.fetch(approved, key)} do
          {{:ok, _actual}, :error} ->
            ["unexpected project #{class} #{identity}"]

          {:error, {:ok, _approved}} ->
            ["missing approved project #{class} #{identity}"]

          {{:ok, fingerprints}, {:ok, fingerprints}} ->
            []

          {{:ok, _actual}, {:ok, _approved}} ->
            ["terminal definition mismatch for approved project #{class} #{identity}"]
        end
      end)

    (missing_definitions ++ comparison_errors)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp prohibited_terminal_identities(inventory) do
    [
      {"view", inventory.views},
      {"materialized view", inventory.materialized_views},
      {"routine", inventory.routines},
      {"trigger", reject_framework_triggers(inventory.triggers)},
      {"RLS policy", inventory.policies},
      {"grant", inventory.grants},
      {"extension", MapSet.difference(inventory.extensions, @allowed_extensions)}
    ]
    |> Enum.flat_map(fn {class, identities} ->
      Enum.map(identities, &{class, &1})
    end)
    |> MapSet.new()
  end

  defp allowed_terminal_object?("extension", identity),
    do: MapSet.member?(@allowed_extensions, identity)

  defp allowed_terminal_object?("trigger", identity) do
    identity
    |> String.split(" ON ", parts: 2)
    |> List.last()
    |> then(&framework_owned?(:table, &1))
  end

  defp allowed_terminal_object?(_class, _identity), do: false

  defp approved_terminal_objects do
    @approved_exceptions_path
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("exceptions")
    |> Enum.flat_map(&Map.get(&1, "terminal_objects", []))
  end

  defp normalize_terminal_approval!(%{
         "class" => class,
         "identity" => identity,
         "fingerprint" => fingerprint
       })
       when is_binary(class) and class != "" and is_binary(identity) and identity != "" and
              is_binary(fingerprint) and fingerprint != "",
       do: {class, identity, fingerprint}

  defp normalize_terminal_approval!({class, identity, fingerprint})
       when is_binary(class) and is_binary(identity) and is_binary(fingerprint),
       do: {class, identity, fingerprint}

  defp normalize_terminal_approval!(approval) do
    raise ArgumentError, "invalid approved terminal database object: #{inspect(approval)}"
  end

  defp terminal_objects(dump) do
    dump
    |> sql_statements()
    |> Enum.flat_map(fn statement ->
      case terminal_object_identity(statement) do
        nil -> []
        {class, identity} -> [{class, identity, fingerprint_statement(statement)}]
      end
    end)
    |> MapSet.new()
  end

  defp terminal_object_identity(statement) do
    cond do
      identity = capture(statement, ~r/^CREATE MATERIALIZED VIEW (?<identity>\S+) AS/s) ->
        {"materialized view", normalize_identity(identity)}

      identity = capture(statement, ~r/^CREATE VIEW (?<identity>\S+) AS/s) ->
        {"view", normalize_identity(identity)}

      identity = routine_identity(statement) ->
        {"routine", identity}

      trigger =
          capture(
            statement,
            ~r/^CREATE (?:CONSTRAINT )?TRIGGER (?<name>\S+) .* ON (?<table>\S+)/s
          ) ->
        {"trigger", normalize_trigger(trigger, statement)}

      policy = capture(statement, ~r/^CREATE POLICY (?<name>\S+) ON (?<table>\S+)/s) ->
        {"RLS policy", normalize_policy(policy, statement)}

      extension =
          capture(statement, ~r/^CREATE EXTENSION IF NOT EXISTS (?<name>\S+)/s) ->
        {"extension", trim_identifier(extension)}

      grant = grant_identity(statement) ->
        {"grant", grant}

      true ->
        nil
    end
  end

  defp fingerprint_statement(statement) do
    "sha256:" <>
      Base.encode16(:crypto.hash(:sha256, String.trim(statement)), case: :lower)
  end

  defp routine_identity(statement) do
    case Regex.named_captures(
           ~r/^CREATE (?:OR REPLACE )?(?:FUNCTION|PROCEDURE) (?<name>[^\s\(]+)\((?<arguments>[^\n]*)\)/s,
           String.trim(statement)
         ) do
      %{"name" => name, "arguments" => arguments} ->
        arguments = arguments |> String.trim() |> String.replace(~r/\s+/, " ")
        "#{normalize_identity(name)}(#{arguments})"

      nil ->
        nil
    end
  end

  defp grant_identity(statement) do
    case Regex.named_captures(
           ~r/^GRANT (?<privileges>.+?) ON (?<object_type>.+?) (?<identity>\S+) TO (?<grantee>.+);$/s,
           String.trim(statement)
         ) do
      %{
        "privileges" => privileges,
        "object_type" => object_type,
        "identity" => identity,
        "grantee" => grantee
      } ->
        "#{String.trim(privileges)} ON #{String.trim(object_type)} #{normalize_identity(identity)} TO #{String.trim(grantee)}"

      nil ->
        nil
    end
  end

  defp sql_statements(dump), do: split_sql(dump, :plain, [], [])

  defp split_sql(<<>>, _state, current, statements) do
    statements
    |> finish_statement(current)
    |> Enum.reverse()
  end

  defp split_sql(<<"--", rest::binary>>, :plain, current, statements),
    do: split_sql(rest, :line_comment, current, statements)

  defp split_sql(<<"/*", rest::binary>>, :plain, current, statements),
    do: split_sql(rest, :block_comment, current, statements)

  defp split_sql(<<"'", rest::binary>>, :plain, current, statements),
    do: split_sql(rest, :single_quote, ["'" | current], statements)

  defp split_sql(<<"\"", rest::binary>>, :plain, current, statements),
    do: split_sql(rest, :double_quote, ["\"" | current], statements)

  defp split_sql(<<"$", _rest::binary>> = input, :plain, current, statements) do
    case Regex.run(~r/^\$(?:[A-Za-z_][A-Za-z0-9_]*)?\$/, input) do
      [delimiter] ->
        <<^delimiter::binary, rest::binary>> = input
        split_sql(rest, {:dollar_quote, delimiter}, [delimiter | current], statements)

      nil ->
        <<character::utf8, rest::binary>> = input
        split_sql(rest, :plain, [<<character::utf8>> | current], statements)
    end
  end

  defp split_sql(<<";", rest::binary>>, :plain, current, statements) do
    statements = finish_statement(statements, [";" | current])
    split_sql(rest, :plain, [], statements)
  end

  defp split_sql(<<"''", rest::binary>>, :single_quote, current, statements),
    do: split_sql(rest, :single_quote, ["''" | current], statements)

  defp split_sql(<<"'", rest::binary>>, :single_quote, current, statements),
    do: split_sql(rest, :plain, ["'" | current], statements)

  defp split_sql(<<"\"\"", rest::binary>>, :double_quote, current, statements),
    do: split_sql(rest, :double_quote, ["\"\"" | current], statements)

  defp split_sql(<<"\"", rest::binary>>, :double_quote, current, statements),
    do: split_sql(rest, :plain, ["\"" | current], statements)

  defp split_sql(<<"\n", rest::binary>>, :line_comment, current, statements),
    do: split_sql(rest, :plain, ["\n" | current], statements)

  defp split_sql(<<_character::utf8, rest::binary>>, :line_comment, current, statements),
    do: split_sql(rest, :line_comment, current, statements)

  defp split_sql(<<"*/", rest::binary>>, :block_comment, current, statements),
    do: split_sql(rest, :plain, [" " | current], statements)

  defp split_sql(<<_character::utf8, rest::binary>>, :block_comment, current, statements),
    do: split_sql(rest, :block_comment, current, statements)

  defp split_sql(input, {:dollar_quote, delimiter} = state, current, statements) do
    if String.starts_with?(input, delimiter) do
      rest = binary_part(input, byte_size(delimiter), byte_size(input) - byte_size(delimiter))
      split_sql(rest, :plain, [delimiter | current], statements)
    else
      <<character::utf8, rest::binary>> = input
      split_sql(rest, state, [<<character::utf8>> | current], statements)
    end
  end

  defp split_sql(<<character::utf8, rest::binary>>, state, current, statements),
    do: split_sql(rest, state, [<<character::utf8>> | current], statements)

  defp finish_statement(statements, current) do
    statement = current |> Enum.reverse() |> IO.iodata_to_binary() |> String.trim()
    if statement == "", do: statements, else: [statement | statements]
  end

  defp dump_terminal_inventory! do
    config = OfficeGraph.Repo.config()

    args = [
      "--schema-only",
      "--no-owner",
      "--host",
      to_string(Keyword.fetch!(config, :hostname)),
      "--port",
      to_string(Keyword.fetch!(config, :port)),
      "--username",
      to_string(Keyword.fetch!(config, :username)),
      "--dbname",
      to_string(Keyword.fetch!(config, :database))
    ]

    env =
      case Keyword.get(config, :password) do
        nil -> []
        password -> [{"PGPASSWORD", to_string(password)}]
      end

    case System.find_executable("pg_dump") do
      nil ->
        dump_with_docker_or_raise!(config, "pg_dump is not available on PATH", :unavailable)

      executable ->
        case System.cmd(executable, args, env: env, stderr_to_stdout: true) do
          {dump, 0} -> parse_dump(dump)
          {output, status} -> dump_with_docker_or_raise!(config, output, status)
        end
    end
  end

  defp dump_with_docker_or_raise!(config, local_output, local_status) do
    with {:ok, container} <- postgres_container_for_port(Keyword.fetch!(config, :port)),
         {:ok, dump} <- docker_pg_dump(container, config) do
      parse_dump(dump)
    else
      {:error, reason} ->
        raise "pg_dump failed with status #{local_status} and Docker fallback failed (#{reason}):\n#{local_output}"
    end
  end

  defp postgres_container_for_port(port) do
    case System.cmd("docker", ["ps", "--format", "{{.ID}} {{.Ports}}"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.find_value(fn line ->
          if String.contains?(line, ":#{port}->5432/tcp") do
            line |> String.split(" ", parts: 2) |> List.first()
          end
        end)
        |> case do
          nil -> {:error, "no running PostgreSQL container maps host port #{port}"}
          container -> {:ok, container}
        end

      {output, status} ->
        {:error, "docker ps failed with status #{status}: #{String.trim(output)}"}
    end
  end

  defp docker_pg_dump(container, config) do
    args =
      [
        "exec",
        "-e",
        "PGPASSWORD=#{Keyword.get(config, :password)}",
        container,
        "pg_dump",
        "--schema-only",
        "--no-owner",
        "--username",
        to_string(Keyword.fetch!(config, :username)),
        "--dbname",
        to_string(Keyword.fetch!(config, :database))
      ]

    case System.cmd("docker", args, stderr_to_stdout: true) do
      {dump, 0} ->
        {:ok, dump}

      {output, status} ->
        {:error, "docker pg_dump failed with status #{status}: #{String.trim(output)}"}
    end
  end

  defp parse_dump_line(line, {inventory, current_table}) do
    cond do
      table = capture(line, ~r/^CREATE (?:FOREIGN )?TABLE (?<identity>\S+) \($/) ->
        table = normalize_identity(table)
        {Map.update!(inventory, :tables, &MapSet.put(&1, table)), {:create_table, table}}

      match?({:create_table, _table}, current_table) &&
          String.starts_with?(String.trim_leading(line), ")") ->
        {inventory, nil}

      match?({:create_table, _table}, current_table) ->
        {:create_table, table} = current_table
        {parse_table_column(line, table, inventory), current_table}

      alter_default = parse_alter_column_default(line) ->
        {put_column_default(inventory, alter_default), current_table}

      constraint_table = capture(line, ~r/^ALTER TABLE ONLY (?<identity>\S+)$/) ->
        {inventory, {:alter_table, normalize_identity(constraint_table)}}

      match?({:alter_table, _table}, current_table) ->
        {:alter_table, table} = current_table
        {parse_alter_table_line(line, table, inventory), nil}

      sequence = capture(line, ~r/^CREATE SEQUENCE (?<identity>\S+)/) ->
        {Map.update!(inventory, :sequences, &MapSet.put(&1, normalize_identity(sequence))),
         current_table}

      view = capture(line, ~r/^CREATE VIEW (?<identity>\S+) AS/) ->
        {Map.update!(inventory, :views, &MapSet.put(&1, normalize_identity(view))), current_table}

      view = capture(line, ~r/^CREATE MATERIALIZED VIEW (?<identity>\S+) AS/) ->
        {Map.update!(inventory, :materialized_views, &MapSet.put(&1, normalize_identity(view))),
         current_table}

      routine = routine_identity(line) ->
        {Map.update!(inventory, :routines, &MapSet.put(&1, routine)), current_table}

      trigger =
          capture(line, ~r/^CREATE (?:CONSTRAINT )?TRIGGER (?<name>\S+) .* ON (?<table>\S+)/) ->
        {Map.update!(inventory, :triggers, &MapSet.put(&1, normalize_trigger(trigger, line))),
         current_table}

      policy = capture(line, ~r/^CREATE POLICY (?<name>\S+) ON (?<table>\S+)/) ->
        {Map.update!(inventory, :policies, &MapSet.put(&1, normalize_policy(policy, line))),
         current_table}

      extension = capture(line, ~r/^CREATE EXTENSION IF NOT EXISTS (?<name>\S+)/) ->
        {Map.update!(inventory, :extensions, &MapSet.put(&1, trim_identifier(extension))),
         current_table}

      grant = grant_identity(line) ->
        {Map.update!(inventory, :grants, &MapSet.put(&1, grant)), current_table}

      index = parse_index(line) ->
        {Map.update!(inventory, :indexes, &MapSet.put(&1, index)), current_table}

      constraint =
          capture(
            line,
            ~r/^ALTER TABLE ONLY (?<table>\S+) ADD CONSTRAINT (?<name>\S+) (?<definition>.+);/
          ) ->
        {parse_constraint(line, constraint, inventory), current_table}

      true ->
        {inventory, current_table}
    end
  end

  defp parse_alter_table_line(line, table, inventory) do
    case Regex.named_captures(~r/^\s+ADD CONSTRAINT (?<name>\S+) (?<definition>.+);/, line) do
      %{"name" => name, "definition" => definition} ->
        parse_constraint(table, trim_identifier(name), definition, inventory)

      nil ->
        inventory
    end
  end

  defp parse_alter_column_default(line) do
    case Regex.named_captures(
           ~r/^ALTER TABLE ONLY (?<table>\S+) ALTER COLUMN (?<column>\S+) SET DEFAULT (?<default>.+);$/,
           line
         ) do
      %{"table" => table, "column" => column, "default" => default} ->
        {normalize_identity(table), trim_identifier(column), normalize_definition(default)}

      nil ->
        nil
    end
  end

  defp put_column_default(inventory, {table, column, default}) do
    Map.update!(inventory, :columns, fn columns ->
      case Enum.find(columns, fn
             {^table, ^column, _definition} -> true
             _column -> false
           end) do
        {^table, ^column, definition} = existing ->
          columns
          |> MapSet.delete(existing)
          |> MapSet.put({table, column, insert_column_default(definition, default)})

        nil ->
          MapSet.put(columns, {table, column, "DEFAULT #{default}"})
      end
    end)
  end

  defp insert_column_default(definition, default) do
    if String.ends_with?(definition, " NOT NULL") do
      base = String.trim_trailing(definition, " NOT NULL")
      "#{base} DEFAULT #{default} NOT NULL"
    else
      "#{definition} DEFAULT #{default}"
    end
  end

  defp parse_table_column(line, table, inventory) do
    case Regex.named_captures(
           ~r/^\s{4}(?<name>"[^"]+"|[A-Za-z_][\w$]*)\s+(?<definition>.+?)(?:,)?$/,
           line
         ) do
      %{"name" => "CONSTRAINT"} ->
        inventory

      %{"name" => name, "definition" => definition} ->
        column = {table, trim_identifier(name), normalize_definition(definition)}
        Map.update!(inventory, :columns, &MapSet.put(&1, column))

      nil ->
        inventory
    end
  end

  defp parse_constraint(line, _constraint, inventory) do
    %{"table" => table, "name" => name, "definition" => definition} =
      Regex.named_captures(
        ~r/^ALTER TABLE ONLY (?<table>\S+) ADD CONSTRAINT (?<name>\S+) (?<definition>.+);/,
        line
      )

    table = normalize_identity(table)
    name = trim_identifier(name)

    parse_constraint(table, name, definition, inventory)
  end

  defp parse_constraint(table, name, definition, inventory) do
    definition = normalize_definition(definition)

    inventory = Map.update!(inventory, :constraints, &MapSet.put(&1, {table, name, definition}))

    inventory =
      if String.starts_with?(definition, "PRIMARY KEY") do
        Map.update!(inventory, :primary_keys, &MapSet.put(&1, {table, name}))
      else
        inventory
      end

    case Regex.named_captures(
           ~r/FOREIGN KEY \((?<source>[^\)]+)\) REFERENCES (?<destination>[^\(]+)\((?<destination_attribute>[^\)]+)\)/,
           definition
         ) do
      %{
        "source" => source_attribute,
        "destination" => destination_table,
        "destination_attribute" => destination_attribute
      } ->
        foreign_key =
          {table, trim_identifier(source_attribute), normalize_identity(destination_table),
           trim_identifier(destination_attribute)}

        Map.update!(inventory, :foreign_keys, &MapSet.put(&1, foreign_key))

      nil ->
        inventory
    end
  end

  defp expected_resource_map do
    :office_graph
    |> Application.fetch_env!(:ash_domains)
    |> Enum.flat_map(fn domain ->
      domain
      |> Ash.Domain.Info.resources()
      |> Enum.map(&{domain, &1})
    end)
    |> Enum.filter(fn {_domain, resource} -> migration_authoritative?(resource) end)
    |> Map.new(fn {domain, resource} ->
      {resource_table_identity(resource), {domain, resource}}
    end)
  end

  defp matching_belongs_to?(
         source,
         destination,
         destination_table,
         source_columns,
         destination_columns
       ) do
    same_arity? = length(source_columns) == length(destination_columns)
    actual_pairs = Enum.zip(source_columns, destination_columns) |> Enum.sort()

    same_arity? and
      Enum.any?(Ash.Resource.Info.relationships(source), fn
        %Ash.Resource.Relationships.BelongsTo{} = relationship ->
          relationship.destination == destination and
            relationship_destination_identity(relationship) == destination_table and
            relationship_column_pairs(source, relationship) == actual_pairs

        _other ->
          false
      end)
  end

  defp relationship_column_pairs(source, relationship) do
    source_attribute = Ash.Resource.Info.attribute(source, relationship.source_attribute)

    destination_attribute =
      Ash.Resource.Info.attribute(relationship.destination, relationship.destination_attribute)

    reference = AshPostgres.DataLayer.Info.reference(source, relationship.name)
    base_pair = {attribute_column(source_attribute), attribute_column(destination_attribute)}

    matched_pairs =
      ((reference && reference.match_with) || %{})
      |> Enum.map(fn {source_name, destination_name} ->
        {
          source |> Ash.Resource.Info.attribute(source_name) |> attribute_column(),
          relationship.destination
          |> Ash.Resource.Info.attribute(destination_name)
          |> attribute_column()
        }
      end)

    Enum.sort([base_pair | matched_pairs])
  end

  defp foreign_key_relationship_error(
         source_table,
         source_attribute,
         destination_table,
         destination_attribute
       ) do
    [
      "#{source_table}.#{source_attribute} references #{destination_table}.#{destination_attribute} without a matching belongs_to"
    ]
  end

  defp relationship_destination_identity(relationship) do
    schema_table_identity(
      relationship.context[:data_layer][:table] ||
        AshPostgres.DataLayer.Info.table(relationship.destination),
      relationship.context[:data_layer][:schema] ||
        AshPostgres.DataLayer.Info.schema(relationship.destination)
    )
  end

  defp attribute_column(nil), do: nil
  defp attribute_column(attribute), do: to_string(attribute.source || attribute.name)

  defp identifier_list(attributes) do
    attributes
    |> String.split(",", trim: true)
    |> Enum.map(&trim_identifier/1)
  end

  defp table_shape_errors(inventory, expected_resources, project_tables) do
    expected_shape = expected_table_shape(expected_resources)
    actual_columns = project_definitions(inventory.columns, project_tables)
    expected_columns = definition_map(expected_shape.columns)
    actual_column_keys = actual_columns |> Map.keys() |> MapSet.new()
    expected_column_keys = expected_columns |> Map.keys() |> MapSet.new()

    unexpected_columns =
      actual_column_keys
      |> MapSet.difference(expected_column_keys)
      |> Enum.map(fn {table, column} -> "unexpected project column #{table}.#{column}" end)

    missing_columns =
      expected_column_keys
      |> MapSet.difference(actual_column_keys)
      |> Enum.map(fn {table, column} -> "missing Ash-owned column #{table}.#{column}" end)

    mismatched_columns =
      definition_mismatches(expected_columns, actual_columns, fn {table, column},
                                                                 expected,
                                                                 actual ->
        "column definition mismatch for #{table}.#{column}: expected #{expected}, got #{actual}"
      end)

    actual_primary_keys =
      inventory.primary_keys
      |> Enum.filter(fn {table, _name} -> MapSet.member?(project_tables, table) end)
      |> MapSet.new()

    missing_primary_keys =
      expected_shape.primary_keys
      |> MapSet.difference(actual_primary_keys)
      |> Enum.map(fn {table, name} -> "missing Ash-owned primary key #{table}.#{name}" end)

    unexpected_primary_keys =
      actual_primary_keys
      |> MapSet.difference(expected_shape.primary_keys)
      |> Enum.map(fn {table, name} -> "unexpected project primary key #{table}.#{name}" end)

    actual_constraints = project_definitions(inventory.constraints, project_tables)
    expected_constraints = definition_map(expected_shape.constraints)
    actual_constraint_keys = actual_constraints |> Map.keys() |> MapSet.new()
    expected_constraint_keys = expected_constraints |> Map.keys() |> MapSet.new()

    missing_constraints =
      expected_constraint_keys
      |> MapSet.difference(actual_constraint_keys)
      |> Enum.map(fn {table, name} -> "missing Ash-owned constraint #{table}.#{name}" end)

    unexpected_constraints =
      actual_constraint_keys
      |> MapSet.difference(expected_constraint_keys)
      |> Enum.map(fn {table, name} -> "unexpected project constraint #{table}.#{name}" end)

    mismatched_constraints =
      definition_mismatches(
        expected_constraints,
        actual_constraints,
        fn {table, name}, expected, actual ->
          "constraint definition mismatch for #{name} ON #{table}: expected #{expected}, got #{actual}"
        end
      )

    actual_indexes = project_definitions(inventory.indexes, project_tables)
    expected_indexes = definition_map(expected_shape.indexes)
    actual_index_keys = actual_indexes |> Map.keys() |> MapSet.new()
    expected_index_keys = expected_indexes |> Map.keys() |> MapSet.new()

    missing_indexes =
      expected_index_keys
      |> MapSet.difference(actual_index_keys)
      |> Enum.map(fn {table, name} -> "missing Ash-owned index #{name} ON #{table}" end)

    unexpected_indexes =
      actual_index_keys
      |> MapSet.difference(expected_index_keys)
      |> Enum.map(fn {table, name} -> "unexpected project index #{name} ON #{table}" end)

    mismatched_indexes =
      definition_mismatches(expected_indexes, actual_indexes, fn {table, name},
                                                                 expected,
                                                                 actual ->
        "index definition mismatch for #{name} ON #{table}: expected #{expected}, got #{actual}"
      end)

    missing_columns ++
      unexpected_columns ++
      mismatched_columns ++
      missing_primary_keys ++
      unexpected_primary_keys ++
      missing_constraints ++
      unexpected_constraints ++
      mismatched_constraints ++
      missing_indexes ++ unexpected_indexes ++ mismatched_indexes
  end

  defp project_definitions(definitions, project_tables) do
    definitions
    |> Enum.filter(fn {table, _name, _definition} -> MapSet.member?(project_tables, table) end)
    |> definition_map()
  end

  defp definition_map(definitions) do
    Map.new(definitions, fn {table, name, definition} -> {{table, name}, definition} end)
  end

  defp definition_mismatches(expected, actual, message) do
    expected
    |> Map.keys()
    |> MapSet.new()
    |> MapSet.intersection(actual |> Map.keys() |> MapSet.new())
    |> Enum.flat_map(fn key ->
      expected_definition = Map.fetch!(expected, key)
      actual_definition = Map.fetch!(actual, key)

      if expected_definition == actual_definition do
        []
      else
        [message.(key, expected_definition, actual_definition)]
      end
    end)
  end

  defp expected_table_shape(expected_resources) do
    expected_resources
    |> Enum.reduce(
      %{
        columns: MapSet.new(),
        constraints: MapSet.new(),
        indexes: MapSet.new(),
        primary_keys: MapSet.new()
      },
      fn {_table, {_domain, resource}}, shape ->
        table = resource_table_identity(resource)

        shape
        |> Map.update!(:columns, &MapSet.union(&1, expected_columns(table, resource)))
        |> Map.update!(:primary_keys, &MapSet.union(&1, expected_primary_keys(table, resource)))
        |> Map.update!(:constraints, &MapSet.union(&1, expected_constraints(table, resource)))
        |> Map.update!(:indexes, &MapSet.union(&1, expected_indexes(table, resource)))
      end
    )
  end

  defp expected_columns(table, resource) do
    resource
    |> migrated_attributes()
    |> Enum.map(fn attribute ->
      {table, to_string(attribute.source || attribute.name),
       expected_column_definition(resource, attribute)}
    end)
    |> MapSet.new()
  end

  defp expected_sequences(expected_resources) do
    expected_resources
    |> Enum.flat_map(fn {_table, {_domain, resource}} ->
      table = resource_table_identity(resource)

      resource
      |> migrated_attributes()
      |> Enum.filter(fn attribute ->
        type = expected_migration_type(resource, attribute)
        default = raw_expected_default(resource, attribute, type)

        sequence_backed_generated?(attribute, type, default)
      end)
      |> Enum.map(&sequence_identity(table, &1))
    end)
    |> MapSet.new()
  end

  defp migrated_attributes(resource) do
    ignored = AshPostgres.DataLayer.Info.migration_ignore_attributes(resource) || []

    resource
    |> Ash.Resource.Info.attributes()
    |> Enum.reject(&(&1.name in ignored))
  end

  defp expected_column_definition(resource, attribute) do
    type = expected_migration_type(resource, attribute)

    [
      postgres_type(type),
      expected_default(resource, attribute, type),
      if(attribute.allow_nil?, do: nil, else: "NOT NULL")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> normalize_definition()
  end

  defp expected_migration_type(resource, attribute) do
    type =
      AshPostgres.DataLayer.Info.migration_types(resource)[attribute.name] ||
        AshPostgres.MigrationGenerator.get_migration_type(attribute.type, attribute.constraints)

    repo = AshPostgres.DataLayer.Info.repo(resource, :mutate)

    if function_exported?(repo, :override_migration_type, 1) do
      repo.override_migration_type(type)
    else
      type
    end
  end

  defp postgres_type({:array, type}), do: "#{postgres_type(type)}[]"
  defp postgres_type({:varchar, size}), do: "character varying(#{size})"
  defp postgres_type({:binary, size}), do: "bit varying(#{size})"
  defp postgres_type({:decimal, precision, scale}), do: "numeric(#{precision},#{scale})"
  defp postgres_type({:decimal, precision}), do: "numeric(#{precision})"
  defp postgres_type(:binary), do: "bytea"
  defp postgres_type(:bigint), do: "bigint"
  defp postgres_type(:boolean), do: "boolean"
  defp postgres_type(:citext), do: "citext"
  defp postgres_type(:date), do: "date"
  defp postgres_type(:decimal), do: "numeric"
  defp postgres_type(:float), do: "double precision"
  defp postgres_type(:integer), do: "integer"
  defp postgres_type(:jsonb), do: "jsonb"
  defp postgres_type(:map), do: "jsonb"
  defp postgres_type(:naive_datetime), do: "timestamp without time zone"
  defp postgres_type(:naive_datetime_usec), do: "timestamp without time zone"
  defp postgres_type(:string), do: "text"
  defp postgres_type(:text), do: "text"
  defp postgres_type(:time), do: "time without time zone"
  defp postgres_type(:time_usec), do: "time without time zone"
  defp postgres_type(:utc_datetime), do: "timestamp without time zone"
  defp postgres_type(:utc_datetime_usec), do: "timestamp without time zone"
  defp postgres_type(:uuid), do: "uuid"
  defp postgres_type(type), do: "unsupported(#{inspect(type)})"

  defp expected_default(resource, attribute, type) do
    default = raw_expected_default(resource, attribute, type)

    default =
      if sequence_backed_generated?(attribute, type, default) do
        table = resource_table_identity(resource)
        "nextval('#{sequence_identity(table, attribute)}'::regclass)"
      else
        default
      end

    case default do
      nil -> nil
      default -> "DEFAULT #{default}"
    end
  end

  defp raw_expected_default(resource, attribute, type) do
    case configured_migration_default(resource, attribute.name) do
      {:ok, default} -> format_configured_default(default)
      :error -> format_resource_default(resource, attribute, type)
    end
  end

  defp sequence_backed_generated?(attribute, type, default),
    do: attribute.generated? and type in [:bigint, :integer] and is_nil(default)

  defp configured_migration_default(resource, attribute) do
    defaults = AshPostgres.DataLayer.Info.migration_defaults(resource) || []

    if is_map(defaults) do
      Map.fetch(defaults, attribute)
    else
      Keyword.fetch(defaults, attribute)
    end
  end

  defp format_configured_default("nil"), do: nil

  defp format_configured_default(default) when is_binary(default) do
    case Regex.run(~r/^fragment\("(.*)"\)$/, default, capture: :all_but_first) do
      [sql] -> sql
      nil -> default
    end
  end

  defp format_configured_default(default), do: to_string(default)

  defp format_resource_default(resource, %{generated?: true}, :uuid) do
    repo = AshPostgres.DataLayer.Info.repo(resource, :mutate)

    if repo.use_builtin_uuidv7_function?(), do: "uuidv7()", else: "uuid_generate_v7()"
  end

  defp format_resource_default(_resource, %{default: default}, _type)
       when is_nil(default) or is_function(default),
       do: nil

  defp format_resource_default(_resource, %{default: []}, type),
    do: "ARRAY[]::#{postgres_type(type)}"

  defp format_resource_default(_resource, %{default: default}, type) when is_binary(default),
    do: "'#{String.replace(default, "'", "''")}'::#{postgres_type(type)}"

  defp format_resource_default(_resource, %{default: default}, _type)
       when is_boolean(default) or is_integer(default) or is_float(default),
       do: to_string(default)

  defp format_resource_default(_resource, %{default: default}, type) when is_atom(default),
    do: "'#{default}'::#{postgres_type(type)}"

  defp format_resource_default(_resource, _attribute, _type), do: nil

  defp expected_primary_keys(table, resource) do
    resource
    |> Ash.Resource.Info.attributes()
    |> Enum.filter(& &1.primary_key?)
    |> case do
      [] -> MapSet.new()
      _attributes -> MapSet.new([{table, postgres_identifier("#{table_name(table)}_pkey")}])
    end
  end

  defp expected_constraints(table, resource) do
    MapSet.union(
      expected_primary_key_constraints(table, resource),
      MapSet.union(
        expected_foreign_key_constraints(table, resource),
        expected_check_constraints(table, resource)
      )
    )
  end

  defp expected_primary_key_constraints(table, resource) do
    attributes =
      resource
      |> Ash.Resource.Info.attributes()
      |> Enum.filter(& &1.primary_key?)

    case attributes do
      [] ->
        MapSet.new()

      attributes ->
        name = postgres_identifier("#{table_name(table)}_pkey")
        fields = Enum.map_join(attributes, ", ", &to_string(&1.source || &1.name))
        MapSet.new([{table, name, "PRIMARY KEY (#{fields})"}])
    end
  end

  defp expected_foreign_key_constraints(table, resource) do
    resource
    |> Ash.Resource.Info.relationships()
    |> Enum.filter(&match?(%Ash.Resource.Relationships.BelongsTo{}, &1))
    |> Enum.flat_map(fn relationship ->
      with false <- ignored_reference?(resource, relationship),
           %Ash.Resource.Attribute{} = source_attribute <-
             Ash.Resource.Info.attribute(resource, relationship.source_attribute) do
        name = reference_name(table, source_attribute, resource, relationship)
        definition = expected_reference_definition(resource, relationship)
        [{table, name, definition}]
      else
        _value -> []
      end
    end)
    |> MapSet.new()
  end

  defp expected_check_constraints(table, resource) do
    resource
    |> AshPostgres.DataLayer.Info.check_constraints()
    |> Enum.filter(& &1.check)
    |> Enum.map(fn constraint ->
      {table, postgres_identifier(constraint.name),
       normalize_definition("CHECK (#{constraint.check})")}
    end)
    |> MapSet.new()
  end

  defp expected_reference_definition(resource, relationship) do
    source_attribute = Ash.Resource.Info.attribute(resource, relationship.source_attribute)

    destination_attribute =
      Ash.Resource.Info.attribute(relationship.destination, relationship.destination_attribute)

    reference = AshPostgres.DataLayer.Info.reference(resource, relationship.name)
    source = to_string(source_attribute.source || source_attribute.name)
    destination = to_string(destination_attribute.source || destination_attribute.name)

    {matched_sources, matched_destinations} =
      ((reference && reference.match_with) || %{})
      |> Enum.map(fn {source_name, destination_name} ->
        {
          resource |> Ash.Resource.Info.attribute(source_name) |> attribute_column(),
          relationship.destination
          |> Ash.Resource.Info.attribute(destination_name)
          |> attribute_column()
        }
      end)
      |> Enum.unzip()

    sources = [source | matched_sources]
    destinations = [destination | matched_destinations]

    destination_table =
      schema_table_identity(
        relationship.context[:data_layer][:table] ||
          AshPostgres.DataLayer.Info.table(relationship.destination),
        relationship.context[:data_layer][:schema] ||
          AshPostgres.DataLayer.Info.schema(relationship.destination)
      )

    [
      "FOREIGN KEY (#{Enum.join(sources, ", ")})",
      "REFERENCES #{destination_table}(#{Enum.join(destinations, ", ")})",
      reference_match_type(reference),
      reference_action("ON UPDATE", reference && reference.on_update),
      reference_action("ON DELETE", reference && reference.on_delete),
      reference_deferrability(reference)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> normalize_definition()
  end

  defp reference_match_type(%{match_type: type}) when type in [:full, :partial, :simple],
    do: "MATCH #{type |> to_string() |> String.upcase()}"

  defp reference_match_type(_reference), do: nil

  defp reference_action(prefix, action) when action in [:delete, :update],
    do: "#{prefix} CASCADE"

  defp reference_action(prefix, action) when action in [:nilify, :nilify_all],
    do: "#{prefix} SET NULL"

  defp reference_action(prefix, :restrict), do: "#{prefix} RESTRICT"
  defp reference_action(_prefix, _action), do: nil

  defp reference_deferrability(%{deferrable: :initially}),
    do: "DEFERRABLE INITIALLY DEFERRED"

  defp reference_deferrability(%{deferrable: true}), do: "DEFERRABLE"
  defp reference_deferrability(_reference), do: nil

  defp expected_indexes(table, resource) do
    MapSet.union(
      expected_identity_indexes(table, resource),
      MapSet.union(
        expected_custom_indexes(table, resource),
        expected_reference_indexes(table, resource)
      )
    )
  end

  defp expected_identity_indexes(table, resource) do
    identity_index_names = AshPostgres.DataLayer.Info.identity_index_names(resource)
    skipped = AshPostgres.DataLayer.Info.skip_unique_indexes(resource)

    resource
    |> Ash.Resource.Info.identities()
    |> Enum.reject(&(&1.name in skipped))
    |> Enum.map(fn identity ->
      name = identity_index_names[identity.name] || "#{table_name(table)}_#{identity.name}_index"
      name = postgres_identifier(name)
      fields = expected_index_fields(resource, identity.keys, identity.all_tenants?)
      where = expected_identity_where(resource, identity)

      definition =
        expected_index_definition(
          true,
          :btree,
          fields,
          nil,
          where,
          identity.nils_distinct?
        )

      {table, name, definition}
    end)
    |> MapSet.new()
  end

  defp expected_custom_indexes(table, resource) do
    schema = AshPostgres.DataLayer.Info.schema(resource)

    resource
    |> AshPostgres.DataLayer.Info.custom_indexes()
    |> Enum.map(fn index ->
      table = schema_table_identity(index.table || table_name(table), index.prefix || schema)

      name =
        index.name || AshPostgres.CustomIndex.name(table_name(table), %{fields: index.fields})

      name = name |> to_string() |> postgres_identifier()
      fields = expected_index_fields(resource, index.fields, index.all_tenants?)
      include = Enum.map(index.include || [], &expected_index_field(resource, &1))
      where = expected_custom_index_where(resource, index.where)

      definition =
        expected_index_definition(
          index.unique,
          index.using || :btree,
          fields,
          include,
          where,
          index.nulls_distinct
        )

      {table, name, definition}
    end)
    |> MapSet.new()
  end

  defp expected_reference_indexes(table, resource) do
    resource
    |> Ash.Resource.Info.relationships()
    |> Enum.filter(&match?(%Ash.Resource.Relationships.BelongsTo{}, &1))
    |> Enum.flat_map(fn relationship ->
      with false <- ignored_reference?(resource, relationship),
           true <- reference_index?(resource, relationship),
           %Ash.Resource.Attribute{} = source_attribute <-
             Ash.Resource.Info.attribute(resource, relationship.source_attribute) do
        source = to_string(source_attribute.source || source_attribute.name)
        name = postgres_identifier("#{table_name(table)}_#{source}_index")
        fields = expected_index_fields(resource, [source], false)
        [{table, name, expected_index_definition(false, :btree, fields, nil, nil, true)}]
      else
        _value -> []
      end
    end)
    |> MapSet.new()
  end

  defp expected_index_fields(resource, fields, all_tenants?) do
    fields = Enum.map(fields, &expected_index_field(resource, &1))

    case Ash.Resource.Info.multitenancy_strategy(resource) do
      :attribute when not all_tenants? ->
        tenant_attribute = Ash.Resource.Info.multitenancy_attribute(resource)
        Enum.uniq([expected_index_field(resource, tenant_attribute) | fields])

      _strategy ->
        fields
    end
  end

  defp expected_index_field(resource, field) when is_atom(field) do
    case Ash.Resource.Info.attribute(resource, field) do
      nil -> to_string(field)
      attribute -> to_string(attribute.source || attribute.name)
    end
  end

  defp expected_index_field(_resource, field), do: normalize_definition(to_string(field))

  defp expected_identity_where(resource, identity) do
    identity_where = AshPostgres.DataLayer.Info.identity_wheres_to_sql(resource)[identity.name]
    base_filter = AshPostgres.DataLayer.Info.base_filter_sql(resource)

    case {identity_where, base_filter} do
      {nil, nil} -> nil
      {where, nil} -> "(#{where})"
      {nil, base_filter} -> "(#{base_filter})"
      {where, base_filter} -> "(#{where}) AND (#{base_filter})"
    end
  end

  defp expected_custom_index_where(resource, where) do
    case {AshPostgres.DataLayer.Info.base_filter_sql(resource), where} do
      {nil, nil} -> nil
      {nil, where} -> where
      {base_filter, nil} -> base_filter
      {base_filter, where} -> base_filter <> " AND " <> where
    end
  end

  defp expected_index_definition(unique?, using, fields, include, where, nulls_distinct?) do
    [
      if(unique?, do: "UNIQUE", else: nil),
      "USING #{using}",
      "(#{Enum.join(fields, ", ")})",
      if(include in [nil, []], do: nil, else: "INCLUDE (#{Enum.join(include, ", ")})"),
      if(unique? and nulls_distinct? == false, do: "NULLS NOT DISTINCT", else: nil),
      if(where, do: "WHERE #{normalize_definition(where)}", else: nil)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp ignored_reference?(resource, relationship) do
    case AshPostgres.DataLayer.Info.reference(resource, relationship.name) do
      nil -> false
      reference -> reference.ignore?
    end
  end

  defp reference_index?(resource, relationship) do
    case AshPostgres.DataLayer.Info.reference(resource, relationship.name) do
      nil -> false
      reference -> reference.index?
    end
  end

  defp reference_name(table, source_attribute, resource, relationship) do
    case AshPostgres.DataLayer.Info.reference(resource, relationship.name) do
      %{name: name} when is_binary(name) ->
        postgres_identifier(name)

      _reference ->
        postgres_identifier(
          "#{table_name(table)}_#{source_attribute.source || source_attribute.name}_fkey"
        )
    end
  end

  defp migration_authoritative?(resource) do
    Ash.Resource.Info.data_layer(resource) == AshPostgres.DataLayer and
      AshPostgres.DataLayer.Info.migrate?(resource)
  end

  defp reject_framework_objects(objects, class) do
    objects
    |> Enum.reject(&framework_owned?(class, &1))
    |> MapSet.new()
  end

  defp reject_framework_triggers(triggers) do
    triggers
    |> Enum.reject(fn trigger ->
      trigger
      |> String.split(" ON ", parts: 2)
      |> List.last()
      |> then(&framework_owned?(:table, &1))
    end)
    |> MapSet.new()
  end

  defp framework_owned?(class, identity) when is_binary(identity),
    do: MapSet.member?(Map.get(@framework_objects, class, MapSet.new()), identity)

  defp framework_owned?(_class, _identity), do: false

  defp resource_table_identity(resource) do
    schema_table_identity(
      AshPostgres.DataLayer.Info.table(resource),
      AshPostgres.DataLayer.Info.schema(resource)
    )
  end

  defp schema_table_identity(table, schema) when schema in [nil, :public, "public"],
    do: to_string(table)

  defp schema_table_identity(table, schema) when is_atom(schema) or is_binary(schema),
    do: "#{schema}.#{table}"

  defp table_name(table) do
    table
    |> to_string()
    |> String.split(".")
    |> List.last()
  end

  defp postgres_identifier(name) do
    name
    |> to_string()
    |> String.slice(0, 63)
  end

  defp sequence_identity(table, attribute) do
    sequence =
      postgres_identifier("#{table_name(table)}_#{attribute.source || attribute.name}_seq")

    case String.split(table, ".", parts: 2) do
      [schema, _table] -> "#{schema}.#{sequence}"
      [_table] -> sequence
    end
  end

  defp normalize_trigger(name, line) do
    table = line |> capture(~r/\sON (?<identity>\S+)/) |> normalize_identity()
    "#{trim_identifier(name)} ON #{table}"
  end

  defp normalize_policy(name, line) do
    table = line |> capture(~r/\sON (?<identity>\S+)/) |> normalize_identity()
    "#{trim_identifier(name)} ON #{table}"
  end

  defp parse_index(line) do
    case Regex.named_captures(
           ~r/^CREATE (?<unique>UNIQUE )?INDEX (?<name>\S+) ON (?:ONLY )?(?<table>\S+) (?<definition>.+);$/,
           line
         ) do
      %{"name" => name, "table" => table, "definition" => definition} = captures ->
        unique = if captures["unique"] in [nil, ""], do: "", else: "UNIQUE "

        {normalize_identity(table), trim_identifier(name),
         normalize_definition(unique <> definition)}

      nil ->
        nil
    end
  end

  defp normalize_definition(definition) do
    definition
    |> String.trim()
    |> String.trim_trailing(",")
    |> String.trim_trailing(";")
    |> String.replace(~r/\bCONSTRAINT\s+\S+\s+(?=NOT NULL\b)/, "")
    |> String.replace(~r/"([A-Za-z_][\w$]*)"/, "\\1")
    |> String.replace(~r/\s+/, " ")
    |> normalize_foreign_key_definition()
    |> normalize_sequence_regclass()
  end

  defp normalize_sequence_regclass(definition) do
    Regex.replace(
      ~r/nextval\('(?<identity>[^']+)'::regclass\)/,
      definition,
      fn _match, identity -> "nextval('#{normalize_identity(identity)}'::regclass)" end
    )
  end

  defp normalize_foreign_key_definition(definition) do
    case Regex.named_captures(
           ~r/^FOREIGN KEY \((?<sources>[^\)]+)\) REFERENCES (?<table>[^\(]+)\((?<destinations>[^\)]+)\)(?<suffix>.*)$/,
           definition
         ) do
      %{
        "sources" => sources,
        "table" => table,
        "destinations" => destinations,
        "suffix" => suffix
      } ->
        pairs =
          sources
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.zip(destinations |> String.split(",") |> Enum.map(&String.trim/1))
          |> Enum.sort()

        {sources, destinations} = Enum.unzip(pairs)

        table = table |> String.trim() |> normalize_identity()

        "FOREIGN KEY (#{Enum.join(sources, ", ")}) REFERENCES #{table}(#{Enum.join(destinations, ", ")})#{suffix}"

      nil ->
        definition
    end
  end

  defp normalize_identity(identity) when is_binary(identity) do
    identity
    |> String.trim()
    |> String.trim_trailing(";")
    |> String.trim_trailing(",")
    |> String.split(".")
    |> Enum.map(&trim_identifier/1)
    |> case do
      ["public", name] -> name
      [name] -> name
      [schema, name] -> "#{schema}.#{name}"
      parts -> Enum.join(parts, ".")
    end
  end

  defp normalize_identity(nil), do: nil

  defp trim_identifier(identifier) do
    identifier
    |> String.trim()
    |> String.trim("\"")
    |> String.trim_trailing(";")
  end

  defp capture(line, regex) do
    case Regex.named_captures(regex, line) do
      %{"identity" => value} -> value
      %{"name" => value} -> value
      nil -> nil
    end
  end
end
