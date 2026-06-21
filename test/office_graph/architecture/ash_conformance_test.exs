defmodule OfficeGraph.Architecture.AshConformanceTest do
  use ExUnit.Case, async: true

  alias OfficeGraph.Authorization.Checks.HasCapability
  alias OfficeGraph.Identity.SessionContext
  alias OfficeGraph.WorkGraph.Changes.ValidateSameScopeReferences

  @ash_domains Application.compile_env(:office_graph, :ash_domains, [])
  @architecture_exception_ledger "openspec/changes/first-backend-walking-skeleton/architecture-exceptions.md"
  @implementation_summary "openspec/changes/first-backend-walking-skeleton/implementation-summary.md"

  @expected_resources %{
    "organizations" => {OfficeGraph.Tenancy.Domain, OfficeGraph.Tenancy.Organization},
    "workspaces" => {OfficeGraph.Tenancy.Domain, OfficeGraph.Tenancy.Workspace},
    "initiatives" => {OfficeGraph.Tenancy.Domain, OfficeGraph.Tenancy.Initiative},
    "workstreams" => {OfficeGraph.Tenancy.Domain, OfficeGraph.Tenancy.Workstream},
    "principals" => {OfficeGraph.Identity.Domain, OfficeGraph.Identity.Principal},
    "principal_profiles" => {OfficeGraph.Identity.Domain, OfficeGraph.Identity.PrincipalProfile},
    "credentials" => {OfficeGraph.Identity.Domain, OfficeGraph.Identity.Credential},
    "sessions" => {OfficeGraph.Identity.Domain, OfficeGraph.Identity.Session},
    "capabilities" => {OfficeGraph.Authorization.Domain, OfficeGraph.Authorization.Capability},
    "roles" => {OfficeGraph.Authorization.Domain, OfficeGraph.Authorization.Role},
    "role_capabilities" =>
      {OfficeGraph.Authorization.Domain, OfficeGraph.Authorization.RoleCapability},
    "role_assignments" =>
      {OfficeGraph.Authorization.Domain, OfficeGraph.Authorization.RoleAssignment},
    "policy_bundles" =>
      {OfficeGraph.Authorization.Domain, OfficeGraph.Authorization.PolicyBundle},
    "authorization_decisions" =>
      {OfficeGraph.Authorization.Domain, OfficeGraph.Authorization.AuthorizationDecision},
    "operation_correlations" =>
      {OfficeGraph.Operations.Domain, OfficeGraph.Operations.OperationCorrelation},
    "audit_records" => {OfficeGraph.Audit.Domain, OfficeGraph.Audit.AuditRecord},
    "revisions" => {OfficeGraph.Revisions.Domain, OfficeGraph.Revisions.Revision},
    "tombstones" => {OfficeGraph.Tombstones.Domain, OfficeGraph.Tombstones.Tombstone},
    "documents" => {OfficeGraph.Content.Domain, OfficeGraph.Content.Document},
    "document_blocks" => {OfficeGraph.Content.Domain, OfficeGraph.Content.DocumentBlock},
    "document_marks" => {OfficeGraph.Content.Domain, OfficeGraph.Content.DocumentMark},
    "document_references" => {OfficeGraph.Content.Domain, OfficeGraph.Content.DocumentReference},
    "document_revisions" => {OfficeGraph.Content.Domain, OfficeGraph.Content.DocumentRevision},
    "external_sources" =>
      {OfficeGraph.Integrations.Domain, OfficeGraph.Integrations.ExternalSource},
    "raw_archives" => {OfficeGraph.Integrations.Domain, OfficeGraph.Integrations.RawArchive},
    "normalized_intake_events" =>
      {OfficeGraph.Integrations.Domain, OfficeGraph.Integrations.NormalizedIntakeEvent},
    "external_references" =>
      {OfficeGraph.ExternalRefs.Domain, OfficeGraph.ExternalRefs.ExternalReference},
    "graph_items" => {OfficeGraph.WorkGraph.Domain, OfficeGraph.WorkGraph.GraphItem},
    "graph_relationships" =>
      {OfficeGraph.WorkGraph.Domain, OfficeGraph.WorkGraph.GraphRelationship},
    "signals" => {OfficeGraph.WorkGraph.Domain, OfficeGraph.WorkGraph.Signal},
    "tasks" => {OfficeGraph.WorkGraph.Domain, OfficeGraph.WorkGraph.Task},
    "review_findings" => {OfficeGraph.WorkGraph.Domain, OfficeGraph.WorkGraph.ReviewFinding},
    "verification_checks" =>
      {OfficeGraph.WorkGraph.Domain, OfficeGraph.WorkGraph.VerificationCheck},
    "artifacts" => {OfficeGraph.WorkGraph.Domain, OfficeGraph.WorkGraph.Artifact},
    "evidence_items" => {OfficeGraph.WorkGraph.Domain, OfficeGraph.WorkGraph.EvidenceItem},
    "verification_results" =>
      {OfficeGraph.WorkGraph.Domain, OfficeGraph.WorkGraph.VerificationResult},
    "work_packets" => {OfficeGraph.WorkPackets.Domain, OfficeGraph.WorkPackets.WorkPacket},
    "runs" => {OfficeGraph.Runs.Domain, OfficeGraph.Runs.Run},
    "run_events" => {OfficeGraph.Runs.Domain, OfficeGraph.Runs.RunEvent},
    "proposed_graph_changes" =>
      {OfficeGraph.ProposedChanges.Domain, OfficeGraph.ProposedChanges.ProposedGraphChange}
  }

  @work_graph_resources [
    OfficeGraph.WorkGraph.Signal,
    OfficeGraph.WorkGraph.Task,
    OfficeGraph.WorkGraph.ReviewFinding,
    OfficeGraph.WorkGraph.VerificationCheck,
    OfficeGraph.WorkGraph.Artifact,
    OfficeGraph.WorkGraph.EvidenceItem,
    OfficeGraph.WorkGraph.VerificationResult
  ]

  @expected_action_capabilities %{
    OfficeGraph.WorkGraph.Signal => %{
      read: {:read, :skeleton_read},
      create: {:create, :manual_intake_submit}
    },
    OfficeGraph.WorkGraph.Task => %{
      read: {:read, :skeleton_read},
      create: {:create, :proposed_change_apply},
      mark_verified_complete: {:update, :verification_complete}
    },
    OfficeGraph.WorkGraph.ReviewFinding => %{
      read: {:read, :skeleton_read},
      create: {:create, :proposed_change_apply},
      mark_verified_complete: {:update, :verification_complete}
    },
    OfficeGraph.WorkGraph.VerificationCheck => %{
      read: {:read, :skeleton_read},
      create: {:create, :proposed_change_apply},
      mark_satisfied: {:update, :verification_complete}
    },
    OfficeGraph.WorkGraph.Artifact => %{
      read: {:read, :skeleton_read},
      create: {:create, :evidence_link}
    },
    OfficeGraph.WorkGraph.EvidenceItem => %{
      read: {:read, :skeleton_read},
      create: {:create, :evidence_link}
    },
    OfficeGraph.WorkGraph.VerificationResult => %{
      read: {:read, :skeleton_read},
      create: {:create, :verification_complete}
    }
  }

  @expected_reference_validations %{
    OfficeGraph.WorkGraph.Signal => %{
      create: [
        graph_item_id:
          {OfficeGraph.WorkGraph.GraphItem, resource_type: "signal", resource_id: :id},
        body_document_id: OfficeGraph.Content.Document
      ]
    },
    OfficeGraph.WorkGraph.Task => %{
      create: [
        graph_item_id: {OfficeGraph.WorkGraph.GraphItem, resource_type: "task", resource_id: :id},
        source_signal_id: OfficeGraph.WorkGraph.Signal,
        body_document_id: OfficeGraph.Content.Document
      ]
    },
    OfficeGraph.WorkGraph.ReviewFinding => %{
      create: [
        graph_item_id:
          {OfficeGraph.WorkGraph.GraphItem, resource_type: "review_finding", resource_id: :id},
        task_id: OfficeGraph.WorkGraph.Task,
        body_document_id: OfficeGraph.Content.Document
      ]
    },
    OfficeGraph.WorkGraph.VerificationCheck => %{
      create: [
        graph_item_id:
          {OfficeGraph.WorkGraph.GraphItem, resource_type: "verification_check", resource_id: :id},
        review_finding_id: OfficeGraph.WorkGraph.ReviewFinding,
        description_document_id: OfficeGraph.Content.Document
      ]
    },
    OfficeGraph.WorkGraph.Artifact => %{
      create: [
        graph_item_id:
          {OfficeGraph.WorkGraph.GraphItem, resource_type: "artifact", resource_id: :id}
      ]
    },
    OfficeGraph.WorkGraph.EvidenceItem => %{
      create: [
        graph_item_id:
          {OfficeGraph.WorkGraph.GraphItem, resource_type: "evidence_item", resource_id: :id},
        verification_check_id: OfficeGraph.WorkGraph.VerificationCheck,
        artifact_id: OfficeGraph.WorkGraph.Artifact,
        body_document_id: OfficeGraph.Content.Document
      ]
    },
    OfficeGraph.WorkGraph.VerificationResult => %{
      create: [
        verification_check_id: OfficeGraph.WorkGraph.VerificationCheck,
        evidence_item_id: OfficeGraph.WorkGraph.EvidenceItem,
        operation_id: OfficeGraph.Operations.OperationCorrelation
      ]
    }
  }

  @direct_ecto_operation_pattern ~r/\b(?<receiver>(?:OfficeGraph\.)?Repo|Repo|(?:Ecto\.)?Multi|Multi)\.(?<operation>transaction|insert!|insert|update!|update|delete!|delete|get_by!|get_by)(?![!?_[:alnum:]])/

  test "migration-created tables match the repo-wide Ash ownership inventory" do
    expected_tables = @expected_resources |> Map.keys() |> Enum.sort()

    duplicate_resources =
      @expected_resources
      |> Enum.group_by(fn {_table, {_domain, resource}} -> resource end, fn {table, _} ->
        table
      end)
      |> Enum.filter(fn {_resource, tables} -> length(tables) > 1 end)

    assert map_size(@expected_resources) == 40
    assert duplicate_resources == []
    assert migration_tables() == expected_tables
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
           "Expected resources must be AshPostgres resources with matching tables and migrate? false:\n#{format_errors(errors)}"
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

  test "shared Ash capability check is loadable" do
    assert Code.ensure_loaded?(HasCapability)

    assert HasCapability.describe(capability: :skeleton_read) =~
             "skeleton_read"
  end

  test "shared Ash capability check enforces explicit capability and target scope" do
    organization_id = Ecto.UUID.generate()
    workspace_id = Ecto.UUID.generate()

    actor = session_context(organization_id, workspace_id, ["skeleton.read"])
    changeset = scoped_changeset(organization_id, workspace_id)

    assert HasCapability.match?(actor, %{changeset: changeset}, capability: :skeleton_read)

    refute HasCapability.match?(actor, %{changeset: changeset}, [])

    refute HasCapability.match?(nil, %{changeset: changeset}, capability: :skeleton_read)

    refute HasCapability.match?(
             actor,
             %{changeset: scoped_changeset(Ecto.UUID.generate(), workspace_id)},
             capability: :skeleton_read
           )

    refute HasCapability.match?(
             actor,
             %{changeset: scoped_changeset(organization_id, Ecto.UUID.generate())},
             capability: :skeleton_read
           )

    refute HasCapability.match?(
             actor,
             %{changeset: %Ash.Changeset{}},
             capability: :skeleton_read
           )

    refute HasCapability.match?(
             session_context(organization_id, workspace_id, []),
             %{changeset: changeset},
             capability: :skeleton_read
           )

    assert HasCapability.match?(
             actor,
             %{query: %Ash.Query{}, action: %{type: :read}},
             capability: :skeleton_read
           )

    assert HasCapability.match?(
             session_context(organization_id, workspace_id, ["verification.complete"]),
             %{
               changeset: %Ash.Changeset{
                 action_type: :update,
                 data: %{organization_id: organization_id, workspace_id: workspace_id},
                 attributes: %{
                   organization_id: Ecto.UUID.generate(),
                   workspace_id: Ecto.UUID.generate()
                 }
               }
             },
             capability: :verification_complete
           )
  end

  test "direct Repo and Ecto.Multi operations are explicitly ledgered" do
    unapproved =
      direct_ecto_operations()
      |> Enum.reject(&ledger_approves_operation?(direct_ecto_ledger_entries(), &1))

    assert unapproved == [],
           """
           Found direct Repo/Ecto.Multi operations without explicit ledger approval.
           Each approval must document the file, function, and exact operation string in #{@architecture_exception_ledger}.

           #{format_direct_operations(unapproved)}
           """
  end

  test "direct Ecto exception ledger entries still point to current code" do
    operations = direct_ecto_operations()

    missing =
      for entry <- direct_ecto_ledger_entries(),
          function <- entry.functions,
          not Enum.any?(operations, &(&1.path == entry.path and &1.function == function)) do
        "#{entry.path} #{function}"
      end

    assert missing == [],
           "#{@architecture_exception_ledger} contains direct Ecto exception entries with no matching current code:\n#{format_errors(missing)}"
  end

  test "implementation summary includes architecture evidence mapping" do
    assert File.exists?(@implementation_summary),
           "Expected implementation summary at #{@implementation_summary}"

    summary = File.read!(@implementation_summary)

    for required_text <- [
          "### Architecture Evidence Matrix",
          "| Requirement | Evidence | Gate |",
          "Stable WorkGraph resources are Ash-backed",
          "WorkGraph Ash actions are authorization-aware",
          "Graph identity plus typed resource creation is atomic",
          "Stable product mutations route through Ash or approved exceptions",
          "Direct Ecto paths are approved and documented",
          "Architecture gate is part of backend verification",
          "OpenSpec remains valid and mapped to evidence",
          "mix architecture.conformance",
          "./bin/verify-backend",
          "openspec validate first-backend-walking-skeleton --strict",
          "openspec validate --changes --strict"
        ] do
      assert summary =~ required_text,
             "#{@implementation_summary} must include architecture evidence mapping for #{inspect(required_text)}"
    end
  end

  defp migration_tables do
    "priv/repo/migrations/*.exs"
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      path
      |> File.read!()
      |> then(&Regex.scan(~r/create\s+table\(:([a-zA-Z0-9_]+)\b/, &1, capture: :all_but_first))
      |> List.flatten()
    end)
    |> Enum.sort()
  end

  defp expected_domains do
    @expected_resources
    |> Map.values()
    |> Enum.map(fn {domain, _resource} -> domain end)
    |> MapSet.new()
  end

  defp resource_conformance_errors(table, resource) do
    if Code.ensure_loaded?(resource) do
      []
      |> maybe_add_resource_error(
        table,
        resource,
        "data_layer",
        AshPostgres.DataLayer,
        safe_info(fn -> Ash.Resource.Info.data_layer(resource) end)
      )
      |> maybe_add_resource_error(
        table,
        resource,
        "postgres.table",
        table,
        safe_info(fn -> AshPostgres.DataLayer.Info.table(resource) end)
      )
      |> maybe_add_resource_error(
        table,
        resource,
        "postgres.migrate?",
        false,
        safe_info(fn -> AshPostgres.DataLayer.Info.migrate?(resource) end)
      )
    else
      ["#{table}: #{inspect(resource)} is not loadable"]
    end
  end

  defp maybe_add_resource_error(errors, _table, _resource, _field, expected, {:ok, expected}) do
    errors
  end

  defp maybe_add_resource_error(errors, table, resource, field, expected, {:ok, actual}) do
    [
      "#{table}: #{inspect(resource)} #{field} expected #{inspect(expected)}, got #{inspect(actual)}"
      | errors
    ]
  end

  defp maybe_add_resource_error(errors, table, resource, field, expected, {:error, error}) do
    [
      "#{table}: #{inspect(resource)} #{field} expected #{inspect(expected)}, got error #{error}"
      | errors
    ]
  end

  defp safe_info(fun) do
    {:ok, fun.()}
  rescue
    exception ->
      {:error, Exception.message(exception)}
  catch
    kind, reason ->
      {:error, "#{kind}: #{inspect(reason)}"}
  end

  defp registered_domains_for(resource) do
    @ash_domains
    |> Enum.filter(fn domain ->
      with true <- Code.ensure_loaded?(domain),
           {:ok, resources} <- safe_info(fn -> Ash.Domain.Info.resources(domain) end) do
        resource in resources
      else
        _ -> false
      end
    end)
    |> Enum.sort_by(&inspect/1)
  end

  defp manual_ecto_schemas do
    "lib/office_graph/**/*.ex"
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      path
      |> File.read!()
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.reduce({nil, []}, fn {line, line_number}, {current_module, schemas} ->
        current_module = module_name(line) || current_module

        if Regex.match?(~r/^\s*use Ecto\.Schema\b/, line) do
          schema = %{
            path: path,
            line: line_number,
            module: current_module,
            source: String.trim(line)
          }

          {current_module, [schema | schemas]}
        else
          {current_module, schemas}
        end
      end)
      |> elem(1)
      |> Enum.reverse()
    end)
    |> Enum.sort_by(&{&1.path, &1.line})
  end

  defp work_graph_resources_modules do
    "lib/office_graph/work_graph/resources/*.ex"
    |> Path.wildcard()
    |> Enum.sort()
  end

  defp assert_work_graph_resources_are_ash! do
    errors =
      @work_graph_resources
      |> Enum.flat_map(fn resource ->
        case safe_info(fn -> Ash.Resource.Info.data_layer(resource) end) do
          {:ok, _data_layer} -> []
          {:error, error} -> ["#{inspect(resource)} is not an Ash resource: #{error}"]
        end
      end)

    assert errors == [],
           "Canonical WorkGraph modules must be Ash resources before policy/action checks can pass:\n#{format_errors(errors)}"
  end

  defp public_action?(resource, action_name, action_type) do
    resource
    |> Ash.Resource.Info.public_actions()
    |> Enum.any?(&(&1.name == action_name and &1.type == action_type))
  end

  defp actions_by_type(resource, action_type) do
    resource
    |> Ash.Resource.Info.actions()
    |> Enum.filter(&(&1.type == action_type))
  end

  defp capability_policy?(resource, action_name, action_type, capability) do
    resource
    |> Ash.Policy.Info.policies()
    |> Enum.filter(&policy_applies_to_action?(&1, action_name, action_type))
    |> Enum.any?(&policy_has_capability?(&1, capability))
  end

  defp scope_filter_policy?(resource, action_name, action_type) do
    resource
    |> Ash.Policy.Info.policies()
    |> Enum.filter(&policy_applies_to_action?(&1, action_name, action_type))
    |> Enum.any?(&policy_has_scope_filter?/1)
  end

  defp policy_applies_to_action?(
         %Ash.Policy.Policy{condition: conditions},
         action_name,
         action_type
       ) do
    Enum.any?(List.wrap(conditions), fn
      {Ash.Policy.Check.Action, opts} ->
        action_name in Keyword.fetch!(opts, :action)

      {Ash.Policy.Check.ActionType, opts} ->
        action_type in Keyword.fetch!(opts, :type)

      _condition ->
        false
    end)
  end

  defp policy_has_capability?(%Ash.Policy.Policy{policies: checks}, capability) do
    Enum.any?(List.wrap(checks), fn
      %Ash.Policy.Check{
        check_module: HasCapability,
        check_opts: opts,
        type: :authorize_if
      } ->
        Keyword.fetch(opts, :capability) == {:ok, capability}

      _check ->
        false
    end)
  end

  defp policy_has_scope_filter?(%Ash.Policy.Policy{policies: checks}) do
    Enum.any?(List.wrap(checks), fn
      %Ash.Policy.Check{
        check_module: Ash.Policy.Check.Expression,
        check_opts: opts,
        type: :authorize_if
      } ->
        opts
        |> Keyword.get(:expr)
        |> scope_filter_expression?()

      _check ->
        false
    end)
  end

  defp scope_filter_expression?(%Ash.Query.BooleanExpression{
         op: :and,
         left: left,
         right: right
       }) do
    [scope_actor_equality_field(left), scope_actor_equality_field(right)]
    |> MapSet.new()
    |> MapSet.equal?(MapSet.new([:organization_id, :workspace_id]))
  end

  defp scope_filter_expression?(_expression), do: false

  defp scope_actor_equality_field(%Ash.Query.Call{
         name: :==,
         args: [%Ash.Query.Ref{attribute: left_field}, {:_actor, right_field}]
       })
       when left_field == right_field and left_field in [:organization_id, :workspace_id],
       do: left_field

  defp scope_actor_equality_field(%Ash.Query.Call{
         name: :==,
         args: [{:_actor, left_field}, %Ash.Query.Ref{attribute: right_field}]
       })
       when left_field == right_field and left_field in [:organization_id, :workspace_id],
       do: left_field

  defp scope_actor_equality_field(_expression), do: nil

  defp same_scope_reference_validation(%{changes: changes}) do
    Enum.find_value(changes, fn
      %Ash.Resource.Change{change: {ValidateSameScopeReferences, opts}} ->
        Keyword.fetch!(opts, :references)

      _change ->
        nil
    end)
  end

  defp session_context(organization_id, workspace_id, capabilities) do
    %SessionContext{
      principal_id: Ecto.UUID.generate(),
      session_id: Ecto.UUID.generate(),
      organization_id: organization_id,
      workspace_id: workspace_id,
      capabilities: MapSet.new(capabilities)
    }
  end

  defp scoped_changeset(organization_id, workspace_id) do
    %Ash.Changeset{
      attributes: %{
        organization_id: organization_id,
        workspace_id: workspace_id
      }
    }
  end

  defp direct_ecto_operations do
    "lib/office_graph/**/*.ex"
    |> Path.wildcard()
    |> Enum.flat_map(&scan_file_for_direct_ecto_operations/1)
    |> Enum.sort_by(&{&1.path, &1.line, &1.operation})
  end

  defp scan_file_for_direct_ecto_operations(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce({nil, []}, fn {line, line_number}, {current_function, operations} ->
      current_function = function_name(line) || current_function

      line_operations =
        @direct_ecto_operation_pattern
        |> Regex.scan(line, capture: :all_names)
        |> Enum.map(fn [operation, receiver] ->
          %{
            path: path,
            line: line_number,
            function: current_function,
            operation: normalize_direct_ecto_operation(receiver, operation),
            source: String.trim(line)
          }
        end)

      {current_function, line_operations ++ operations}
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp direct_ecto_ledger_entries do
    @architecture_exception_ledger
    |> File.read!()
    |> String.split("\n")
    |> Enum.flat_map(fn line ->
      case Regex.run(~r/^\|\s*`([^`]+)`\s*\|\s*(.*?)\s*\|/, line) do
        [_, path, functions_cell] ->
          [
            %{
              path: path,
              functions: ledger_cell_values(functions_cell),
              operations: ledger_operation_values(line)
            }
          ]

        _ ->
          []
      end
    end)
  end

  defp ledger_approves_operation?(entries, operation) do
    Enum.any?(entries, fn entry ->
      entry.path == operation.path and
        MapSet.member?(entry.functions, operation.function) and
        MapSet.member?(entry.operations, operation.operation)
    end)
  end

  defp ledger_cell_values(cell) do
    cell
    |> then(&Regex.scan(~r/`([^`]+)`/, &1, capture: :all_but_first))
    |> List.flatten()
    |> MapSet.new()
  end

  defp ledger_operation_values(line) do
    @direct_ecto_operation_pattern
    |> Regex.scan(line, capture: :all_names)
    |> Enum.map(fn [operation, receiver] ->
      normalize_direct_ecto_operation(receiver, operation)
    end)
    |> MapSet.new()
  end

  defp normalize_direct_ecto_operation(receiver, operation)
       when receiver in ["Multi", "Ecto.Multi"] do
    "Ecto.Multi.#{operation}"
  end

  defp normalize_direct_ecto_operation(_receiver, operation) do
    "Repo.#{operation}"
  end

  defp module_name(line) do
    case Regex.run(~r/^\s*defmodule\s+([A-Za-z0-9_.]+)\s+do/, line) do
      [_, name] -> name
      _ -> nil
    end
  end

  defp function_name(line) do
    case Regex.run(~r/^\s*defp?\s+([a-zA-Z0-9_!?]+)\((.*)\)\s+do/, line) do
      [_, name, args] -> "#{name}/#{arity(args)}"
      _ -> nil
    end
  end

  defp arity(args) do
    args
    |> String.trim()
    |> case do
      "" -> 0
      args -> args |> String.split(",") |> length()
    end
  end

  defp format_modules(modules) do
    modules
    |> Enum.map_join("\n", &"  #{inspect(&1)}")
  end

  defp format_errors(errors) do
    Enum.map_join(errors, "\n", &"  #{&1}")
  end

  defp format_ecto_schemas(schemas) do
    schemas
    |> Enum.map_join("\n", fn schema ->
      "  #{schema.path}:#{schema.line} #{schema.module} #{schema.source}"
    end)
  end

  defp format_direct_operations(operations) do
    operations
    |> Enum.map_join("\n", fn operation ->
      "  #{operation.path}:#{operation.line} #{operation.function || "<module>"} #{operation.operation} #{operation.source}"
    end)
  end
end
