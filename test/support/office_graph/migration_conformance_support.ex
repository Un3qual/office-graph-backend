defmodule OfficeGraph.TestSupport.MigrationConformanceSupport do
  @moduledoc false

  @framework_tables MapSet.new(["oban_jobs", "schema_migrations"])
  @framework_prefixes ["oban_"]
  @allowed_extensions MapSet.new(["plpgsql"])

  def migration_tables do
    terminal_inventory().tables
    |> Enum.reject(&framework_owned?/1)
    |> Enum.sort()
  end

  def resource_table_identities(expected_resources) do
    expected_resources
    |> Enum.map(fn {table, {_domain, resource}} -> resource_table_identity(table, resource) end)
    |> Enum.sort()
  end

  def migration_foreign_key_relationship_errors(
        expected_resources,
        inventory \\ terminal_inventory()
      ) do
    resources_by_table =
      Map.new(expected_resources, fn {table, {_domain, resource}} ->
        {resource_table_identity(table, resource), resource}
      end)

    inventory.foreign_keys
    |> Enum.flat_map(fn {source_table, source_attribute, destination_table, destination_attribute} ->
      with true <- Map.has_key?(resources_by_table, source_table),
           true <- Map.has_key?(resources_by_table, destination_table),
           source <- Map.fetch!(resources_by_table, source_table),
           destination <- Map.fetch!(resources_by_table, destination_table),
           {:ok, source_attribute} <- single_existing_atom(source_attribute),
           {:ok, destination_attribute} <- single_existing_atom(destination_attribute),
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
        false -> []
        _unknown_attribute_or_table -> []
      end
    end)
    |> Enum.sort()
  end

  def terminal_database_errors(
        expected_resources \\ expected_resource_map(),
        inventory \\ terminal_inventory()
      ) do
    expected_tables = expected_resources |> resource_table_identities() |> MapSet.new()
    project_tables = inventory.tables |> reject_framework_objects() |> MapSet.new()

    missing_tables =
      expected_tables
      |> MapSet.difference(project_tables)
      |> Enum.map(&"missing Ash-owned table #{&1}")

    unexpected_tables =
      project_tables
      |> MapSet.difference(expected_tables)
      |> Enum.map(&"unexpected project table #{&1}")

    unexpected_sequences =
      inventory.sequences
      |> reject_framework_objects()
      |> Enum.map(&"unexpected project sequence #{&1}")

    prohibited_objects =
      [
        {"view", inventory.views},
        {"materialized view", inventory.materialized_views},
        {"routine", inventory.routines},
        {"trigger", reject_framework_triggers(inventory.triggers)},
        {"RLS policy", inventory.policies},
        {"grant", inventory.grants},
        {"extension", MapSet.difference(inventory.extensions, @allowed_extensions)}
      ]
      |> Enum.flat_map(fn {label, values} ->
        values
        |> Enum.sort()
        |> Enum.map(&"unexpected project #{label} #{&1}")
      end)

    (missing_tables ++
       unexpected_tables ++
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
      triggers: MapSet.new(),
      views: MapSet.new()
    }

    dump
    |> String.split("\n")
    |> Enum.reduce({initial, nil}, &parse_dump_line/2)
    |> elem(0)
    |> Map.update!(:foreign_keys, fn keys ->
      keys
      |> MapSet.to_list()
      |> Enum.sort()
    end)
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

    case System.cmd("pg_dump", args, env: env, stderr_to_stdout: true) do
      {dump, 0} -> parse_dump(dump)
      {output, status} -> dump_with_docker_or_raise!(config, output, status)
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
      table = capture(line, ~r/^CREATE TABLE (?<identity>\S+) \($/) ->
        table = normalize_identity(table)
        {Map.update!(inventory, :tables, &MapSet.put(&1, table)), {:create_table, table}}

      match?({:create_table, _table}, current_table) && String.starts_with?(line, ");") ->
        {inventory, nil}

      match?({:create_table, _table}, current_table) ->
        {:create_table, table} = current_table
        {parse_table_column(line, table, inventory), current_table}

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

      routine =
          capture(line, ~r/^CREATE (?:OR REPLACE )?(?:FUNCTION|PROCEDURE) (?<identity>[^\(]+)\(/) ->
        {Map.update!(inventory, :routines, &MapSet.put(&1, normalize_identity(routine))),
         current_table}

      trigger = capture(line, ~r/^CREATE TRIGGER (?<name>\S+) .* ON (?<table>\S+)/) ->
        {Map.update!(inventory, :triggers, &MapSet.put(&1, normalize_trigger(trigger, line))),
         current_table}

      policy = capture(line, ~r/^CREATE POLICY (?<name>\S+) ON (?<table>\S+)/) ->
        {Map.update!(inventory, :policies, &MapSet.put(&1, normalize_policy(policy, line))),
         current_table}

      extension = capture(line, ~r/^CREATE EXTENSION IF NOT EXISTS (?<name>\S+)/) ->
        {Map.update!(inventory, :extensions, &MapSet.put(&1, trim_identifier(extension))),
         current_table}

      grant = capture(line, ~r/^GRANT .+ ON .+ (?<identity>\S+) TO /) ->
        {Map.update!(inventory, :grants, &MapSet.put(&1, normalize_identity(grant))),
         current_table}

      index = capture(line, ~r/^CREATE (?:UNIQUE )?INDEX (?<name>\S+) ON (?<table>\S+) /) ->
        {Map.update!(inventory, :indexes, &MapSet.put(&1, normalize_index(index, line))),
         current_table}

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

  defp parse_table_column(line, table, inventory) do
    case Regex.named_captures(~r/^\s{4}(?<name>"[^"]+"|[A-Za-z_][\w$]*)\s+/, line) do
      %{"name" => "CONSTRAINT"} ->
        inventory

      %{"name" => name} ->
        Map.update!(inventory, :columns, &MapSet.put(&1, {table, trim_identifier(name)}))

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
    inventory =
      Map.update!(inventory, :constraints, &MapSet.put(&1, {table, name, definition}))

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
      {AshPostgres.DataLayer.Info.table(resource), {domain, resource}}
    end)
  end

  defp single_existing_atom(attributes) do
    case attributes |> String.split(",") |> Enum.map(&String.trim/1) do
      [attribute] ->
        {:ok, String.to_existing_atom(attribute)}

      _composite ->
        :composite
    end
  rescue
    ArgumentError -> :unknown
  end

  defp table_shape_errors(inventory, expected_resources, project_tables) do
    expected_shape = expected_table_shape(expected_resources)

    unexpected_columns =
      inventory.columns
      |> MapSet.difference(expected_shape.columns)
      |> Enum.filter(fn {table, _column} -> MapSet.member?(project_tables, table) end)
      |> Enum.map(fn {table, column} -> "unexpected project column #{table}.#{column}" end)

    missing_columns =
      expected_shape.columns
      |> MapSet.difference(inventory.columns)
      |> Enum.map(fn {table, column} -> "missing Ash-owned column #{table}.#{column}" end)

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

    actual_constraints =
      inventory.constraints
      |> Enum.map(fn {table, name, _definition} -> {table, name} end)
      |> Enum.filter(fn {table, _name} -> MapSet.member?(project_tables, table) end)
      |> MapSet.new()

    missing_constraints =
      expected_shape.constraints
      |> MapSet.difference(actual_constraints)
      |> Enum.map(fn {table, name} -> "missing Ash-owned constraint #{table}.#{name}" end)

    unexpected_constraints =
      actual_constraints
      |> MapSet.difference(expected_shape.constraints)
      |> Enum.map(fn {table, name} -> "unexpected project constraint #{table}.#{name}" end)

    actual_indexes =
      inventory.indexes
      |> Enum.map(&index_tuple/1)
      |> Enum.filter(fn {table, _name, _identity} -> MapSet.member?(project_tables, table) end)
      |> MapSet.new()

    missing_indexes =
      expected_shape.indexes
      |> MapSet.difference(actual_indexes)
      |> Enum.map(fn {_table, _name, identity} -> "missing Ash-owned index #{identity}" end)

    unexpected_indexes =
      actual_indexes
      |> MapSet.difference(expected_shape.indexes)
      |> Enum.map(fn {_table, _name, identity} -> "unexpected project index #{identity}" end)

    missing_columns ++
      unexpected_columns ++
      missing_primary_keys ++
      unexpected_primary_keys ++
      missing_constraints ++
      unexpected_constraints ++
      missing_indexes ++ unexpected_indexes
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
      fn {table, {_domain, resource}}, shape ->
        table = resource_table_identity(table, resource)

        shape
        |> Map.update!(:columns, &MapSet.union(&1, expected_columns(table, resource)))
        |> Map.update!(:primary_keys, &MapSet.union(&1, expected_primary_keys(table, resource)))
        |> Map.update!(:constraints, &MapSet.union(&1, expected_constraints(table, resource)))
        |> Map.update!(:indexes, &MapSet.union(&1, expected_indexes(table, resource)))
      end
    )
  end

  defp expected_columns(table, resource) do
    ignored = AshPostgres.DataLayer.Info.migration_ignore_attributes(resource) || []

    resource
    |> Ash.Resource.Info.attributes()
    |> Enum.reject(&(&1.name in ignored))
    |> Enum.map(&{table, to_string(&1.source || &1.name)})
    |> MapSet.new()
  end

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
      expected_primary_keys(table, resource),
      MapSet.union(
        expected_foreign_key_constraints(table, resource),
        expected_check_constraints(table, resource)
      )
    )
  end

  defp expected_foreign_key_constraints(table, resource) do
    resource
    |> Ash.Resource.Info.relationships()
    |> Enum.filter(&match?(%Ash.Resource.Relationships.BelongsTo{}, &1))
    |> Enum.flat_map(fn relationship ->
      with false <- ignored_reference?(resource, relationship),
           %Ash.Resource.Attribute{} = source_attribute <-
             Ash.Resource.Info.attribute(resource, relationship.source_attribute) do
        [{table, reference_name(table, source_attribute, resource, relationship)}]
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
    |> Enum.map(&{table, postgres_identifier(&1.name)})
    |> MapSet.new()
  end

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
      {table, name, "#{name} ON #{table}"}
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
      {table, name, "#{name} ON #{table}"}
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
        [{table, name, "#{name} ON #{table}"}]
      else
        _value -> []
      end
    end)
    |> MapSet.new()
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

  defp reject_framework_objects(objects) do
    objects
    |> Enum.reject(&framework_owned?/1)
    |> MapSet.new()
  end

  defp reject_framework_triggers(triggers) do
    triggers
    |> Enum.reject(fn trigger ->
      trigger
      |> String.split(" ON ", parts: 2)
      |> List.last()
      |> framework_owned?()
    end)
    |> MapSet.new()
  end

  defp framework_owned?(identity) when is_binary(identity) do
    MapSet.member?(@framework_tables, identity) or
      Enum.any?(@framework_prefixes, &String.starts_with?(identity, &1))
  end

  defp framework_owned?(_identity), do: false

  defp resource_table_identity(table, resource),
    do: schema_table_identity(table, AshPostgres.DataLayer.Info.schema(resource))

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

  defp normalize_trigger(name, line) do
    table = line |> capture(~r/\sON (?<identity>\S+)/) |> normalize_identity()
    "#{trim_identifier(name)} ON #{table}"
  end

  defp normalize_policy(name, line) do
    table = line |> capture(~r/\sON (?<identity>\S+)/) |> normalize_identity()
    "#{trim_identifier(name)} ON #{table}"
  end

  defp normalize_index(name, line) do
    table = line |> capture(~r/\sON (?<identity>\S+)/) |> normalize_identity()
    "#{trim_identifier(name)} ON #{table}"
  end

  defp index_tuple(identity) do
    [name, table] = String.split(identity, " ON ", parts: 2)
    {table, name, identity}
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
