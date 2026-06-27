defmodule OfficeGraph.Architecture.AshConformanceTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.Authorization.Checks.HasCapability
  alias OfficeGraph.Foundation
  alias OfficeGraph.Identity.SessionContext
  alias OfficeGraph.WorkGraph.Changes.ValidateSameScopeReferences

  @ash_domains Application.compile_env(:office_graph, :ash_domains, [])
  @architecture_exception_ledger "openspec/specs/backend-model-ownership/architecture-exceptions.md"
  @api_migration_ledger "openspec/changes/stabilize-architecture-foundation/api-migration-ledger.md"
  @implementation_summary "openspec/specs/walking-skeleton-verification/implementation-summary.md"
  @model_inventory "openspec/specs/backend-model-ownership/model-inventory.md"
  @stabilization_inventory "openspec/changes/stabilize-architecture-foundation/stabilization-inventory.md"

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
    "evidence_candidates" =>
      {OfficeGraph.WorkGraph.Domain, OfficeGraph.WorkGraph.EvidenceCandidate},
    "evidence_items" => {OfficeGraph.WorkGraph.Domain, OfficeGraph.WorkGraph.EvidenceItem},
    "verification_results" =>
      {OfficeGraph.WorkGraph.Domain, OfficeGraph.WorkGraph.VerificationResult},
    "work_packets" => {OfficeGraph.WorkPackets.Domain, OfficeGraph.WorkPackets.WorkPacket},
    "work_packet_versions" =>
      {OfficeGraph.WorkPackets.Domain, OfficeGraph.WorkPackets.WorkPacketVersion},
    "work_packet_version_sources" =>
      {OfficeGraph.WorkPackets.Domain, OfficeGraph.WorkPackets.WorkPacketSourceReference},
    "work_packet_version_required_checks" =>
      {OfficeGraph.WorkPackets.Domain, OfficeGraph.WorkPackets.WorkPacketRequiredCheck},
    "runs" => {OfficeGraph.Runs.Domain, OfficeGraph.Runs.Run},
    "run_required_checks" => {OfficeGraph.Runs.Domain, OfficeGraph.Runs.RunRequiredCheck},
    "execution_observations" => {OfficeGraph.Runs.Domain, OfficeGraph.Runs.ExecutionObservation},
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

  @planned_mvp_resources %{
    "requirements" => {OfficeGraph.WorkGraph.Domain, OfficeGraph.WorkGraph.Requirement},
    "questions" => {OfficeGraph.WorkGraph.Domain, OfficeGraph.WorkGraph.Question},
    "decisions" => {OfficeGraph.WorkGraph.Domain, OfficeGraph.WorkGraph.Decision},
    "conversations" =>
      {OfficeGraph.NodeConversations.Domain, OfficeGraph.NodeConversations.Conversation},
    "conversation_messages" =>
      {OfficeGraph.NodeConversations.Domain, OfficeGraph.NodeConversations.ConversationMessage},
    "repositories" =>
      {OfficeGraph.SoftwareProving.Domain, OfficeGraph.SoftwareProving.Repository},
    "repository_refs" =>
      {OfficeGraph.SoftwareProving.Domain, OfficeGraph.SoftwareProving.RepositoryRef},
    "commits" => {OfficeGraph.SoftwareProving.Domain, OfficeGraph.SoftwareProving.Commit},
    "pull_requests" =>
      {OfficeGraph.SoftwareProving.Domain, OfficeGraph.SoftwareProving.PullRequest},
    "review_threads" =>
      {OfficeGraph.SoftwareProving.Domain, OfficeGraph.SoftwareProving.ReviewThread},
    "review_comments" =>
      {OfficeGraph.SoftwareProving.Domain, OfficeGraph.SoftwareProving.ReviewComment},
    "check_runs" => {OfficeGraph.SoftwareProving.Domain, OfficeGraph.SoftwareProving.CheckRun},
    "issues" => {OfficeGraph.SoftwareProving.Domain, OfficeGraph.SoftwareProving.Issue},
    "observability_issues" =>
      {OfficeGraph.SoftwareProving.Domain, OfficeGraph.SoftwareProving.ObservabilityIssue},
    "observability_events" =>
      {OfficeGraph.SoftwareProving.Domain, OfficeGraph.SoftwareProving.ObservabilityEvent},
    "rich_text_documents" => {OfficeGraph.Content.Domain, OfficeGraph.Content.RichTextDocument},
    "rich_text_blocks" => {OfficeGraph.Content.Domain, OfficeGraph.Content.RichTextBlock},
    "rich_text_block_versions" =>
      {OfficeGraph.Content.Domain, OfficeGraph.Content.RichTextBlockVersion},
    "rich_text_spans" => {OfficeGraph.Content.Domain, OfficeGraph.Content.RichTextSpan},
    "rich_text_mark_types" => {OfficeGraph.Content.Domain, OfficeGraph.Content.RichTextMarkType},
    "rich_text_marks" => {OfficeGraph.Content.Domain, OfficeGraph.Content.RichTextMark},
    "rich_text_references" => {OfficeGraph.Content.Domain, OfficeGraph.Content.RichTextReference},
    "rich_text_document_revisions" =>
      {OfficeGraph.Content.Domain, OfficeGraph.Content.RichTextDocumentRevision},
    "rich_text_quote_snapshots" =>
      {OfficeGraph.Content.Domain, OfficeGraph.Content.RichTextQuoteSnapshot},
    "rich_text_quote_selection_segments" =>
      {OfficeGraph.Content.Domain, OfficeGraph.Content.RichTextQuoteSelectionSegment},
    "rich_text_derived_plain_texts" =>
      {OfficeGraph.Content.Domain, OfficeGraph.Content.RichTextDerivedPlainText}
  }

  @accepted_software_proving_planned_tables MapSet.new([
                                              "repositories",
                                              "repository_refs",
                                              "commits",
                                              "pull_requests",
                                              "review_threads",
                                              "review_comments",
                                              "check_runs",
                                              "issues",
                                              "observability_issues",
                                              "observability_events"
                                            ])

  @accepted_rich_text_planned_tables MapSet.new([
                                       "rich_text_documents",
                                       "rich_text_blocks",
                                       "rich_text_block_versions",
                                       "rich_text_spans",
                                       "rich_text_mark_types",
                                       "rich_text_marks",
                                       "rich_text_references",
                                       "rich_text_document_revisions",
                                       "rich_text_quote_snapshots",
                                       "rich_text_quote_selection_segments",
                                       "rich_text_derived_plain_texts"
                                     ])

  @expected_resource_identities %{
    OfficeGraph.Tenancy.Organization => %{unique_slug: [:slug]},
    OfficeGraph.Tenancy.Workspace => %{unique_slug: [:organization_id, :slug]},
    OfficeGraph.Tenancy.Initiative => %{unique_slug: [:workspace_id, :slug]},
    OfficeGraph.Tenancy.Workstream => %{unique_slug: [:initiative_id, :slug]},
    OfficeGraph.Identity.Principal => %{email: [:email]},
    OfficeGraph.Identity.PrincipalProfile => %{principal_id: [:principal_id]},
    OfficeGraph.Identity.Credential => %{unique_subject: [:provider, :subject]},
    OfficeGraph.Identity.Session => %{
      unique_context: %{
        keys: [:principal_id, :organization_id, :workspace_id, :purpose],
        where: "is_nil(revoked_at)"
      }
    },
    OfficeGraph.Authorization.Capability => %{key: [:key]},
    OfficeGraph.Authorization.Role => %{unique_key: [:organization_id, :key]},
    OfficeGraph.Authorization.RoleCapability => %{
      unique_role_capability: [:role_id, :capability_id]
    },
    OfficeGraph.Authorization.RoleAssignment => %{
      unique_assignment: [:principal_id, :role_id, :organization_id, :workspace_id]
    },
    OfficeGraph.Authorization.PolicyBundle => %{unique_version: [:organization_id, :version]},
    OfficeGraph.Operations.OperationCorrelation => %{
      unique_correlation_id: [:organization_id, :workspace_id, :correlation_id],
      unique_idempotency_key: %{
        keys: [
          :organization_id,
          :workspace_id,
          :principal_id,
          :session_id,
          :action,
          :idempotency_key
        ],
        where: "not is_nil(idempotency_key)"
      }
    },
    OfficeGraph.Content.DocumentBlock => %{unique_document_position: [:document_id, :position]},
    OfficeGraph.Content.DocumentRevision => %{
      unique_document_revision: [:document_id, :revision_number]
    },
    OfficeGraph.ProposedChanges.ProposedGraphChange => %{
      unique_normalized_event_change_type: %{
        keys: [:normalized_event_id, :change_type],
        where: "not is_nil(normalized_event_id)"
      }
    }
  }

  @expected_action_capabilities %{
    OfficeGraph.WorkGraph.Signal => %{
      read: {:read, :skeleton_read},
      create: {:create, :proposed_change_apply}
    },
    OfficeGraph.WorkGraph.Task => %{
      read: {:read, :skeleton_read},
      create: {:create, :proposed_change_apply}
    },
    OfficeGraph.WorkGraph.ReviewFinding => %{
      read: {:read, :skeleton_read},
      create: {:create, :proposed_change_apply}
    },
    OfficeGraph.WorkGraph.VerificationCheck => %{
      read: {:read, :skeleton_read},
      create: {:create, :proposed_change_apply}
    },
    OfficeGraph.WorkGraph.Artifact => %{
      read: {:read, :skeleton_read},
      create: {:create, :evidence_link}
    },
    OfficeGraph.WorkGraph.EvidenceItem => %{
      read: {:read, :skeleton_read}
    },
    OfficeGraph.WorkGraph.VerificationResult => %{
      read: {:read, :skeleton_read}
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

  @direct_ecto_operation_pattern ~r/\b(?<receiver>Ecto\.Adapters\.SQL|(?:OfficeGraph\.)?Repo|Repo|(?:Ecto\.)?Multi|Multi)\.(?<operation>insert_or_update!|insert_or_update|insert_all|update_all|delete_all|transaction|aggregate|exists\?|get_by!|get_by|query!|query|stream|insert!|insert|update!|update|delete!|delete|get!|get|all|one!|one)(?![!?_[:alnum:]])/

  test "stabilization inventory documents current API domain and frontend debt" do
    assert File.exists?(@stabilization_inventory),
           "Expected stabilization inventory at #{@stabilization_inventory}"

    inventory = File.read!(@stabilization_inventory)

    for required_text <- [
          "## Active OpenSpec Scope",
          "## Manual API Surface Inventory",
          "## Domain And Database Exception Inventory",
          "## Broad Authorization Bypass Inventory",
          "## Frontend Architecture Gap Inventory",
          "OfficeGraphWeb.GraphQL.Schema",
          "OfficeGraph.ApiSupport",
          "assets/package.json"
        ] do
      assert inventory =~ required_text,
             "#{@stabilization_inventory} must document #{inspect(required_text)}"
    end
  end

  test "manual GraphQL and JSON API surfaces are covered by migration ledger entries" do
    unledgered =
      manual_api_surfaces()
      |> Enum.reject(&api_migration_ledger_approves_surface?(api_migration_ledger_entries(), &1))

    assert unledgered == [],
           """
           Found manual API surfaces without migration ledger coverage.
           Each surface must record owner, reason, replacement target, safety/parity tests, and retirement condition in #{@api_migration_ledger}.

           #{format_api_surfaces(unledgered)}
           """
  end

  test "manual API migration ledger entries still point to current surfaces" do
    current_surface_ids =
      manual_api_surfaces()
      |> MapSet.new(& &1.id)

    stale =
      for entry <- api_migration_ledger_entries(),
          not MapSet.member?(current_surface_ids, entry.id) do
        entry.id
      end

    assert stale == [],
           "#{@api_migration_ledger} contains surface ids with no matching current manual API surface:\n#{format_errors(stale)}"
  end

  test "manual API migration ledger records required approval metadata" do
    errors =
      @api_migration_ledger
      |> File.read!()
      |> api_migration_ledger_metadata_errors()

    assert errors == [],
           """
           #{@api_migration_ledger} entries must document owner, capability, exception class, reason, replacement target, safety/parity tests, and retirement condition:
           #{format_errors(errors)}
           """
  end

  test "ApiSupport no longer owns packet-run-verification orchestration" do
    source = File.read!("lib/office_graph/api_support.ex")

    direct_ecto_operations =
      scan_file_for_direct_ecto_operations("lib/office_graph/api_support.ex")

    refute source =~ "execute_packet_run_verification_transaction",
           "packet-run-verification transaction ownership belongs in a domain command"

    refute Enum.any?(direct_ecto_operations, &(&1.operation == "Repo.transaction")),
           "ApiSupport must stay limited to API context loading and delegation"

    assert source =~ "PacketRunVerification.execute",
           "ApiSupport should delegate packet-run-verification to the domain command"
  end

  test "manual GraphQL schema code is split under the GraphQL transport namespace" do
    assert File.exists?("lib/office_graph_web/graphql/schema.ex"),
           "Expected root GraphQL schema at lib/office_graph_web/graphql/schema.ex"

    refute File.exists?("lib/office_graph_web/schema.ex"),
           "Move the legacy monolithic schema into OfficeGraphWeb.GraphQL.* modules"

    graphql_modules =
      "lib/office_graph_web/graphql/**/*.ex"
      |> Path.wildcard()
      |> Enum.flat_map(&modules_in_file/1)

    for {path, module} <- graphql_modules do
      assert String.starts_with?(module, "OfficeGraphWeb.GraphQL."),
             "#{path} defines #{module}; GraphQL code must use OfficeGraphWeb.GraphQL.*"
    end

    for required_path <- [
          "lib/office_graph_web/graphql/schema.ex",
          "lib/office_graph_web/graphql/common/errors.ex",
          "lib/office_graph_web/graphql/common/queries.ex",
          "lib/office_graph_web/graphql/compatibility/types.ex",
          "lib/office_graph_web/graphql/compatibility/mutations.ex",
          "lib/office_graph_web/graphql/operator_workflow/types.ex",
          "lib/office_graph_web/graphql/operator_workflow/queries.ex",
          "lib/office_graph_web/graphql/packet_run_verification/types.ex",
          "lib/office_graph_web/graphql/packet_run_verification/mutations.ex"
        ] do
      assert File.exists?(required_path),
             "Expected GraphQL transport module file #{required_path}"
    end
  end

  test "manual JSON API code is split under the JSON API transport namespace" do
    old_json_api_paths =
      [
        "lib/office_graph_web/controllers/walking_skeleton_controller.ex",
        "lib/office_graph_web/controllers/operator_workflow_controller.ex",
        "lib/office_graph_web/controllers/packet_run_verification_controller.ex",
        "lib/office_graph_web/walking_skeleton_serializer.ex",
        "lib/office_graph_web/operator_workflow_serializer.ex",
        "lib/office_graph_web/packet_run_verification_serializer.ex"
      ]
      |> Enum.filter(&File.exists?/1)

    assert old_json_api_paths == [],
           "Move manual JSON API controllers and serializers under lib/office_graph_web/json_api:\n#{format_errors(old_json_api_paths)}"

    json_api_modules =
      "lib/office_graph_web/json_api/**/*.ex"
      |> Path.wildcard()
      |> Enum.flat_map(&modules_in_file/1)

    for {path, module} <- json_api_modules do
      assert String.starts_with?(module, "OfficeGraphWeb.JsonApi."),
             "#{path} defines #{module}; JSON API code must use OfficeGraphWeb.JsonApi.*"
    end

    for required_path <- [
          "lib/office_graph_web/json_api/common/errors.ex",
          "lib/office_graph_web/json_api/compatibility/controller.ex",
          "lib/office_graph_web/json_api/compatibility/serializer.ex",
          "lib/office_graph_web/json_api/operator_workflow/controller.ex",
          "lib/office_graph_web/json_api/operator_workflow/serializer.ex",
          "lib/office_graph_web/json_api/packet_run_verification/controller.ex",
          "lib/office_graph_web/json_api/packet_run_verification/serializer.ex"
        ] do
      assert File.exists?(required_path),
             "Expected JSON API transport module file #{required_path}"
    end
  end

  test "GraphQL and JSON API helpers stay transport-specific" do
    generic_api_modules =
      "lib/office_graph_web/api/**/*.ex"
      |> Path.wildcard()
      |> Enum.concat(Path.wildcard("lib/office_graph_web/api.ex"))
      |> Enum.filter(&File.exists?/1)

    assert generic_api_modules == [],
           "Do not create a generic OfficeGraphWeb.Api dumping ground:\n#{format_errors(generic_api_modules)}"

    graphql_errors = "lib/office_graph_web/graphql/common/errors.ex"
    json_errors = "lib/office_graph_web/json_api/common/errors.ex"

    assert File.exists?(graphql_errors), "Expected #{graphql_errors}"
    assert File.exists?(json_errors), "Expected #{json_errors}"

    refute File.read!(graphql_errors) =~ "put_status",
           "GraphQL error mapping must not know about Plug/Phoenix response envelopes"

    refute File.read!(json_errors) =~ "extensions:",
           "JSON API error mapping must not return Absinthe error envelopes"
  end

  test "broad Ash authorization bypasses are explicitly ledgered" do
    unapproved =
      ash_authorization_bypasses()
      |> Enum.reject(&auth_bypass_ledger_approves_operation?(auth_bypass_ledger_entries(), &1))

    assert unapproved == [],
           """
           Found authorize?: false call sites without explicit exception ledger approval.
           Each approval must document the file, function, bypass scope, reason, verification, and retirement condition in #{@architecture_exception_ledger}.

           #{format_auth_bypasses(unapproved)}
           """
  end

  test "authorization bypass ledger entries still point to current code" do
    current_tuples =
      ash_authorization_bypasses()
      |> MapSet.new(&{&1.path, &1.function})

    missing =
      for entry <- auth_bypass_ledger_entries(),
          not MapSet.member?(current_tuples, {entry.path, entry.function}) do
        "#{entry.path} #{entry.function}"
      end

    assert missing == [],
           "#{@architecture_exception_ledger} contains authorization bypass entries with no matching current code:\n#{format_errors(missing)}"
  end

  test "authorization bypass ledger records required approval metadata" do
    errors =
      @architecture_exception_ledger
      |> File.read!()
      |> auth_bypass_ledger_metadata_errors()

    assert errors == [],
           """
           #{@architecture_exception_ledger} authorization bypass entries must document owner, approved functions, bypass scope, approving spec, reason, verification coverage, and retirement condition:
           #{format_errors(errors)}
           """
  end

  @tag :scanner_contract
  test "direct Ecto scanner reports proposed-change transaction boundaries" do
    operations =
      direct_ecto_operations()
      |> Enum.filter(&(&1.path == "lib/office_graph/proposed_changes.ex"))
      |> MapSet.new(&{&1.path, &1.function, &1.operation})

    assert operations ==
             MapSet.new([
               {"lib/office_graph/proposed_changes.ex", "apply_all/3", "Repo.transaction"},
               {"lib/office_graph/proposed_changes.ex", "create_for_manual_intake/4",
                "Repo.transaction"}
             ])
  end

  @tag :scanner_contract
  test "traceability contexts no longer use direct Ecto mutations or aggregate reads" do
    forbidden_paths =
      MapSet.new([
        "lib/office_graph/operations.ex",
        "lib/office_graph/audit.ex",
        "lib/office_graph/revisions.ex"
      ])

    operations =
      direct_ecto_operations()
      |> Enum.filter(&(&1.path in forbidden_paths))

    assert operations == [],
           "Traceability contexts must create/count through Ash actions:\n#{format_direct_operations(operations)}"
  end

  @tag :scanner_contract
  test "direct Ecto ledger approval requires exact path function operation tuples" do
    entries =
      parse_direct_ecto_ledger_entries("""
      | File | Function | Operation |
      | --- | --- | --- |
      | `lib/example.ex` | `allowed/0` | `Repo.insert` |
      | `lib/example.ex` | `{other/0, Repo.update}` | Synthetic tuple approval |
      """)

    assert ledger_approves_operation?(entries, %{
             path: "lib/example.ex",
             function: "allowed/0",
             operation: "Repo.insert"
           })

    refute ledger_approves_operation?(entries, %{
             path: "lib/example.ex",
             function: "other/0",
             operation: "Repo.insert"
           })
  end

  test "migration-created tables match the repo-wide Ash ownership inventory" do
    expected_tables = @expected_resources |> Map.keys() |> Enum.sort()

    duplicate_resources =
      @expected_resources
      |> Enum.group_by(fn {_table, {_domain, resource}} -> resource end, fn {table, _} ->
        table
      end)
      |> Enum.filter(fn {_resource, tables} -> length(tables) > 1 end)

    assert map_size(@expected_resources) == 46
    assert duplicate_resources == []
    assert migration_tables() == expected_tables
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

  test "same-scope reference validation uses Ash for all configured references" do
    source = File.read!("lib/office_graph/work_graph/changes/validate_same_scope_references.ex")

    refute source =~ "fetch_unconverted_reference"
    refute source =~ "Repo.get"
    refute source =~ "@unconverted_reference_schemas"
  end

  test "verification completion centralizes parent-before-child lock acquisition" do
    source = File.read!("lib/office_graph/work_graph.ex")

    assert source =~ "lock_completion_graph!(session_context, verification_check.id)"
    assert source =~ "lock_review_findings_for_task!("
    assert source =~ "lock_verification_checks_for_findings!("
  end

  test "direct child create validations lock parents before accepting" do
    review_finding_source = File.read!("lib/office_graph/work_graph/review_finding.ex")
    verification_check_source = File.read!("lib/office_graph/work_graph/verification_check.ex")

    assert review_finding_source =~ "Ash.Changeset.before_action"
    assert review_finding_source =~ "Ash.Query.lock(:for_update)"

    assert verification_check_source =~ "Ash.Changeset.before_action"
    assert verification_check_source =~ "Ash.Query.lock(:for_update)"
  end

  test "proposed change applied transition is explicitly internal only" do
    source = File.read!("lib/office_graph/proposed_changes/proposed_graph_change.ex")

    assert source =~ "policy action(:mark_applied)"
    assert source =~ "forbid_if always()"
  end

  test "shared Ash capability check is loadable" do
    assert Code.ensure_loaded?(HasCapability)

    assert HasCapability.describe(capability: :skeleton_read) =~
             "skeleton_read"
  end

  test "shared Ash capability check enforces explicit capability and target scope" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    organization_id = bootstrap.organization.id
    workspace_id = bootstrap.workspace.id

    actor = bootstrap.session
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

    refute HasCapability.match?(
             session_context(organization_id, workspace_id, ["skeleton.read"]),
             %{changeset: changeset},
             capability: :skeleton_read
           )

    assert HasCapability.match?(
             actor,
             %{query: %Ash.Query{}, action: %{type: :read}},
             capability: :skeleton_read
           )

    assert HasCapability.match?(
             actor,
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
           Each approval must document the file, function, and exact operation as a tuple or row in #{@architecture_exception_ledger}.

           #{format_direct_operations(unapproved)}
           """
  end

  test "direct Ecto exception ledger entries still point to current code" do
    operations = direct_ecto_operations()

    current_tuples =
      operations
      |> MapSet.new(&{&1.path, &1.function, &1.operation})

    missing =
      for entry <- direct_ecto_ledger_entries(),
          not MapSet.member?(current_tuples, {entry.path, entry.function, entry.operation}) do
        "#{entry.path} #{entry.function} #{entry.operation}"
      end

    assert missing == [],
           "#{@architecture_exception_ledger} contains exact direct Ecto exception tuples with no matching current code:\n#{format_errors(missing)}"
  end

  test "direct Ecto exception ledger records required approval metadata" do
    errors =
      @architecture_exception_ledger
      |> File.read!()
      |> direct_ecto_ledger_metadata_errors()

    assert errors == [],
           """
           #{@architecture_exception_ledger} entries must document owner, reason, allowed operation type, approving spec, and retirement condition:
           #{format_errors(errors)}
           """
  end

  test "implementation summary includes architecture evidence mapping" do
    assert File.exists?(@implementation_summary),
           "Expected implementation summary at #{@implementation_summary}"

    summary = File.read!(@implementation_summary)

    for required_text <- [
          "## Architecture Evidence Matrix",
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
          "openspec validate --specs --strict",
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

  defp expected_resource_inventory do
    @expected_resources
    |> Enum.map(fn {table, {domain, resource}} ->
      {table, inspect(domain), inspect(resource)}
    end)
    |> Enum.sort()
  end

  defp model_inventory_resources do
    model_inventory_section_resources("## Implemented Table Inventory")
  end

  defp expected_planned_resource_inventory do
    @planned_mvp_resources
    |> Enum.map(fn {table, {domain, resource}} ->
      {table, inspect(domain), inspect(resource)}
    end)
    |> Enum.sort()
  end

  defp planned_model_inventory_resources do
    model_inventory_section_resources("## Planned MVP Resource Inventory")
  end

  defp planned_model_inventory_tables do
    planned_model_inventory_resources()
    |> Enum.map(fn {table, _domain, _resource} -> table end)
    |> MapSet.new()
  end

  defp planned_model_inventory_source_references do
    @model_inventory
    |> File.read!()
    |> model_inventory_section_lines("## Planned MVP Resource Inventory")
    |> Enum.flat_map(fn line ->
      case Regex.run(
             ~r/^\|\s*`([^`]+)`\s*\|\s*`[^`]+`\s*\|\s*`[^`]+`\s*\|\s*([^|]+?)\s*\|/,
             line
           ) do
        [_, table, sources] ->
          sources
          |> String.split(";")
          |> Enum.map(fn source ->
            source
            |> String.trim()
            |> String.trim_leading("`")
            |> String.trim_trailing("`")
          end)
          |> Enum.reject(&(&1 == ""))
          |> Enum.map(&{table, &1})

        _ ->
          []
      end
    end)
  end

  defp model_inventory_row(table) do
    @model_inventory
    |> File.read!()
    |> String.split("\n")
    |> Enum.find("", &String.starts_with?(&1, "| `#{table}` |"))
  end

  defp format_missing_tables(required_tables, actual_tables) do
    required_tables
    |> MapSet.difference(actual_tables)
    |> MapSet.to_list()
    |> Enum.sort()
    |> Enum.map_join("\n", &"- #{&1}")
  end

  defp model_inventory_section_resources(heading) do
    @model_inventory
    |> File.read!()
    |> model_inventory_section_lines(heading)
    |> parse_model_inventory_resource_rows()
  end

  defp model_inventory_section_lines(content, heading) do
    content
    |> String.split("\n")
    |> Enum.drop_while(&(&1 != heading))
    |> case do
      [] ->
        []

      [_heading | section_lines] ->
        Enum.take_while(section_lines, &(not String.starts_with?(&1, "## ")))
    end
  end

  defp parse_model_inventory_resource_rows(lines) do
    lines
    |> Enum.flat_map(fn line ->
      case Regex.run(~r/^\|\s*`([^`]+)`\s*\|\s*`([^`]+)`\s*\|\s*`([^`]+)`\s*\|/, line) do
        [_, table, domain, resource] -> [{table, domain, resource}]
        _ -> []
      end
    end)
    |> Enum.sort()
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

  defp identity_conformance_errors(resource, identity_name, expectation, identity) do
    expectation = normalize_identity_expectation(expectation)

    []
    |> maybe_add_identity_key_error(resource, identity_name, expectation.keys, identity.keys)
    |> maybe_add_identity_where_error(
      resource,
      identity_name,
      expectation.where,
      identity_where(identity)
    )
  end

  defp normalize_identity_expectation(keys) when is_list(keys), do: %{keys: keys, where: nil}

  defp normalize_identity_expectation(expectation) when is_map(expectation) do
    Map.put_new(expectation, :where, nil)
  end

  defp maybe_add_identity_key_error(errors, _resource, _identity_name, keys, keys), do: errors

  defp maybe_add_identity_key_error(errors, resource, identity_name, expected_keys, actual_keys) do
    [
      "#{inspect(resource)} identity #{inspect(identity_name)} expected keys #{inspect(expected_keys)}, got #{inspect(actual_keys)}"
      | errors
    ]
  end

  defp maybe_add_identity_where_error(errors, _resource, _identity_name, where, where), do: errors

  defp maybe_add_identity_where_error(
         errors,
         resource,
         identity_name,
         expected_where,
         actual_where
       ) do
    [
      "#{inspect(resource)} identity #{inspect(identity_name)} expected where #{inspect(expected_where)}, got #{inspect(actual_where)}"
      | errors
    ]
  end

  defp identity_where(%{where: nil}), do: nil
  defp identity_where(%{where: where}), do: inspect(where)

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

  defp foundation_read_filter(resource) do
    resource
    |> Ash.Policy.Info.policies()
    |> Enum.find_value(fn
      %Ash.Policy.Policy{policies: checks} = policy ->
        if policy_applies_to_action?(policy, :read, :read) do
          Enum.find_value(checks, fn
            %Ash.Policy.Check{
              check_module: Ash.Policy.Check.Expression,
              check_opts: opts,
              type: :authorize_if
            } ->
              Keyword.fetch!(opts, :expr)

            _check ->
              nil
          end)
        end

      _policy ->
        nil
    end)
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

  defp ash_authorization_bypasses do
    "lib/office_graph/**/*.ex"
    |> Path.wildcard()
    |> Enum.flat_map(&scan_file_for_ash_authorization_bypasses/1)
    |> Enum.uniq_by(&{&1.path, &1.function})
    |> Enum.sort_by(&{&1.path, &1.function})
  end

  defp scan_file_for_ash_authorization_bypasses(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce({nil, []}, fn {line, line_number}, {current_function, bypasses} ->
      current_function = function_name(line) || current_function

      bypasses =
        if line =~ "authorize?: false" do
          [
            %{
              path: path,
              line: line_number,
              function: current_function,
              source: String.trim(line)
            }
            | bypasses
          ]
        else
          bypasses
        end

      {current_function, bypasses}
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp manual_api_surfaces do
    graphql_root_surfaces() ++ json_api_route_surfaces() ++ json_serializer_surfaces()
  end

  defp graphql_root_surfaces do
    [
      {:query, "lib/office_graph_web/graphql/common/queries.ex"},
      {:query, "lib/office_graph_web/graphql/operator_workflow/queries.ex"},
      {:mutation, "lib/office_graph_web/graphql/compatibility/mutations.ex"},
      {:mutation, "lib/office_graph_web/graphql/packet_run_verification/mutations.ex"}
    ]
    |> Enum.flat_map(fn {root_kind, path} ->
      graphql_root_surfaces_in_file(root_kind, path)
    end)
  end

  defp graphql_root_surfaces_in_file(root_kind, path) do
    if File.exists?(path) do
      path
      |> File.read!()
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {line, line_number} ->
        case Regex.run(~r/^\s{4}field :([a-zA-Z0-9_!?]+)\b/, line) do
          [_, field_name] ->
            [
              %{
                id: "graphql.#{root_kind}.#{field_name}",
                type: "GraphQL #{root_kind}",
                path: path,
                line: line_number
              }
            ]

          _ ->
            []
        end
      end)
    else
      []
    end
  end

  defp json_api_route_surfaces do
    "lib/office_graph_web/router.ex"
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce({false, []}, fn {line, line_number}, {in_api_scope?, surfaces} ->
      cond do
        Regex.match?(~r/^\s{2}scope "\/api", OfficeGraphWeb do$/, line) ->
          {true, surfaces}

        in_api_scope? && Regex.match?(~r/^\s{2}end$/, line) ->
          {false, surfaces}

        in_api_scope? ->
          case Regex.run(~r/^\s{4}(get|post|put|patch|delete)\s+"([^"]+)"/, line) do
            [_, method, route] ->
              surface = %{
                id: "json.#{method}./api#{route}",
                type: "JSON #{String.upcase(method)} route",
                path: "lib/office_graph_web/router.ex",
                line: line_number
              }

              {in_api_scope?, [surface | surfaces]}

            _ ->
              {in_api_scope?, surfaces}
          end

        true ->
          {in_api_scope?, surfaces}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp json_serializer_surfaces do
    "lib/office_graph_web/json_api/**/*/serializer.ex"
    |> Path.wildcard()
    |> Enum.map(fn path ->
      source = File.read!(path)
      module = source |> String.split("\n") |> Enum.find_value(&module_name/1)

      %{
        id: "serializer.#{module}",
        type: "JSON serializer",
        path: path,
        line: 1
      }
    end)
    |> Enum.sort_by(& &1.id)
  end

  defp modules_in_file(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.flat_map(fn line ->
      case module_name(line) do
        nil -> []
        module -> [{path, module}]
      end
    end)
  end

  defp api_migration_ledger_entries do
    @api_migration_ledger
    |> File.read!()
    |> markdown_table_entries("Surface ID")
    |> Enum.map(fn entry -> %{id: unbacktick(Map.fetch!(entry, "Surface ID"))} end)
  end

  defp api_migration_ledger_approves_surface?(entries, surface) do
    Enum.any?(entries, &(&1.id == surface.id))
  end

  defp api_migration_ledger_metadata_errors(ledger) do
    table_metadata_errors(ledger, "Surface ID", [
      "Surface ID",
      "Owner",
      "Capability",
      "Current surface",
      "Exception class",
      "Reason",
      "Replacement target",
      "Safety/parity tests",
      "Retirement condition"
    ])
  end

  defp auth_bypass_ledger_entries do
    @architecture_exception_ledger
    |> File.read!()
    |> ledger_section("## Authorization Bypass Ledger")
    |> markdown_table_entries("File")
    |> Enum.flat_map(fn entry ->
      path = unbacktick(Map.fetch!(entry, "File"))

      entry
      |> Map.fetch!("Approved functions")
      |> backticked_values()
      |> Enum.map(&%{path: path, function: &1})
    end)
  end

  defp auth_bypass_ledger_approves_operation?(entries, bypass) do
    Enum.any?(entries, &(&1.path == bypass.path and &1.function == bypass.function))
  end

  defp auth_bypass_ledger_metadata_errors(ledger) do
    ledger
    |> ledger_section("## Authorization Bypass Ledger")
    |> table_metadata_errors("File", [
      "File",
      "Owner",
      "Approved functions",
      "Bypass scope",
      "Approving spec",
      "Reason",
      "Verification coverage",
      "Retirement condition"
    ])
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
    |> parse_direct_ecto_ledger_entries()
  end

  defp parse_direct_ecto_ledger_entries(ledger) do
    ledger
    |> String.split("\n")
    |> Enum.flat_map(fn line ->
      case Regex.run(~r/^\|\s*`([^`]+)`\s*\|\s*(.*?)\s*\|/, line) do
        [_, path, _functions_cell] ->
          ledger_tuple_values(line)
          |> Enum.map(fn {function, operation} ->
            %{path: path, function: function, operation: operation}
          end)

        _ ->
          []
      end
    end)
  end

  defp ledger_approves_operation?(entries, operation) do
    Enum.any?(entries, fn entry ->
      entry.path == operation.path and
        entry.function == operation.function and
        entry.operation == operation.operation
    end)
  end

  defp direct_ecto_ledger_metadata_errors(ledger) do
    rows = markdown_table_rows(ledger)
    [header | data_rows] = rows

    required_headers = [
      "File",
      "Owner",
      "Approved functions",
      "Allowed operation type",
      "Approving spec",
      "Reason",
      "Retirement condition"
    ]

    missing_headers = required_headers -- header

    row_errors =
      data_rows
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {row, row_number} ->
        for header_name <- required_headers,
            blank?(table_cell(row, header, header_name)) do
          "row #{row_number} missing #{header_name}"
        end
      end)

    Enum.map(missing_headers, &"missing required column #{&1}") ++ row_errors
  end

  defp markdown_table_rows(markdown) do
    markdown
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(String.trim_leading(&1), "|"))
    |> Enum.map(&markdown_table_cells/1)
    |> Enum.reject(&markdown_separator_row?/1)
  end

  defp markdown_table_entries(markdown, required_header) do
    case markdown_table_rows(markdown) do
      [] ->
        []

      [header | data_rows] ->
        if required_header in header do
          Enum.map(data_rows, fn row ->
            header
            |> Enum.zip(row ++ List.duplicate("", max(length(header) - length(row), 0)))
            |> Map.new()
          end)
        else
          []
        end
    end
  end

  defp table_metadata_errors(markdown, required_header, required_headers) do
    rows = markdown_table_rows(markdown)

    case rows do
      [] ->
        ["missing table with #{required_header} column"]

      [header | data_rows] ->
        if required_header in header do
          missing_headers = required_headers -- header

          row_errors =
            data_rows
            |> Enum.with_index(1)
            |> Enum.flat_map(fn {row, row_number} ->
              for header_name <- required_headers,
                  blank?(table_cell(row, header, header_name)) do
                "row #{row_number} missing #{header_name}"
              end
            end)

          Enum.map(missing_headers, &"missing required column #{&1}") ++ row_errors
        else
          ["missing table with #{required_header} column"]
        end
    end
  end

  defp ledger_section(markdown, heading) do
    markdown
    |> String.split("\n")
    |> Enum.drop_while(&(&1 != heading))
    |> case do
      [] ->
        ""

      [_heading | section_lines] ->
        section_lines
        |> Enum.take_while(&(not String.starts_with?(&1, "## ")))
        |> Enum.join("\n")
    end
  end

  defp unbacktick(value) do
    value
    |> String.trim()
    |> String.trim_leading("`")
    |> String.trim_trailing("`")
  end

  defp backticked_values(value) do
    ~r/`([^`]+)`/
    |> Regex.scan(value, capture: :all_but_first)
    |> List.flatten()
  end

  defp markdown_table_cells(line) do
    line
    |> String.trim()
    |> String.trim_leading("|")
    |> String.trim_trailing("|")
    |> String.split("|")
    |> Enum.map(&String.trim/1)
  end

  defp markdown_separator_row?(cells) do
    Enum.all?(cells, &String.match?(&1, ~r/^:?-{3,}:?$/))
  end

  defp table_cell(row, header, header_name) do
    case Enum.find_index(header, &(&1 == header_name)) do
      nil -> ""
      index -> Enum.at(row, index, "")
    end
  end

  defp blank?(value), do: String.trim(to_string(value)) == ""

  defp ledger_tuple_values(line) do
    tuple_values =
      ~r/`\{\s*([^`,{}]+)\s*,\s*((?:Repo|Ecto\.Multi|Ecto\.Adapters\.SQL)\.[^`,{}]+)\s*\}`/
      |> Regex.scan(line, capture: :all_but_first)
      |> Enum.map(fn [function, operation] ->
        {String.trim(function), String.trim(operation)}
      end)

    tuple_values ++ ledger_row_tuple_values(line)
  end

  defp ledger_row_tuple_values(line) do
    cells =
      line
      |> String.trim()
      |> String.trim_leading("|")
      |> String.trim_trailing("|")
      |> String.split("|")
      |> Enum.map(&String.trim/1)

    case cells do
      [_path_cell, function_cell, operation_cell | _rest] ->
        with {:ok, function} <- single_backticked_value(function_cell),
             {:ok, operation} <- single_operation_value(operation_cell) do
          [{function, operation}]
        else
          _ -> []
        end

      _ ->
        []
    end
  end

  defp single_backticked_value(cell) do
    case Regex.scan(~r/`([^`]+)`/, cell, capture: :all_but_first) do
      [[value]] -> {:ok, value}
      _ -> :error
    end
  end

  defp single_operation_value(cell) do
    case Regex.scan(
           ~r/`((?:Repo|Ecto\.Multi|Ecto\.Adapters\.SQL)\.[^`]+)`/,
           cell,
           capture: :all_but_first
         ) do
      [[value]] -> {:ok, value}
      _ -> :error
    end
  end

  defp normalize_direct_ecto_operation(receiver, operation)
       when receiver in ["Multi", "Ecto.Multi"] do
    "Ecto.Multi.#{operation}"
  end

  defp normalize_direct_ecto_operation("Ecto.Adapters.SQL", operation) do
    "Ecto.Adapters.SQL.#{operation}"
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
    case Regex.run(~r/^\s*defp?\s+([a-zA-Z0-9_!?]+)\((.*)\)(?:\s+when\b.*)?\s*(?:do|,)/, line) do
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

  defp format_auth_bypasses(bypasses) do
    bypasses
    |> Enum.map_join("\n", fn bypass ->
      "  #{bypass.path}:#{bypass.line} #{bypass.function || "<module>"} #{bypass.source}"
    end)
  end

  defp format_api_surfaces(surfaces) do
    surfaces
    |> Enum.map_join("\n", fn surface ->
      "  #{surface.path}:#{surface.line} #{surface.id} #{surface.type}"
    end)
  end
end
