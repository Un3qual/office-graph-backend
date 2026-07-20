defmodule OfficeGraph.TestSupport.AshConformanceSupport do
  @moduledoc false

  import ExUnit.Assertions

  alias OfficeGraph.Authorization.Checks.HasCapability
  alias OfficeGraph.Identity.SessionContext
  alias OfficeGraph.WorkGraph.Changes.ValidateSameScopeReferences

  @ash_domains Application.compile_env(:office_graph, :ash_domains, [])
  @architecture_exception_ledger "openspec/specs/backend-model-ownership/architecture-exceptions.md"
  @stabilization_change_archive "openspec/changes/archive/2026-06-30-stabilize-architecture-foundation"
  @api_migration_ledger "openspec/specs/backend-model-ownership/api-migration-ledger.md"
  @implementation_summary "openspec/specs/walking-skeleton-verification/implementation-summary.md"
  @map_field_classification "#{@stabilization_change_archive}/map-field-classification.md"
  @model_inventory "openspec/specs/backend-model-ownership/model-inventory.md"
  @stabilization_inventory "#{@stabilization_change_archive}/stabilization-inventory.md"

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
    "domain_events" =>
      {OfficeGraph.DurableDelivery.Domain, OfficeGraph.DurableDelivery.DomainEvent},
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
    "integration_credentials" =>
      {OfficeGraph.Integrations.Domain, OfficeGraph.Integrations.IntegrationCredential},
    "external_references" =>
      {OfficeGraph.ExternalRefs.Domain, OfficeGraph.ExternalRefs.ExternalReference},
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
    "github_repositories" =>
      {OfficeGraph.SoftwareProving.Domain, OfficeGraph.SoftwareProving.GitHub.RepositoryExtension},
    "github_pull_requests" =>
      {OfficeGraph.SoftwareProving.Domain,
       OfficeGraph.SoftwareProving.GitHub.PullRequestExtension},
    "github_review_threads" =>
      {OfficeGraph.SoftwareProving.Domain,
       OfficeGraph.SoftwareProving.GitHub.ReviewThreadExtension},
    "github_review_comments" =>
      {OfficeGraph.SoftwareProving.Domain,
       OfficeGraph.SoftwareProving.GitHub.ReviewCommentExtension},
    "github_check_runs" =>
      {OfficeGraph.SoftwareProving.Domain, OfficeGraph.SoftwareProving.GitHub.CheckRunExtension},
    "github_installations" =>
      {OfficeGraph.GitHubIntegration.Domain, OfficeGraph.GitHubIntegration.Installation},
    "github_permission_snapshots" =>
      {OfficeGraph.GitHubIntegration.Domain, OfficeGraph.GitHubIntegration.PermissionSnapshot},
    "github_permission_entries" =>
      {OfficeGraph.GitHubIntegration.Domain, OfficeGraph.GitHubIntegration.PermissionEntry},
    "github_installation_credentials" =>
      {OfficeGraph.GitHubIntegration.Domain, OfficeGraph.GitHubIntegration.InstallationCredential},
    "github_sync_outcomes" =>
      {OfficeGraph.GitHubIntegration.Domain, OfficeGraph.GitHubIntegration.SyncOutcome},
    "github_outbound_actions" =>
      {OfficeGraph.GitHubIntegration.Domain, OfficeGraph.GitHubIntegration.OutboundAction},
    "graph_items" => {OfficeGraph.WorkGraph.Domain, OfficeGraph.WorkGraph.GraphItem},
    "relationship_definitions" =>
      {OfficeGraph.WorkGraph.Domain, OfficeGraph.WorkGraph.RelationshipDefinition},
    "relationship_endpoint_rules" =>
      {OfficeGraph.WorkGraph.Domain, OfficeGraph.WorkGraph.RelationshipEndpointRule},
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
      {OfficeGraph.ProposedChanges.Domain, OfficeGraph.ProposedChanges.ProposedGraphChange},
    "agent_definitions" =>
      {OfficeGraph.AgentRuntime.Domain, OfficeGraph.AgentRuntime.AgentDefinition},
    "agent_organization_bindings" =>
      {OfficeGraph.AgentRuntime.Domain, OfficeGraph.AgentRuntime.OrganizationBinding},
    "agent_executions" =>
      {OfficeGraph.AgentRuntime.Domain, OfficeGraph.AgentRuntime.AgentExecution},
    "agent_authority_snapshots" =>
      {OfficeGraph.AgentRuntime.Domain, OfficeGraph.AgentRuntime.AuthoritySnapshot},
    "agent_context_packages" =>
      {OfficeGraph.AgentRuntime.Domain, OfficeGraph.AgentRuntime.ContextPackage},
    "agent_context_entries" =>
      {OfficeGraph.AgentRuntime.Domain, OfficeGraph.AgentRuntime.ContextEntry},
    "agent_model_requests" =>
      {OfficeGraph.AgentRuntime.Domain, OfficeGraph.AgentRuntime.ModelRequest},
    "agent_tool_requests" =>
      {OfficeGraph.AgentRuntime.Domain, OfficeGraph.AgentRuntime.ToolRequest},
    "agent_approval_requests" =>
      {OfficeGraph.AgentRuntime.Domain, OfficeGraph.AgentRuntime.ApprovalRequest},
    "agent_context_expansion_requests" =>
      {OfficeGraph.AgentRuntime.Domain, OfficeGraph.AgentRuntime.ContextExpansionRequest},
    "conversations" =>
      {OfficeGraph.NodeConversations.Domain, OfficeGraph.NodeConversations.Conversation},
    "conversation_messages" =>
      {OfficeGraph.NodeConversations.Domain, OfficeGraph.NodeConversations.ConversationMessage}
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
    OfficeGraph.WorkGraph.RelationshipDefinition => %{unique_key: [:key]},
    OfficeGraph.WorkGraph.RelationshipEndpointRule => %{
      unique_definition_kinds: [:relationship_definition_id, :source_kind, :target_kind]
    },
    OfficeGraph.WorkGraph.GraphRelationship => %{
      active_definition_edge: %{
        keys: [:organization_id, :definition_id, :source_item_id, :target_item_id],
        where: ~s(lifecycle == "active")
      }
    },
    OfficeGraph.Identity.Principal => %{email: [:email]},
    OfficeGraph.Identity.PrincipalProfile => %{principal_id: [:principal_id]},
    OfficeGraph.Identity.Credential => %{unique_subject: [:provider, :subject]},
    OfficeGraph.Integrations.RawArchive => %{
      provider_delivery: %{
        keys: [:source_id, :external_delivery_id],
        where: "not is_nil(external_delivery_id)"
      }
    },
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
    OfficeGraph.AgentRuntime.AgentDefinition => %{unique_key: [:key]},
    OfficeGraph.AgentRuntime.OrganizationBinding => %{
      unique_definition_organization: [:definition_id, :organization_id],
      unique_organization_principal: [:organization_id, :agent_principal_id],
      unique_operation: [:operation_id]
    },
    OfficeGraph.AgentRuntime.AgentExecution => %{
      unique_operation: [:operation_id],
      unique_binding_run_idempotency: [:organization_binding_id, :run_id, :idempotency_key]
    },
    OfficeGraph.AgentRuntime.AuthoritySnapshot => %{
      unique_execution_version: [:execution_id, :version]
    },
    OfficeGraph.AgentRuntime.ContextPackage => %{
      unique_execution_version: [:execution_id, :version]
    },
    OfficeGraph.AgentRuntime.ContextEntry => %{
      unique_package_ordinal: [:context_package_id, :ordinal]
    },
    OfficeGraph.AgentRuntime.ModelRequest => %{
      unique_execution_step_idempotency: [:execution_id, :step_key, :idempotency_key]
    },
    OfficeGraph.AgentRuntime.ToolRequest => %{
      unique_execution_step_idempotency: [:execution_id, :step_key, :idempotency_key]
    },
    OfficeGraph.AgentRuntime.ApprovalRequest => %{
      unique_pending_step: %{
        keys: [:execution_id, :step_key],
        where: ~s(state == "pending")
      }
    },
    OfficeGraph.AgentRuntime.ContextExpansionRequest => %{
      unique_pending_step: %{
        keys: [:execution_id, :step_key],
        where: ~s(state == "pending")
      }
    },
    OfficeGraph.NodeConversations.Conversation => %{
      unique_run_graph_item: [
        :organization_id,
        :workspace_id,
        :run_id,
        :graph_item_id,
        :purpose
      ]
    },
    OfficeGraph.NodeConversations.ConversationMessage => %{unique_operation: [:operation_id]},
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
      },
      unique_system_idempotency: %{
        keys: [
          :organization_id,
          :workspace_id,
          :principal_id,
          :action,
          :idempotency_scope,
          :idempotency_key
        ],
        where: ~s(operation_kind == "system")
      }
    },
    OfficeGraph.SoftwareProving.RepositoryRef => %{
      unique_repository_name: [:repository_id, :name]
    },
    OfficeGraph.SoftwareProving.Commit => %{
      unique_repository_oid: [:repository_id, :oid]
    },
    OfficeGraph.SoftwareProving.PullRequest => %{
      unique_repository_number: [:repository_id, :number]
    },
    OfficeGraph.SoftwareProving.GitHub.RepositoryExtension => %{
      unique_workspace_node_id: %{
        keys: [:organization_id, :workspace_id, :node_id],
        where: "not is_nil(workspace_id)"
      },
      unique_organization_node_id: %{
        keys: [:organization_id, :node_id],
        where: "is_nil(workspace_id)"
      }
    },
    OfficeGraph.SoftwareProving.GitHub.PullRequestExtension => %{
      unique_workspace_node_id: %{
        keys: [:organization_id, :workspace_id, :node_id],
        where: "not is_nil(workspace_id)"
      },
      unique_organization_node_id: %{
        keys: [:organization_id, :node_id],
        where: "is_nil(workspace_id)"
      }
    },
    OfficeGraph.SoftwareProving.GitHub.ReviewThreadExtension => %{
      unique_workspace_node_id: %{
        keys: [:organization_id, :workspace_id, :node_id],
        where: "not is_nil(workspace_id)"
      },
      unique_organization_node_id: %{
        keys: [:organization_id, :node_id],
        where: "is_nil(workspace_id)"
      }
    },
    OfficeGraph.SoftwareProving.GitHub.ReviewCommentExtension => %{
      unique_workspace_node_id: %{
        keys: [:organization_id, :workspace_id, :node_id],
        where: "not is_nil(workspace_id)"
      },
      unique_organization_node_id: %{
        keys: [:organization_id, :node_id],
        where: "is_nil(workspace_id)"
      }
    },
    OfficeGraph.SoftwareProving.GitHub.CheckRunExtension => %{
      unique_workspace_node_id: %{
        keys: [:organization_id, :workspace_id, :node_id, :pull_request_id],
        where: "not is_nil(workspace_id)"
      },
      unique_organization_node_id: %{
        keys: [:organization_id, :node_id, :pull_request_id],
        where: "is_nil(workspace_id)"
      }
    },
    OfficeGraph.Integrations.IntegrationCredential => %{
      unique_workspace_reference: %{
        keys: [:organization_id, :workspace_id, :kind, :secret_reference],
        where: "not is_nil(workspace_id)"
      },
      unique_organization_reference: %{
        keys: [:organization_id, :kind, :secret_reference],
        where: "is_nil(workspace_id)"
      }
    },
    OfficeGraph.GitHubIntegration.Installation => %{
      unique_external_installation: [:external_installation_id],
      unique_operation: [:operation_id]
    },
    OfficeGraph.GitHubIntegration.PermissionSnapshot => %{
      unique_installation_version: [:installation_id, :version]
    },
    OfficeGraph.GitHubIntegration.PermissionEntry => %{
      unique_snapshot_name: [:permission_snapshot_id, :name]
    },
    OfficeGraph.GitHubIntegration.InstallationCredential => %{
      unique_installation_purpose: [:installation_id, :purpose]
    },
    OfficeGraph.GitHubIntegration.SyncOutcome => %{
      unique_operation: [:operation_id]
    },
    OfficeGraph.GitHubIntegration.OutboundAction => %{
      unique_operation: [:operation_id]
    },
    OfficeGraph.DurableDelivery.DomainEvent => %{event_key: [:event_key]},
    OfficeGraph.Content.DocumentBlock => %{
      unique_document_position: [:document_id, :position]
    },
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

  @expected_work_graph_relationships %{
    OfficeGraph.WorkGraph.RelationshipDefinition => %{
      endpoint_rules:
        {:has_many, OfficeGraph.WorkGraph.RelationshipEndpointRule, :id,
         :relationship_definition_id}
    },
    OfficeGraph.WorkGraph.RelationshipEndpointRule => %{
      definition:
        {:belongs_to, OfficeGraph.WorkGraph.RelationshipDefinition, :relationship_definition_id,
         :id}
    },
    OfficeGraph.WorkGraph.GraphItem => %{
      outgoing_relationships:
        {:has_many, OfficeGraph.WorkGraph.GraphRelationship, :id, :source_item_id},
      incoming_relationships:
        {:has_many, OfficeGraph.WorkGraph.GraphRelationship, :id, :target_item_id}
    },
    OfficeGraph.WorkGraph.GraphRelationship => %{
      definition:
        {:belongs_to, OfficeGraph.WorkGraph.RelationshipDefinition, :definition_id, :id},
      organization: {:belongs_to, OfficeGraph.Tenancy.Organization, :organization_id, :id},
      governing_workspace: {:belongs_to, OfficeGraph.Tenancy.Workspace, :workspace_id, :id},
      source_item: {:belongs_to, OfficeGraph.WorkGraph.GraphItem, :source_item_id, :id},
      target_item: {:belongs_to, OfficeGraph.WorkGraph.GraphItem, :target_item_id, :id},
      asserting_principal:
        {:belongs_to, OfficeGraph.Identity.Principal, :asserting_principal_id, :id},
      operation: {:belongs_to, OfficeGraph.Operations.OperationCorrelation, :operation_id, :id},
      superseded_relationship:
        {:belongs_to, OfficeGraph.WorkGraph.GraphRelationship, :supersedes_relationship_id, :id},
      tombstone: {:belongs_to, OfficeGraph.Tombstones.Tombstone, :tombstone_id, :id}
    },
    OfficeGraph.WorkGraph.Signal => %{
      graph_item: {:belongs_to, OfficeGraph.WorkGraph.GraphItem, :graph_item_id, :id},
      body_document: {:belongs_to, OfficeGraph.Content.Document, :body_document_id, :id}
    },
    OfficeGraph.WorkGraph.Task => %{
      graph_item: {:belongs_to, OfficeGraph.WorkGraph.GraphItem, :graph_item_id, :id},
      source_signal: {:belongs_to, OfficeGraph.WorkGraph.Signal, :source_signal_id, :id},
      body_document: {:belongs_to, OfficeGraph.Content.Document, :body_document_id, :id}
    },
    OfficeGraph.WorkGraph.ReviewFinding => %{
      graph_item: {:belongs_to, OfficeGraph.WorkGraph.GraphItem, :graph_item_id, :id},
      task: {:belongs_to, OfficeGraph.WorkGraph.Task, :task_id, :id},
      body_document: {:belongs_to, OfficeGraph.Content.Document, :body_document_id, :id}
    },
    OfficeGraph.WorkGraph.VerificationCheck => %{
      graph_item: {:belongs_to, OfficeGraph.WorkGraph.GraphItem, :graph_item_id, :id},
      review_finding: {:belongs_to, OfficeGraph.WorkGraph.ReviewFinding, :review_finding_id, :id},
      description_document:
        {:belongs_to, OfficeGraph.Content.Document, :description_document_id, :id}
    },
    OfficeGraph.WorkGraph.Artifact => %{
      graph_item: {:belongs_to, OfficeGraph.WorkGraph.GraphItem, :graph_item_id, :id}
    },
    OfficeGraph.WorkGraph.EvidenceCandidate => %{
      verification_check:
        {:belongs_to, OfficeGraph.WorkGraph.VerificationCheck, :verification_check_id, :id},
      artifact: {:belongs_to, OfficeGraph.WorkGraph.Artifact, :artifact_id, :id},
      operation: {:belongs_to, OfficeGraph.Operations.OperationCorrelation, :operation_id, :id}
    },
    OfficeGraph.WorkGraph.EvidenceItem => %{
      graph_item: {:belongs_to, OfficeGraph.WorkGraph.GraphItem, :graph_item_id, :id},
      verification_check:
        {:belongs_to, OfficeGraph.WorkGraph.VerificationCheck, :verification_check_id, :id},
      artifact: {:belongs_to, OfficeGraph.WorkGraph.Artifact, :artifact_id, :id},
      body_document: {:belongs_to, OfficeGraph.Content.Document, :body_document_id, :id},
      candidate: {:belongs_to, OfficeGraph.WorkGraph.EvidenceCandidate, :candidate_id, :id},
      acceptance_operation:
        {:belongs_to, OfficeGraph.Operations.OperationCorrelation, :acceptance_operation_id, :id}
    },
    OfficeGraph.WorkGraph.VerificationResult => %{
      verification_check:
        {:belongs_to, OfficeGraph.WorkGraph.VerificationCheck, :verification_check_id, :id},
      evidence_item: {:belongs_to, OfficeGraph.WorkGraph.EvidenceItem, :evidence_item_id, :id},
      operation: {:belongs_to, OfficeGraph.Operations.OperationCorrelation, :operation_id, :id},
      target_graph_item:
        {:belongs_to, OfficeGraph.WorkGraph.GraphItem, :target_graph_item_id, :id}
    }
  }

  @expected_work_packets_relationships %{
    OfficeGraph.WorkPackets.WorkPacket => %{
      operation: {:belongs_to, OfficeGraph.Operations.OperationCorrelation, :operation_id, :id},
      current_version:
        {:belongs_to, OfficeGraph.WorkPackets.WorkPacketVersion, :current_version_id, :id},
      versions: {:has_many, OfficeGraph.WorkPackets.WorkPacketVersion, :id, :work_packet_id}
    },
    OfficeGraph.WorkPackets.WorkPacketVersion => %{
      work_packet: {:belongs_to, OfficeGraph.WorkPackets.WorkPacket, :work_packet_id, :id},
      operation: {:belongs_to, OfficeGraph.Operations.OperationCorrelation, :operation_id, :id},
      source_references:
        {:has_many, OfficeGraph.WorkPackets.WorkPacketSourceReference, :id,
         :work_packet_version_id},
      required_checks:
        {:has_many, OfficeGraph.WorkPackets.WorkPacketRequiredCheck, :id, :work_packet_version_id}
    },
    OfficeGraph.WorkPackets.WorkPacketSourceReference => %{
      work_packet_version:
        {:belongs_to, OfficeGraph.WorkPackets.WorkPacketVersion, :work_packet_version_id, :id},
      graph_item: {:belongs_to, OfficeGraph.WorkGraph.GraphItem, :graph_item_id, :id}
    },
    OfficeGraph.WorkPackets.WorkPacketRequiredCheck => %{
      work_packet_version:
        {:belongs_to, OfficeGraph.WorkPackets.WorkPacketVersion, :work_packet_version_id, :id},
      verification_check:
        {:belongs_to, OfficeGraph.WorkGraph.VerificationCheck, :verification_check_id, :id}
    }
  }

  @expected_work_packets_reference_validations %{
    OfficeGraph.WorkPackets.WorkPacket => %{
      create: [operation_id: OfficeGraph.Operations.OperationCorrelation],
      set_current_version: [current_version_id: OfficeGraph.WorkPackets.WorkPacketVersion]
    },
    OfficeGraph.WorkPackets.WorkPacketVersion => %{
      create: [
        work_packet_id: OfficeGraph.WorkPackets.WorkPacket,
        operation_id: OfficeGraph.Operations.OperationCorrelation
      ]
    },
    OfficeGraph.WorkPackets.WorkPacketSourceReference => %{
      create: [
        work_packet_version_id: OfficeGraph.WorkPackets.WorkPacketVersion,
        graph_item_id: OfficeGraph.WorkGraph.GraphItem
      ]
    },
    OfficeGraph.WorkPackets.WorkPacketRequiredCheck => %{
      create: [
        work_packet_version_id: OfficeGraph.WorkPackets.WorkPacketVersion,
        verification_check_id: OfficeGraph.WorkGraph.VerificationCheck
      ]
    }
  }

  @expected_work_packets_create_defaults %{
    OfficeGraph.WorkPackets.WorkPacket => %{
      state: "draft"
    },
    OfficeGraph.WorkPackets.WorkPacketSourceReference => %{
      source_kind: "graph_item",
      rationale: "packet_source",
      visibility: "full",
      sensitivity: "internal"
    },
    OfficeGraph.WorkPackets.WorkPacketRequiredCheck => %{
      requirement_kind: "required",
      state: "pending"
    }
  }

  @expected_runs_relationships %{
    OfficeGraph.Runs.Run => %{
      work_packet: {:belongs_to, OfficeGraph.WorkPackets.WorkPacket, :work_packet_id, :id},
      work_packet_version:
        {:belongs_to, OfficeGraph.WorkPackets.WorkPacketVersion, :work_packet_version_id, :id},
      operation: {:belongs_to, OfficeGraph.Operations.OperationCorrelation, :operation_id, :id},
      initiator_principal:
        {:belongs_to, OfficeGraph.Identity.Principal, :initiator_principal_id, :id},
      required_checks: {:has_many, OfficeGraph.Runs.RunRequiredCheck, :id, :run_id},
      execution_observations:
        {:has_many, OfficeGraph.Runs.ExecutionObservation, :id, :work_run_id},
      events: {:has_many, OfficeGraph.Runs.RunEvent, :id, :run_id}
    },
    OfficeGraph.Runs.RunRequiredCheck => %{
      run: {:belongs_to, OfficeGraph.Runs.Run, :run_id, :id},
      verification_check:
        {:belongs_to, OfficeGraph.WorkGraph.VerificationCheck, :verification_check_id, :id}
    },
    OfficeGraph.Runs.ExecutionObservation => %{
      work_run: {:belongs_to, OfficeGraph.Runs.Run, :work_run_id, :id},
      operation: {:belongs_to, OfficeGraph.Operations.OperationCorrelation, :operation_id, :id},
      verification_check:
        {:belongs_to, OfficeGraph.WorkGraph.VerificationCheck, :verification_check_id, :id},
      graph_item: {:belongs_to, OfficeGraph.WorkGraph.GraphItem, :graph_item_id, :id}
    },
    OfficeGraph.Runs.RunEvent => %{
      run: {:belongs_to, OfficeGraph.Runs.Run, :run_id, :id}
    }
  }

  @expected_runs_reference_validations %{
    OfficeGraph.Runs.Run => %{
      create: [
        work_packet_id: OfficeGraph.WorkPackets.WorkPacket,
        work_packet_version_id: OfficeGraph.WorkPackets.WorkPacketVersion,
        operation_id: OfficeGraph.Operations.OperationCorrelation
      ]
    },
    OfficeGraph.Runs.RunRequiredCheck => %{
      create: [
        run_id: OfficeGraph.Runs.Run,
        verification_check_id: OfficeGraph.WorkGraph.VerificationCheck
      ]
    },
    OfficeGraph.Runs.ExecutionObservation => %{
      create: [
        work_run_id: OfficeGraph.Runs.Run,
        operation_id: OfficeGraph.Operations.OperationCorrelation,
        verification_check_id: OfficeGraph.WorkGraph.VerificationCheck,
        graph_item_id: OfficeGraph.WorkGraph.GraphItem
      ]
    }
  }

  @expected_runs_create_defaults %{
    OfficeGraph.Runs.RunRequiredCheck => %{
      state: "pending"
    }
  }

  @expected_work_graph_internal_modules [
    OfficeGraph.WorkGraph.Queries,
    OfficeGraph.WorkGraph.ProposalCommands,
    OfficeGraph.WorkGraph.VerificationCommands,
    OfficeGraph.WorkGraph.CommandSupport
  ]

  @direct_ecto_operation_pattern ~r/\b(?<receiver>Ecto\.Adapters\.SQL|(?:OfficeGraph\.)?Repo|Repo|(?:Ecto\.)?Multi|Multi)\.(?<operation>insert_or_update!|insert_or_update|insert_all|update_all|delete_all|transaction|aggregate|exists\?|get_by!|get_by|query!|query|stream|insert!|insert|update!|update|delete!|delete|get!|get|all|one!|one)(?![!?_[:alnum:]])/

  defmacro __using__(_opts) do
    quote do
      use OfficeGraph.DataCase, async: false

      import OfficeGraph.TestSupport.AshConformanceSupport

      alias OfficeGraph.Authorization.Checks.HasCapability
      alias OfficeGraph.Foundation
      alias OfficeGraph.Identity.SessionContext
      alias OfficeGraph.WorkGraph.Changes.ValidateSameScopeReferences

      @ash_domains unquote(Macro.escape(@ash_domains))
      @architecture_exception_ledger unquote(@architecture_exception_ledger)
      @stabilization_change_archive unquote(@stabilization_change_archive)
      @api_migration_ledger unquote(@api_migration_ledger)
      @implementation_summary unquote(@implementation_summary)
      @map_field_classification unquote(@map_field_classification)
      @model_inventory unquote(@model_inventory)
      @stabilization_inventory unquote(@stabilization_inventory)
      @expected_resources unquote(Macro.escape(@expected_resources))
      @work_graph_resources unquote(Macro.escape(@work_graph_resources))
      @planned_mvp_resources unquote(Macro.escape(@planned_mvp_resources))

      @accepted_software_proving_planned_tables unquote(
                                                  Macro.escape(
                                                    @accepted_software_proving_planned_tables
                                                  )
                                                )

      @accepted_rich_text_planned_tables unquote(Macro.escape(@accepted_rich_text_planned_tables))

      @expected_resource_identities unquote(Macro.escape(@expected_resource_identities))
      @expected_action_capabilities unquote(Macro.escape(@expected_action_capabilities))
      @expected_reference_validations unquote(Macro.escape(@expected_reference_validations))

      @expected_work_graph_relationships unquote(Macro.escape(@expected_work_graph_relationships))

      @expected_work_packets_relationships unquote(
                                             Macro.escape(@expected_work_packets_relationships)
                                           )

      @expected_work_packets_reference_validations unquote(
                                                     Macro.escape(
                                                       @expected_work_packets_reference_validations
                                                     )
                                                   )

      @expected_work_packets_create_defaults unquote(
                                               Macro.escape(
                                                 @expected_work_packets_create_defaults
                                               )
                                             )

      @expected_runs_relationships unquote(Macro.escape(@expected_runs_relationships))

      @expected_runs_reference_validations unquote(
                                             Macro.escape(@expected_runs_reference_validations)
                                           )

      @expected_runs_create_defaults unquote(Macro.escape(@expected_runs_create_defaults))

      @expected_work_graph_internal_modules unquote(
                                              Macro.escape(@expected_work_graph_internal_modules)
                                            )

      @direct_ecto_operation_pattern unquote(Macro.escape(@direct_ecto_operation_pattern))
    end
  end

  def migration_tables do
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

  def expected_domains do
    @expected_resources
    |> Enum.map(fn {_table, {domain, _resource}} -> domain end)
    |> MapSet.new()
  end

  def expected_resource_inventory do
    @expected_resources
    |> Enum.map(fn {table, {domain, resource}} ->
      {table, inspect(domain), inspect(resource)}
    end)
    |> Enum.sort()
  end

  def model_inventory_resources do
    model_inventory_section_resources("## Implemented Table Inventory")
  end

  def expected_planned_resource_inventory do
    @planned_mvp_resources
    |> Enum.map(fn {table, {domain, resource}} ->
      {table, inspect(domain), inspect(resource)}
    end)
    |> Enum.sort()
  end

  def planned_model_inventory_resources do
    model_inventory_section_resources("## Planned MVP Resource Inventory")
  end

  def planned_model_inventory_tables do
    planned_model_inventory_resources()
    |> Enum.map(fn {table, _domain, _resource} -> table end)
    |> MapSet.new()
  end

  def planned_model_inventory_source_references do
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

  def model_inventory_row(table) do
    @model_inventory
    |> File.read!()
    |> String.split("\n")
    |> Enum.find("", &String.starts_with?(&1, "| `#{table}` |"))
  end

  def map_attribute_fields do
    "lib/office_graph/**/*.ex"
    |> Path.wildcard()
    |> Enum.flat_map(&scan_file_for_map_attributes/1)
    |> Enum.sort()
  end

  def scan_file_for_map_attributes(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.reduce({nil, []}, fn line, {current_module, fields} ->
      current_module = module_name(line) || current_module

      fields =
        case Regex.run(~r/^\s*attribute\s+:([a-zA-Z0-9_]+),\s+:map\b/, line) do
          [_, field] when is_binary(current_module) -> ["#{current_module}.#{field}" | fields]
          _other -> fields
        end

      {current_module, fields}
    end)
    |> elem(1)
  end

  def map_field_classification_entries do
    @map_field_classification
    |> File.read!()
    |> markdown_table_entries("Field")
    |> Enum.map(fn entry -> entry |> Map.fetch!("Field") |> unbacktick() end)
    |> Enum.sort()
  end

  def map_field_classification_metadata_errors(markdown) do
    table_metadata_errors(markdown, "Field", [
      "Field",
      "Classification",
      "Current role",
      "API/product posture",
      "Promotion trigger"
    ])
  end

  def format_missing_tables(required_tables, actual_tables) do
    required_tables
    |> MapSet.difference(actual_tables)
    |> MapSet.to_list()
    |> Enum.sort()
    |> Enum.map_join("\n", &"- #{&1}")
  end

  def model_inventory_section_resources(heading) do
    @model_inventory
    |> File.read!()
    |> model_inventory_section_lines(heading)
    |> parse_model_inventory_resource_rows()
  end

  def model_inventory_section_lines(content, heading) do
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

  def parse_model_inventory_resource_rows(lines) do
    lines
    |> Enum.flat_map(fn line ->
      case Regex.run(~r/^\|\s*`([^`]+)`\s*\|\s*`([^`]+)`\s*\|\s*`([^`]+)`\s*\|/, line) do
        [_, table, domain, resource] -> [{table, domain, resource}]
        _ -> []
      end
    end)
    |> Enum.sort()
  end

  def resource_conformance_errors(table, resource) do
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

  def maybe_add_resource_error(errors, _table, _resource, _field, expected, {:ok, expected}) do
    errors
  end

  def maybe_add_resource_error(errors, table, resource, field, expected, {:ok, actual}) do
    [
      "#{table}: #{inspect(resource)} #{field} expected #{inspect(expected)}, got #{inspect(actual)}"
      | errors
    ]
  end

  def maybe_add_resource_error(errors, table, resource, field, expected, {:error, error}) do
    [
      "#{table}: #{inspect(resource)} #{field} expected #{inspect(expected)}, got error #{error}"
      | errors
    ]
  end

  def safe_info(fun) do
    {:ok, fun.()}
  catch
    :error, exception when is_exception(exception) ->
      {:error, Exception.message(exception)}

    kind, reason ->
      {:error, "#{kind}: #{inspect(reason)}"}
  end

  def identity_conformance_errors(resource, identity_name, expectation, identity) do
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

  def normalize_identity_expectation(keys) when is_list(keys), do: %{keys: keys, where: nil}

  def normalize_identity_expectation(expectation) when is_map(expectation) do
    Map.put_new(expectation, :where, nil)
  end

  def maybe_add_identity_key_error(errors, _resource, _identity_name, keys, keys), do: errors

  def maybe_add_identity_key_error(
        errors,
        resource,
        identity_name,
        expected_keys,
        actual_keys
      ) do
    [
      "#{inspect(resource)} identity #{inspect(identity_name)} expected keys #{inspect(expected_keys)}, got #{inspect(actual_keys)}"
      | errors
    ]
  end

  def maybe_add_identity_where_error(errors, _resource, _identity_name, where, where),
    do: errors

  def maybe_add_identity_where_error(
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

  def identity_where(%{where: nil}), do: nil
  def identity_where(%{where: where}), do: inspect(where)

  def registered_domains_for(resource) do
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

  def manual_ecto_schemas do
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

  def work_graph_resources_modules do
    "lib/office_graph/work_graph/resources/*.ex"
    |> Path.wildcard()
    |> Enum.sort()
  end

  def assert_work_graph_resources_are_ash! do
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

  def public_action?(resource, action_name, action_type) do
    resource
    |> Ash.Resource.Info.public_actions()
    |> Enum.any?(&(&1.name == action_name and &1.type == action_type))
  end

  def foundation_read_filter(resource) do
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

  def actions_by_type(resource, action_type) do
    resource
    |> Ash.Resource.Info.actions()
    |> Enum.filter(&(&1.type == action_type))
  end

  def assert_relationship_contracts!(expected_relationships_by_resource) do
    for {resource, expected_relationships} <- expected_relationships_by_resource do
      for {name, {type, destination, source_attribute, destination_attribute}} <-
            expected_relationships do
        relationship = Ash.Resource.Info.relationship(resource, name)

        assert relationship,
               "#{inspect(resource)} must define relationship #{inspect(name)}"

        assert relationship.type == type
        assert relationship.destination == destination
        assert relationship.source_attribute == source_attribute
        assert relationship.destination_attribute == destination_attribute
        refute relationship.public?
      end
    end
  end

  def capability_policy?(resource, action_name, action_type, capability) do
    resource
    |> Ash.Policy.Info.policies()
    |> Enum.filter(&policy_applies_to_action?(&1, action_name, action_type))
    |> Enum.any?(&policy_has_capability?(&1, capability))
  end

  def scope_filter_policy?(resource, action_name, action_type) do
    resource
    |> Ash.Policy.Info.policies()
    |> Enum.filter(&policy_applies_to_action?(&1, action_name, action_type))
    |> Enum.any?(&policy_has_scope_filter?/1)
  end

  def policy_applies_to_action?(
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

  def policy_has_capability?(%Ash.Policy.Policy{policies: checks}, capability) do
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

  def policy_has_scope_filter?(%Ash.Policy.Policy{policies: checks}) do
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

  def scope_filter_expression?(%Ash.Query.BooleanExpression{
        op: :and,
        left: left,
        right: right
      }) do
    [scope_actor_equality_field(left), scope_actor_equality_field(right)]
    |> MapSet.new()
    |> MapSet.equal?(MapSet.new([:organization_id, :workspace_id]))
  end

  def scope_filter_expression?(_expression), do: false

  def scope_actor_equality_field(%Ash.Query.Call{
        name: :==,
        args: [%Ash.Query.Ref{attribute: left_field}, {:_actor, right_field}]
      })
      when left_field == right_field and left_field in [:organization_id, :workspace_id],
      do: left_field

  def scope_actor_equality_field(%Ash.Query.Call{
        name: :==,
        args: [{:_actor, left_field}, %Ash.Query.Ref{attribute: right_field}]
      })
      when left_field == right_field and left_field in [:organization_id, :workspace_id],
      do: left_field

  def scope_actor_equality_field(_expression), do: nil

  def same_scope_reference_validation(%{changes: changes}) do
    Enum.find_value(changes, fn
      %Ash.Resource.Change{change: {ValidateSameScopeReferences, opts}} ->
        Keyword.fetch!(opts, :references)

      _change ->
        nil
    end)
  end

  def fixed_attribute_change(%{changes: changes}, attribute) do
    Enum.find_value(changes, fn
      %Ash.Resource.Change{
        change: {Ash.Resource.Change.SetAttribute, [value: value, attribute: ^attribute]}
      } ->
        value

      _change ->
        nil
    end)
  end

  def action_argument_names(%{arguments: arguments}) do
    Enum.map(arguments, & &1.name)
  end

  def action_change?(%{changes: changes}, change_module) do
    Enum.any?(changes, fn
      %Ash.Resource.Change{change: {^change_module, _opts}} -> true
      _change -> false
    end)
  end

  def session_context(organization_id, workspace_id, capabilities) do
    %SessionContext{
      principal_id: Ecto.UUID.generate(),
      session_id: Ecto.UUID.generate(),
      organization_id: organization_id,
      workspace_id: workspace_id,
      capabilities: MapSet.new(capabilities)
    }
  end

  def scoped_changeset(organization_id, workspace_id) do
    %Ash.Changeset{
      attributes: %{
        organization_id: organization_id,
        workspace_id: workspace_id
      }
    }
  end

  def direct_ecto_operations do
    "lib/office_graph/**/*.ex"
    |> Path.wildcard()
    |> Enum.flat_map(&scan_file_for_direct_ecto_operations/1)
    |> Enum.sort_by(&{&1.path, &1.line, &1.operation})
  end

  def ash_authorization_bypasses do
    "lib/office_graph/**/*.ex"
    |> Path.wildcard()
    |> Enum.flat_map(&scan_file_for_ash_authorization_bypasses/1)
    |> Enum.uniq_by(&{&1.path, &1.function})
    |> Enum.sort_by(&{&1.path, &1.function})
  end

  def ash_api_declaration_files do
    "lib/office_graph/**/*.ex"
    |> Path.wildcard()
    |> Enum.filter(fn path ->
      source = File.read!(path)

      source =~ "AshGraphql.Domain" or source =~ "AshJsonApi.Domain" or
        source =~ "AshGraphql.Resource" or source =~ "AshJsonApi.Resource" or
        Regex.match?(~r/^\s+graphql do$/m, source) or
        Regex.match?(~r/^\s+json_api do$/m, source)
    end)
    |> Enum.sort()
  end

  def scan_file_for_ash_authorization_bypasses(path) do
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

  def manual_api_surfaces do
    graphql_root_surfaces() ++ json_api_route_surfaces() ++ json_serializer_surfaces()
  end

  def graphql_root_surfaces do
    [
      {:query, "lib/office_graph_web/graphql/common/queries.ex"},
      {:query, "lib/office_graph_web/graphql/operator_workflow/queries.ex"},
      {:mutation, "lib/office_graph_web/graphql/operator_commands/mutations.ex"}
    ]
    |> Enum.flat_map(fn {root_kind, path} ->
      graphql_root_surfaces_in_file(root_kind, path)
    end)
  end

  def graphql_root_surfaces_in_file(root_kind, path) do
    if File.exists?(path) do
      path
      |> File.read!()
      |> Code.string_to_quoted!(file: path, columns: true)
      |> graphql_field_declarations()
      |> Enum.map(fn {field_name, line_number} ->
        %{
          id: "graphql.#{root_kind}.#{field_name}",
          type: "GraphQL #{root_kind}",
          path: path,
          line: line_number
        }
      end)
    else
      []
    end
  end

  def graphql_field_declarations(ast) do
    {_ast, declarations} =
      Macro.prewalk(ast, [], fn
        {:field, metadata, [field_name | _arguments]} = node, declarations
        when is_atom(field_name) ->
          {node, [{field_name, Keyword.fetch!(metadata, :line)} | declarations]}

        node, declarations ->
          {node, declarations}
      end)

    declarations
    |> Enum.reverse()
    |> Enum.uniq_by(&elem(&1, 0))
  end

  def remote_function_calls_in_file(path, receiver_alias) do
    ast =
      path
      |> File.read!()
      |> Code.string_to_quoted!(file: path)

    {_ast, calls} =
      Macro.prewalk(ast, [], fn
        {{:., _dot_metadata, [{:__aliases__, _alias_metadata, receiver_parts}, function_name]},
         _call_metadata, arguments} = node,
        calls
        when is_atom(function_name) and is_list(arguments) ->
          if List.last(receiver_parts) == receiver_alias do
            {node, [{function_name, length(arguments)} | calls]}
          else
            {node, calls}
          end

        node, calls ->
          {node, calls}
      end)

    calls |> Enum.reverse() |> Enum.uniq()
  end

  def definitions_inside_using_macro(path) do
    ast =
      path
      |> File.read!()
      |> Code.string_to_quoted!(file: path)

    {_ast, definitions} =
      Macro.prewalk(ast, [], fn
        {:defmacro, _metadata, [{:__using__, _using_metadata, _arguments}, [do: body]]} = node,
        definitions ->
          {_body, using_definitions} =
            Macro.prewalk(body, [], fn
              {kind, _definition_metadata,
               [{function_name, _function_metadata, arguments} | _definition_body]} = child,
              using_definitions
              when kind in [:def, :defp] and is_atom(function_name) ->
                arity = if is_list(arguments), do: length(arguments), else: 0
                {child, [{kind, function_name, arity} | using_definitions]}

              child, using_definitions ->
                {child, using_definitions}
            end)

          {node, Enum.reverse(using_definitions, definitions)}

        node, definitions ->
          {node, definitions}
      end)

    definitions
  end

  def json_api_route_surfaces do
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

  def json_serializer_surfaces do
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

  def modules_in_file(path) do
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

  def api_migration_ledger_entries do
    @api_migration_ledger
    |> File.read!()
    |> markdown_table_entries("Surface ID")
    |> Enum.map(fn entry -> %{id: unbacktick(Map.fetch!(entry, "Surface ID"))} end)
  end

  def api_migration_ledger_approves_surface?(entries, surface) do
    Enum.any?(entries, &(&1.id == surface.id))
  end

  def api_migration_ledger_metadata_errors(ledger) do
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

  def auth_bypass_ledger_entries do
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

  def auth_bypass_ledger_approves_operation?(entries, bypass) do
    Enum.any?(entries, &(&1.path == bypass.path and &1.function == bypass.function))
  end

  def auth_bypass_ledger_metadata_errors(ledger) do
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

  def scan_file_for_direct_ecto_operations(path) do
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

      {current_function, Enum.reverse(line_operations, operations)}
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  def direct_ecto_ledger_entries do
    @architecture_exception_ledger
    |> File.read!()
    |> parse_direct_ecto_ledger_entries()
  end

  def parse_direct_ecto_ledger_entries(ledger) do
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

  def ledger_approves_operation?(entries, operation) do
    Enum.any?(entries, fn entry ->
      entry.path == operation.path and
        entry.function == operation.function and
        entry.operation == operation.operation
    end)
  end

  def direct_ecto_ledger_metadata_errors(ledger) do
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

  def markdown_table_rows(markdown) do
    markdown
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(String.trim_leading(&1), "|"))
    |> Enum.map(&markdown_table_cells/1)
    |> Enum.reject(&markdown_separator_row?/1)
  end

  def markdown_table_entries(markdown, required_header) do
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

  def table_metadata_errors(markdown, required_header, required_headers) do
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

  def ledger_section(markdown, heading) do
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

  def unbacktick(value) do
    value
    |> String.trim()
    |> String.trim_leading("`")
    |> String.trim_trailing("`")
  end

  def backticked_values(value) do
    ~r/`([^`]+)`/
    |> Regex.scan(value, capture: :all_but_first)
    |> List.flatten()
  end

  def markdown_table_cells(line) do
    line
    |> String.trim()
    |> String.trim_leading("|")
    |> String.trim_trailing("|")
    |> String.split("|")
    |> Enum.map(&String.trim/1)
  end

  def markdown_separator_row?(cells) do
    Enum.all?(cells, &String.match?(&1, ~r/^:?-{3,}:?$/))
  end

  def table_cell(row, header, header_name) do
    case Enum.find_index(header, &(&1 == header_name)) do
      nil -> ""
      index -> Enum.at(row, index, "")
    end
  end

  def blank?(value), do: String.trim(to_string(value)) == ""

  def ledger_tuple_values(line) do
    tuple_values =
      ~r/`\{\s*([^`,{}]+)\s*,\s*((?:Repo|Ecto\.Multi|Ecto\.Adapters\.SQL)\.[^`,{}]+)\s*\}`/
      |> Regex.scan(line, capture: :all_but_first)
      |> Enum.map(fn [function, operation] ->
        {String.trim(function), String.trim(operation)}
      end)

    tuple_values ++ ledger_row_tuple_values(line)
  end

  def ledger_row_tuple_values(line) do
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

  def single_backticked_value(cell) do
    case Regex.scan(~r/`([^`]+)`/, cell, capture: :all_but_first) do
      [[value]] -> {:ok, value}
      _ -> :error
    end
  end

  def single_operation_value(cell) do
    case Regex.scan(
           ~r/`((?:Repo|Ecto\.Multi|Ecto\.Adapters\.SQL)\.[^`]+)`/,
           cell,
           capture: :all_but_first
         ) do
      [[value]] -> {:ok, value}
      _ -> :error
    end
  end

  def normalize_direct_ecto_operation(receiver, operation)
      when receiver in ["Multi", "Ecto.Multi"] do
    "Ecto.Multi.#{operation}"
  end

  def normalize_direct_ecto_operation("Ecto.Adapters.SQL", operation) do
    "Ecto.Adapters.SQL.#{operation}"
  end

  def normalize_direct_ecto_operation(_receiver, operation) do
    "Repo.#{operation}"
  end

  def module_name(line) do
    case Regex.run(~r/^\s*defmodule\s+([A-Za-z0-9_.]+)\s+do/, line) do
      [_, name] -> name
      _ -> nil
    end
  end

  def function_name(line) do
    case Regex.run(~r/^\s*defp?\s+([a-zA-Z0-9_!?]+)\((.*)\)(?:\s+when\b.*)?\s*(?:do|,)/, line) do
      [_, name, args] -> "#{name}/#{arity(args)}"
      _ -> nil
    end
  end

  def arity(args) do
    args
    |> String.trim()
    |> case do
      "" -> 0
      args -> args |> String.split(",") |> length()
    end
  end

  def function_body_after(source, signature) do
    case String.split(source, signature, parts: 2) do
      [_before, after_signature] -> after_signature
      [_source] -> flunk("Expected source to include #{signature}")
    end
  end

  def format_modules(modules) do
    modules
    |> Enum.map_join("\n", &"  #{inspect(&1)}")
  end

  def format_errors(errors) do
    Enum.map_join(errors, "\n", &"  #{&1}")
  end

  def format_ecto_schemas(schemas) do
    schemas
    |> Enum.map_join("\n", fn schema ->
      "  #{schema.path}:#{schema.line} #{schema.module} #{schema.source}"
    end)
  end

  def format_direct_operations(operations) do
    operations
    |> Enum.map_join("\n", fn operation ->
      "  #{operation.path}:#{operation.line} #{operation.function || "<module>"} #{operation.operation} #{operation.source}"
    end)
  end

  def format_auth_bypasses(bypasses) do
    bypasses
    |> Enum.map_join("\n", fn bypass ->
      "  #{bypass.path}:#{bypass.line} #{bypass.function || "<module>"} #{bypass.source}"
    end)
  end

  def format_api_surfaces(surfaces) do
    surfaces
    |> Enum.map_join("\n", fn surface ->
      "  #{surface.path}:#{surface.line} #{surface.id} #{surface.type}"
    end)
  end
end
