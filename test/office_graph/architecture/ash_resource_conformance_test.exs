defmodule OfficeGraph.Architecture.AshResourceConformanceTest do
  use OfficeGraph.TestSupport.AshConformanceSupport

  import OfficeGraph.TestSupport.MigrationConformanceSupport

  test "migration-created tables match the repo-wide Ash ownership inventory" do
    expected_tables = resource_table_identities(@expected_resources)

    duplicate_resources =
      @expected_resources
      |> Enum.group_by(fn {_table, {_domain, resource}} -> resource end, fn {table, _} ->
        table
      end)
      |> Enum.filter(fn {_resource, tables} -> length(tables) > 1 end)

    assert map_size(@expected_resources) == 89
    assert duplicate_resources == []
    assert migration_tables() == expected_tables
  end

  test "declarative migration foreign keys have concrete Ash relationships" do
    assert migration_foreign_key_relationship_errors(@expected_resources) == []
  end

  test "repo-wide Ash ownership inventory matches the OpenSpec model inventory" do
    assert expected_resource_inventory() == model_inventory_resources()
  end

  test "OpenSpec model inventory tracks accepted planned MVP resources separately" do
    assert expected_planned_resource_inventory() == planned_model_inventory_resources()
  end

  test "planned MVP inventory covers accepted software proving and rich text sets" do
    planned_map_tables = @planned_mvp_resources |> Map.keys() |> MapSet.new()
    planned_inventory_tables = planned_model_inventory_tables()

    for {label, required_tables} <- [
          {"software proving", @accepted_software_proving_planned_tables},
          {"rich text", @accepted_rich_text_planned_tables}
        ] do
      assert MapSet.subset?(required_tables, planned_map_tables),
             "Expected @planned_mvp_resources to include accepted #{label} tables:\n#{format_missing_tables(required_tables, planned_map_tables)}"

      assert MapSet.subset?(required_tables, planned_inventory_tables),
             "Expected #{@model_inventory} to include accepted #{label} tables:\n#{format_missing_tables(required_tables, planned_inventory_tables)}"
    end

    assert model_inventory_row("rich_text_quote_snapshots") =~ "quote freshness state",
           "rich_text_quote_snapshots row must explicitly own quote freshness state"
  end

  test "planned MVP inventory source references point to current files" do
    errors =
      planned_model_inventory_source_references()
      |> Enum.reject(fn {_table, source_path} -> File.exists?(source_path) end)
      |> Enum.map(fn {table, source_path} -> "#{table}: #{source_path}" end)

    assert errors == [],
           "Expected planned MVP inventory source references to point to existing files:\n#{format_errors(errors)}"
  end

  test "durable Ash resources do not use generic map attributes" do
    assert map_attribute_fields() == []
  end

  test "belongs-to relationships define ordinary source attributes" do
    errors =
      @expected_resources
      |> Enum.flat_map(fn {_table, {_domain, resource}} ->
        resource
        |> Ash.Resource.Info.relationships()
        |> Enum.filter(&match?(%Ash.Resource.Relationships.BelongsTo{}, &1))
        |> Enum.reject(& &1.define_attribute?)
        |> Enum.map(fn relationship ->
          "#{inspect(resource)}.#{relationship.name} disables its implied #{relationship.source_attribute} attribute"
        end)
      end)
      |> Enum.sort()

    assert errors == [],
           "Ordinary belongs_to relationships must own their source attributes:\n#{format_errors(errors)}"
  end

  test "non-relationship UUID identifiers are explicitly classified" do
    expected_fields =
      @intentional_non_relationship_uuid_identifiers
      |> Map.keys()
      |> MapSet.new()

    assert unmodeled_uuid_identifier_fields(@expected_resources) == expected_fields

    for {{resource, identifier}, {_classification, discriminator}} <-
          @intentional_non_relationship_uuid_identifiers do
      assert Ash.Resource.Info.attribute(resource, identifier)
      assert Ash.Resource.Info.attribute(resource, discriminator)

      refute Enum.any?(Ash.Resource.Info.relationships(resource), fn relationship ->
               match?(%Ash.Resource.Relationships.BelongsTo{}, relationship) and
                 relationship.source_attribute == identifier
             end)
    end
  end

  test "stable inverse relationships are modeled on owning resources" do
    assert_relationship_contracts!(@stable_inverse_relationships)
  end

  test "generic tombstone resources are absent from the Ash model" do
    refute Map.has_key?(@expected_resources, "tombstones")
    refute OfficeGraph.Tombstones.Domain in @ash_domains
    refute Code.ensure_loaded?(OfficeGraph.Tombstones.Tombstone)
  end

  test "primary keys are writable data-layer-generated values without application defaults" do
    errors =
      @expected_resources
      |> Enum.flat_map(fn {_table, {_domain, resource}} ->
        resource
        |> Ash.Resource.Info.primary_key()
        |> Enum.map(&Ash.Resource.Info.attribute(resource, &1))
        |> Enum.flat_map(fn attribute ->
          cond do
            attribute.type not in [Ash.Type.UUID, Ash.Type.UUIDv7] ->
              []

            Map.get(@shared_primary_key_relationships, resource) == attribute.name ->
              []

            not attribute.generated? ->
              ["#{inspect(resource)}.#{attribute.name} is not data-layer generated"]

            not attribute.writable? ->
              ["#{inspect(resource)}.#{attribute.name} does not allow explicit replay IDs"]

            not is_nil(attribute.default) ->
              [
                "#{inspect(resource)}.#{attribute.name} has application default #{inspect(attribute.default)}"
              ]

            true ->
              []
          end
        end)
      end)
      |> Enum.sort()

    assert errors == [],
           "Durable UUID primary keys must be generated by PostgreSQL:\n#{format_errors(errors)}"
  end

  test "shared extension primary keys are supplied by their parent relationships" do
    for {resource, primary_key} <- @shared_primary_key_relationships do
      attribute = Ash.Resource.Info.attribute(resource, primary_key)

      relationship =
        resource
        |> Ash.Resource.Info.relationships()
        |> Enum.find(&(&1.source_attribute == primary_key))

      assert attribute.primary_key?
      assert attribute.writable?
      refute attribute.generated?
      assert is_nil(attribute.default)
      assert match?(%Ash.Resource.Relationships.BelongsTo{}, relationship)
      assert relationship.destination_attribute == :id
    end
  end

  test "application UUID allocation is limited to pre-insert linkage and ephemeral tokens" do
    expected_allocations = %{
      "lib/office_graph/agent_runtime/workers/execution_worker.ex" =>
        {2, [:lease_token, :model_request_replay]},
      "lib/office_graph/api_support.ex" => {1, [:fixture_trace]},
      "lib/office_graph/operations.ex" => {1, [:operation_correlation]},
      "lib/office_graph/verification.ex" => {2, [:multi_record_graph_linkage]},
      "lib/office_graph/work_graph/commands/proposal_commands.ex" =>
        {6, [:multi_record_graph_linkage]},
      "lib/office_graph/work_graph/commands/system_commands.ex" =>
        {2, [:multi_record_graph_linkage]},
      "lib/office_graph/work_graph/commands/verification_commands.ex" =>
        {5, [:multi_record_graph_linkage]}
    }

    actual_allocations =
      "lib/office_graph/**/*.ex"
      |> Path.wildcard()
      |> Enum.flat_map(fn path ->
        count =
          path
          |> File.read!()
          |> then(&Regex.scan(~r/Ecto\.UUID\.generate\(\)/, &1))
          |> length()

        if count == 0, do: [], else: [{path, count}]
      end)
      |> Map.new()

    expected_counts =
      Map.new(expected_allocations, fn {path, {count, _classifications}} -> {path, count} end)

    assert actual_allocations == expected_counts

    for path <- Map.keys(actual_allocations) do
      refute File.read!(path) =~ ~r/\bid:\s*Ecto\.UUID\.generate\(\)/
    end
  end

  test "all expected Ash domains are registered in application config" do
    expected_domains = expected_domains()

    missing_domains =
      expected_domains
      |> MapSet.difference(MapSet.new(@ash_domains))
      |> MapSet.to_list()
      |> Enum.sort_by(&inspect/1)

    assert missing_domains == [],
           "Missing Ash domains in :office_graph, :ash_domains:\n#{format_modules(missing_domains)}"
  end

  test "all expected resources load with AshPostgres ownership metadata" do
    errors =
      @expected_resources
      |> Enum.sort_by(fn {table, _mapping} -> table end)
      |> Enum.flat_map(fn {table, {_domain, resource}} ->
        resource_conformance_errors(table, resource)
      end)

    assert errors == [],
           "Expected resources must be migration-authoritative AshPostgres resources with matching tables:\n#{format_errors(errors)}"
  end

  test "migration-authoritative resources use tracked current snapshots" do
    snapshot_tables =
      "priv/resource_snapshots/repo/*/*.json"
      |> Path.wildcard()
      |> Enum.map(&(&1 |> Path.dirname() |> Path.basename()))
      |> MapSet.new()

    expected_tables = @expected_resources |> Map.keys() |> MapSet.new()

    assert snapshot_tables == expected_tables,
           "Expected one current resource-snapshot directory per table.\n" <>
             "Missing: #{inspect(expected_tables |> MapSet.difference(snapshot_tables) |> Enum.sort())}\n" <>
             "Unexpected: #{inspect(snapshot_tables |> MapSet.difference(expected_tables) |> Enum.sort())}"
  end

  test "migration-authoritative identities do not require SQL predicates" do
    filtered_identities =
      @expected_resources
      |> Enum.flat_map(fn {_table, {_domain, resource}} ->
        resource
        |> Ash.Resource.Info.identities()
        |> Enum.reject(&is_nil(&1.where))
        |> Enum.map(&{resource, &1.name})
      end)
      |> Enum.sort()

    assert filtered_identities == [],
           "Filtered identities require SQL predicates; use nullable keys, nils_distinct?, or typed identity slots:\n" <>
             Enum.map_join(filtered_identities, "\n", &inspect/1)
  end

  test "each expected resource is registered in exactly one owning domain" do
    errors =
      @expected_resources
      |> Enum.sort_by(fn {table, _mapping} -> table end)
      |> Enum.flat_map(fn {table, {expected_domain, resource}} ->
        registered_domains = registered_domains_for(resource)

        if registered_domains == [expected_domain] do
          []
        else
          [
            "#{table}: #{inspect(resource)} expected only in #{inspect(expected_domain)}, got #{inspect(registered_domains)}"
          ]
        end
      end)

    assert errors == [],
           "Expected resources must be registered in exactly one owning Ash domain:\n#{format_errors(errors)}"
  end

  test "Ash resources declare expected unique identities" do
    errors =
      @expected_resource_identities
      |> Enum.sort_by(fn {resource, _identities} -> inspect(resource) end)
      |> Enum.flat_map(fn {resource, identities} ->
        Enum.flat_map(identities, fn {identity_name, expected_keys} ->
          case safe_info(fn -> Ash.Resource.Info.identity(resource, identity_name) end) do
            {:ok, nil} ->
              ["#{inspect(resource)} missing identity #{inspect(identity_name)}"]

            {:ok, identity} ->
              identity_conformance_errors(resource, identity_name, expected_keys, identity)

            {:error, error} ->
              [
                "#{inspect(resource)} identity #{inspect(identity_name)} is not readable: #{error}"
              ]
          end
        end)
      end)

    assert errors == [],
           "Ash resources must declare database-backed identities:\n#{format_errors(errors)}"
  end

  test "foundation authorization read policies do not expose cross-workspace rows" do
    refute public_action?(OfficeGraph.Authorization.RoleCapability, :read, :read),
           "RoleCapability join rows must not have public reads until they have a tenant-safe read policy"

    refute public_action?(OfficeGraph.Authorization.AuthorizationDecision, :read, :read),
           "AuthorizationDecision rows must not have public reads until operation workspace scope is Ash-backed"

    role_assignment_filter = foundation_read_filter(OfficeGraph.Authorization.RoleAssignment)
    role_assignment_filter_text = inspect(role_assignment_filter)

    for required_fragment <- [
          "principal_id == {:_actor, :principal_id}",
          "organization_id == {:_actor, :organization_id}",
          "is_nil(workspace_id)",
          "workspace_id == {:_actor, :workspace_id}"
        ] do
      assert role_assignment_filter_text =~ required_fragment,
             "RoleAssignment read filter must include #{required_fragment}, got #{role_assignment_filter_text}"
    end
  end

  test "production model code does not define manual Ecto schemas" do
    schemas = manual_ecto_schemas()

    assert schemas == [],
           "Found table-backed Ecto schemas under lib/office_graph:\n#{format_ecto_schemas(schemas)}"
  end

  test "WorkGraph no longer has parallel Resources modules" do
    parallel_modules = work_graph_resources_modules()

    assert parallel_modules == [],
           "Remove parallel WorkGraph resource modules and promote canonical modules instead:\n#{format_errors(parallel_modules)}"
  end

  test "WorkGraph canonical Ash resources expose public actions with explicit capability policies" do
    assert_work_graph_resources_are_ash!()

    for resource <- @work_graph_resources do
      for {action_name, {action_type, capability}} <-
            Map.fetch!(@expected_action_capabilities, resource) do
        assert public_action?(resource, action_name, action_type),
               "#{inspect(resource)} must expose public #{action_type} action #{inspect(action_name)}"

        assert capability_policy?(resource, action_name, action_type, capability),
               "#{inspect(resource)} #{inspect(action_name)} must authorize through #{inspect(HasCapability)} with capability #{inspect(capability)}"
      end
    end
  end

  test "WorkGraph canonical Ash read actions include actor scope filter policies" do
    assert_work_graph_resources_are_ash!()

    for resource <- @work_graph_resources do
      read_actions = actions_by_type(resource, :read)

      assert read_actions != [],
             "#{inspect(resource)} must define at least one read action"

      for action <- read_actions do
        assert scope_filter_policy?(resource, action.name, :read),
               "#{inspect(resource)} #{inspect(action.name)} must filter reads by actor organization_id and workspace_id"
      end
    end
  end

  test "proposal replay reads stay private, scoped, and apply-authorized" do
    for resource <- [
          OfficeGraph.WorkGraph.Signal,
          OfficeGraph.WorkGraph.Task,
          OfficeGraph.WorkGraph.ReviewFinding,
          OfficeGraph.WorkGraph.VerificationCheck
        ] do
      action_name = :read_for_proposed_change_replay

      refute public_action?(resource, action_name, :read),
             "#{inspect(resource)} #{inspect(action_name)} must stay private"

      assert Ash.Resource.Info.action(resource, action_name),
             "#{inspect(resource)} must define #{inspect(action_name)}"

      assert capability_policy?(resource, action_name, :read, :proposed_change_apply),
             "#{inspect(resource)} #{inspect(action_name)} must require proposed_change.apply"

      assert scope_filter_policy?(resource, action_name, :read),
             "#{inspect(resource)} #{inspect(action_name)} must retain actor scope filtering"
    end
  end

  test "work packet version command read stays private, scoped, and version-authorized" do
    resource = OfficeGraph.WorkPackets.WorkPacket
    action_name = :read_for_version_command

    refute public_action?(resource, action_name, :read)
    assert Ash.Resource.Info.action(resource, action_name)

    assert capability_policy?(
             resource,
             action_name,
             :read,
             :work_packet_version_create
           )

    assert scope_filter_policy?(resource, action_name, :read)
  end

  test "operator command target reads stay private, scoped, and command-authorized" do
    for {resource, action_name, capability} <- [
          {OfficeGraph.WorkPackets.WorkPacketVersion, :read_for_run_start_command,
           :work_run_start},
          {OfficeGraph.Runs.Run, :read_for_observation_command, :execution_observation_record},
          {OfficeGraph.WorkGraph.EvidenceCandidate, :read_for_accept_command, :evidence_accept},
          {OfficeGraph.Runs.Run, :read_for_waive_command, :verification_waive},
          {OfficeGraph.Runs.RunRequiredCheck, :read_for_waive_command, :verification_waive},
          {OfficeGraph.Runs.RunRequiredCheck, :read_for_accept_command, :evidence_accept}
        ] do
      refute public_action?(resource, action_name, :read)
      assert Ash.Resource.Info.action(resource, action_name)
      assert capability_policy?(resource, action_name, :read, capability)
      assert scope_filter_policy?(resource, action_name, :read)
    end
  end

  test "WorkGraph canonical Ash create actions validate same-scope references" do
    assert_work_graph_resources_are_ash!()

    expected_resources = @expected_reference_validations |> Map.keys() |> MapSet.new()

    assert expected_resources == MapSet.new(@work_graph_resources),
           "Expected reference validation table must cover every required resource"

    for resource <- @work_graph_resources do
      expected_by_action = Map.fetch!(@expected_reference_validations, resource)
      create_actions = actions_by_type(resource, :create)

      assert MapSet.new(Enum.map(create_actions, & &1.name)) ==
               MapSet.new(Map.keys(expected_by_action)),
             "#{inspect(resource)} must define exactly the create actions covered by the same-scope reference table"

      for action <- create_actions do
        expected_references = Map.fetch!(expected_by_action, action.name)

        assert same_scope_reference_validation(action) == expected_references,
               "#{inspect(resource)} #{inspect(action.name)} must validate same-scope references #{inspect(expected_references)}"
      end
    end
  end

  test "WorkGraph resources model safe raw UUID references as Ash relationships" do
    assert_relationship_contracts!(@expected_work_graph_relationships)
  end

  test "WorkPackets resources model safe raw UUID references as Ash relationships" do
    assert_relationship_contracts!(@expected_work_packets_relationships)
  end

  test "WorkPackets action contracts validate references through Ash changes" do
    for {resource, expected_by_action} <- @expected_work_packets_reference_validations do
      for {action_name, expected_references} <- expected_by_action do
        action = Ash.Resource.Info.action(resource, action_name)

        assert action,
               "#{inspect(resource)} must define action #{inspect(action_name)}"

        assert same_scope_reference_validation(action) == expected_references,
               "#{inspect(resource)} #{inspect(action_name)} must validate same-scope references #{inspect(expected_references)}"
      end
    end
  end

  test "WorkPacket create does not accept current version assignment" do
    create_action = Ash.Resource.Info.action(OfficeGraph.WorkPackets.WorkPacket, :create)

    refute :current_version_id in create_action.accept
  end

  test "WorkPackets lifecycle actions derive packet and version state" do
    packet_create = Ash.Resource.Info.action(OfficeGraph.WorkPackets.WorkPacket, :create)

    packet_update =
      Ash.Resource.Info.action(OfficeGraph.WorkPackets.WorkPacket, :set_current_version)

    version_create = Ash.Resource.Info.action(OfficeGraph.WorkPackets.WorkPacketVersion, :create)

    refute :state in packet_create.accept
    assert fixed_attribute_change(packet_create, :state) == "draft"

    refute :state in packet_update.accept
    assert action_change?(packet_update, OfficeGraph.WorkPackets.Changes.ValidateCurrentVersion)

    refute :lifecycle_state in version_create.accept

    assert MapSet.new(action_argument_names(version_create)) ==
             MapSet.new([:source_graph_item_ids, :verification_check_ids])

    assert action_change?(
             version_create,
             OfficeGraph.WorkPackets.Changes.DeriveVersionLifecycleState
           )
  end

  test "WorkPackets child create actions own fixed packet contract attributes" do
    for {resource, expected_defaults} <- @expected_work_packets_create_defaults do
      create_action = Ash.Resource.Info.action(resource, :create)

      assert create_action,
             "#{inspect(resource)} must define create action"

      for {attribute, expected_value} <- expected_defaults do
        refute attribute in create_action.accept,
               "#{inspect(resource)} create must not accept fixed #{inspect(attribute)} from callers"

        assert fixed_attribute_change(create_action, attribute) == expected_value,
               "#{inspect(resource)} create must set #{inspect(attribute)} to #{inspect(expected_value)}"
      end
    end
  end

  test "Runs resources model safe raw UUID references as Ash relationships" do
    assert_relationship_contracts!(@expected_runs_relationships)
  end

  test "Runs action contracts validate references through Ash changes" do
    for {resource, expected_by_action} <- @expected_runs_reference_validations do
      for {action_name, expected_references} <- expected_by_action do
        action = Ash.Resource.Info.action(resource, action_name)

        assert action,
               "#{inspect(resource)} must define action #{inspect(action_name)}"

        assert same_scope_reference_validation(action) == expected_references,
               "#{inspect(resource)} #{inspect(action_name)} must validate same-scope references #{inspect(expected_references)}"
      end
    end
  end

  test "Run create derives initial lifecycle state" do
    create_action = Ash.Resource.Info.action(OfficeGraph.Runs.Run, :create)

    for attribute <- [
          :state,
          :aggregate_state,
          :execution_state,
          :verification_state,
          :started_at,
          :completed_at
        ] do
      refute attribute in create_action.accept,
             "Run.create must not accept caller-supplied #{inspect(attribute)}"
    end

    assert action_change?(create_action, OfficeGraph.Runs.Changes.DeriveRunInitialLifecycle)
  end

  test "Run create owns run-start packet readiness and authority validation" do
    create_action = Ash.Resource.Info.action(OfficeGraph.Runs.Run, :create)

    assert action_change?(create_action, OfficeGraph.Runs.Changes.ValidateRunStartContract)
  end

  test "ExecutionObservation create derives ingestion time" do
    create_action = Ash.Resource.Info.action(OfficeGraph.Runs.ExecutionObservation, :create)

    refute :ingested_at in create_action.accept

    assert action_change?(create_action, OfficeGraph.Runs.Changes.DeriveObservationIngestedAt)
  end

  test "RunEvent create remains a private run-scoped append action" do
    create_action = Ash.Resource.Info.action(OfficeGraph.Runs.RunEvent, :create)

    refute create_action.public?
    assert :run_id in create_action.accept
  end

  test "Runs observation command delegates reference validation to Ash changes" do
    observation_create = Ash.Resource.Info.action(OfficeGraph.Runs.ExecutionObservation, :create)

    assert action_change?(
             observation_create,
             OfficeGraph.Runs.Changes.ValidateObservationRunReferences
           )
  end

  test "Verification owns accepted evidence recomputation through one Runs lifecycle hook" do
    exported_names = OfficeGraph.Runs.__info__(:functions) |> MapSet.new(&elem(&1, 0))

    assert function_exported?(OfficeGraph.Runs, :apply_accepted_verification_result, 2)

    for retired_name <- [
          :set_run_verified,
          :set_run_verified_if_all_required_checks_satisfied,
          :set_run_verification_failed,
          :mark_required_check_satisfied,
          :satisfy_required_check_and_verify_run
        ] do
      refute MapSet.member?(exported_names, retired_name)
    end
  end

  test "Runs child create actions own fixed run contract attributes" do
    for {resource, expected_defaults} <- @expected_runs_create_defaults do
      create_action = Ash.Resource.Info.action(resource, :create)

      assert create_action,
             "#{inspect(resource)} must define create action"

      for {attribute, expected_value} <- expected_defaults do
        refute attribute in create_action.accept,
               "#{inspect(resource)} create must not accept fixed #{inspect(attribute)} from callers"

        assert fixed_attribute_change(create_action, attribute) == expected_value,
               "#{inspect(resource)} create must set #{inspect(attribute)} to #{inspect(expected_value)}"
      end
    end
  end
end
