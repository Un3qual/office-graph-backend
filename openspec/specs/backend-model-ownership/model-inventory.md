# Resource Ownership Inventory

## Implemented Table Inventory

Derived from committed migrations; expected count: 68 tables.

| Table | Owning domain | Canonical Ash resource |
| --- | --- | --- |
| `organizations` | `OfficeGraph.Tenancy.Domain` | `OfficeGraph.Tenancy.Organization` |
| `workspaces` | `OfficeGraph.Tenancy.Domain` | `OfficeGraph.Tenancy.Workspace` |
| `initiatives` | `OfficeGraph.Tenancy.Domain` | `OfficeGraph.Tenancy.Initiative` |
| `workstreams` | `OfficeGraph.Tenancy.Domain` | `OfficeGraph.Tenancy.Workstream` |
| `principals` | `OfficeGraph.Identity.Domain` | `OfficeGraph.Identity.Principal` |
| `principal_profiles` | `OfficeGraph.Identity.Domain` | `OfficeGraph.Identity.PrincipalProfile` |
| `credentials` | `OfficeGraph.Identity.Domain` | `OfficeGraph.Identity.Credential` |
| `sessions` | `OfficeGraph.Identity.Domain` | `OfficeGraph.Identity.Session` |
| `capabilities` | `OfficeGraph.Authorization.Domain` | `OfficeGraph.Authorization.Capability` |
| `roles` | `OfficeGraph.Authorization.Domain` | `OfficeGraph.Authorization.Role` |
| `role_capabilities` | `OfficeGraph.Authorization.Domain` | `OfficeGraph.Authorization.RoleCapability` |
| `role_assignments` | `OfficeGraph.Authorization.Domain` | `OfficeGraph.Authorization.RoleAssignment` |
| `policy_bundles` | `OfficeGraph.Authorization.Domain` | `OfficeGraph.Authorization.PolicyBundle` |
| `authorization_decisions` | `OfficeGraph.Authorization.Domain` | `OfficeGraph.Authorization.AuthorizationDecision` |
| `operation_correlations` | `OfficeGraph.Operations.Domain` | `OfficeGraph.Operations.OperationCorrelation` |
| `domain_events` | `OfficeGraph.DurableDelivery.Domain` | `OfficeGraph.DurableDelivery.DomainEvent` |
| `audit_records` | `OfficeGraph.Audit.Domain` | `OfficeGraph.Audit.AuditRecord` |
| `revisions` | `OfficeGraph.Revisions.Domain` | `OfficeGraph.Revisions.Revision` |
| `tombstones` | `OfficeGraph.Tombstones.Domain` | `OfficeGraph.Tombstones.Tombstone` |
| `documents` | `OfficeGraph.Content.Domain` | `OfficeGraph.Content.Document` |
| `document_blocks` | `OfficeGraph.Content.Domain` | `OfficeGraph.Content.DocumentBlock` |
| `document_marks` | `OfficeGraph.Content.Domain` | `OfficeGraph.Content.DocumentMark` |
| `document_references` | `OfficeGraph.Content.Domain` | `OfficeGraph.Content.DocumentReference` |
| `document_revisions` | `OfficeGraph.Content.Domain` | `OfficeGraph.Content.DocumentRevision` |
| `external_sources` | `OfficeGraph.Integrations.Domain` | `OfficeGraph.Integrations.ExternalSource` |
| `raw_archives` | `OfficeGraph.Integrations.Domain` | `OfficeGraph.Integrations.RawArchive` |
| `normalized_intake_events` | `OfficeGraph.Integrations.Domain` | `OfficeGraph.Integrations.NormalizedIntakeEvent` |
| `integration_credentials` | `OfficeGraph.Integrations.Domain` | `OfficeGraph.Integrations.IntegrationCredential` |
| `external_references` | `OfficeGraph.ExternalRefs.Domain` | `OfficeGraph.ExternalRefs.ExternalReference` |
| `repositories` | `OfficeGraph.SoftwareProving.Domain` | `OfficeGraph.SoftwareProving.Repository` |
| `repository_refs` | `OfficeGraph.SoftwareProving.Domain` | `OfficeGraph.SoftwareProving.RepositoryRef` |
| `commits` | `OfficeGraph.SoftwareProving.Domain` | `OfficeGraph.SoftwareProving.Commit` |
| `pull_requests` | `OfficeGraph.SoftwareProving.Domain` | `OfficeGraph.SoftwareProving.PullRequest` |
| `review_threads` | `OfficeGraph.SoftwareProving.Domain` | `OfficeGraph.SoftwareProving.ReviewThread` |
| `review_comments` | `OfficeGraph.SoftwareProving.Domain` | `OfficeGraph.SoftwareProving.ReviewComment` |
| `check_runs` | `OfficeGraph.SoftwareProving.Domain` | `OfficeGraph.SoftwareProving.CheckRun` |
| `github_repositories` | `OfficeGraph.SoftwareProving.Domain` | `OfficeGraph.SoftwareProving.GitHub.RepositoryExtension` |
| `github_pull_requests` | `OfficeGraph.SoftwareProving.Domain` | `OfficeGraph.SoftwareProving.GitHub.PullRequestExtension` |
| `github_review_threads` | `OfficeGraph.SoftwareProving.Domain` | `OfficeGraph.SoftwareProving.GitHub.ReviewThreadExtension` |
| `github_review_comments` | `OfficeGraph.SoftwareProving.Domain` | `OfficeGraph.SoftwareProving.GitHub.ReviewCommentExtension` |
| `github_check_runs` | `OfficeGraph.SoftwareProving.Domain` | `OfficeGraph.SoftwareProving.GitHub.CheckRunExtension` |
| `github_installations` | `OfficeGraph.GitHubIntegration.Domain` | `OfficeGraph.GitHubIntegration.Installation` |
| `github_permission_snapshots` | `OfficeGraph.GitHubIntegration.Domain` | `OfficeGraph.GitHubIntegration.PermissionSnapshot` |
| `github_permission_entries` | `OfficeGraph.GitHubIntegration.Domain` | `OfficeGraph.GitHubIntegration.PermissionEntry` |
| `github_installation_credentials` | `OfficeGraph.GitHubIntegration.Domain` | `OfficeGraph.GitHubIntegration.InstallationCredential` |
| `github_sync_outcomes` | `OfficeGraph.GitHubIntegration.Domain` | `OfficeGraph.GitHubIntegration.SyncOutcome` |
| `github_outbound_actions` | `OfficeGraph.GitHubIntegration.Domain` | `OfficeGraph.GitHubIntegration.OutboundAction` |
| `graph_items` | `OfficeGraph.WorkGraph.Domain` | `OfficeGraph.WorkGraph.GraphItem` |
| `relationship_definitions` | `OfficeGraph.WorkGraph.Domain` | `OfficeGraph.WorkGraph.RelationshipDefinition` |
| `relationship_endpoint_rules` | `OfficeGraph.WorkGraph.Domain` | `OfficeGraph.WorkGraph.RelationshipEndpointRule` |
| `graph_relationships` | `OfficeGraph.WorkGraph.Domain` | `OfficeGraph.WorkGraph.GraphRelationship` |
| `signals` | `OfficeGraph.WorkGraph.Domain` | `OfficeGraph.WorkGraph.Signal` |
| `tasks` | `OfficeGraph.WorkGraph.Domain` | `OfficeGraph.WorkGraph.Task` |
| `review_findings` | `OfficeGraph.WorkGraph.Domain` | `OfficeGraph.WorkGraph.ReviewFinding` |
| `verification_checks` | `OfficeGraph.WorkGraph.Domain` | `OfficeGraph.WorkGraph.VerificationCheck` |
| `artifacts` | `OfficeGraph.WorkGraph.Domain` | `OfficeGraph.WorkGraph.Artifact` |
| `evidence_candidates` | `OfficeGraph.WorkGraph.Domain` | `OfficeGraph.WorkGraph.EvidenceCandidate` |
| `evidence_items` | `OfficeGraph.WorkGraph.Domain` | `OfficeGraph.WorkGraph.EvidenceItem` |
| `verification_results` | `OfficeGraph.WorkGraph.Domain` | `OfficeGraph.WorkGraph.VerificationResult` |
| `work_packets` | `OfficeGraph.WorkPackets.Domain` | `OfficeGraph.WorkPackets.WorkPacket` |
| `work_packet_versions` | `OfficeGraph.WorkPackets.Domain` | `OfficeGraph.WorkPackets.WorkPacketVersion` |
| `work_packet_version_sources` | `OfficeGraph.WorkPackets.Domain` | `OfficeGraph.WorkPackets.WorkPacketSourceReference` |
| `work_packet_version_required_checks` | `OfficeGraph.WorkPackets.Domain` | `OfficeGraph.WorkPackets.WorkPacketRequiredCheck` |
| `runs` | `OfficeGraph.Runs.Domain` | `OfficeGraph.Runs.Run` |
| `run_required_checks` | `OfficeGraph.Runs.Domain` | `OfficeGraph.Runs.RunRequiredCheck` |
| `execution_observations` | `OfficeGraph.Runs.Domain` | `OfficeGraph.Runs.ExecutionObservation` |
| `run_events` | `OfficeGraph.Runs.Domain` | `OfficeGraph.Runs.RunEvent` |
| `proposed_graph_changes` | `OfficeGraph.ProposedChanges.Domain` | `OfficeGraph.ProposedChanges.ProposedGraphChange` |

## Planned MVP Resource Inventory

These resources are accepted or active design commitments that are not yet
implemented in committed migrations. They remain separate from the implemented
68-table inventory so the architecture gate does not treat the walking skeleton
as the complete MVP persistence model.

| Table | Owning domain | Canonical Ash resource | Source | Implementation status |
| --- | --- | --- | --- | --- |
| `requirements` | `OfficeGraph.WorkGraph.Domain` | `OfficeGraph.WorkGraph.Requirement` | `openspec/specs/graph-items/spec.md`; `openspec/specs/mvp-persistence-inventory/spec.md` | Planned - not implemented |
| `questions` | `OfficeGraph.WorkGraph.Domain` | `OfficeGraph.WorkGraph.Question` | `openspec/specs/graph-items/spec.md`; `openspec/specs/mvp-persistence-inventory/spec.md` | Planned - not implemented |
| `decisions` | `OfficeGraph.WorkGraph.Domain` | `OfficeGraph.WorkGraph.Decision` | `openspec/specs/graph-items/spec.md`; `openspec/specs/mvp-persistence-inventory/spec.md` | Planned - not implemented |
| `conversations` | `OfficeGraph.NodeConversations.Domain` | `OfficeGraph.NodeConversations.Conversation` | `openspec/specs/graph-items/spec.md`; `openspec/specs/node-conversations/spec.md`; `openspec/specs/mvp-persistence-inventory/spec.md` | Planned - not implemented |
| `conversation_messages` | `OfficeGraph.NodeConversations.Domain` | `OfficeGraph.NodeConversations.ConversationMessage` | `openspec/specs/graph-items/spec.md`; `openspec/specs/node-conversations/spec.md`; `openspec/specs/mvp-persistence-inventory/spec.md` | Planned - not implemented |
| `issues` | `OfficeGraph.SoftwareProving.Domain` | `OfficeGraph.SoftwareProving.Issue` | `openspec/specs/mvp-persistence-inventory/spec.md`; `openspec/specs/domain-attachments/spec.md` | Planned - not implemented |
| `observability_issues` | `OfficeGraph.SoftwareProving.Domain` | `OfficeGraph.SoftwareProving.ObservabilityIssue` | `openspec/specs/mvp-persistence-inventory/spec.md`; `openspec/specs/domain-attachments/spec.md` | Planned - not implemented |
| `observability_events` | `OfficeGraph.SoftwareProving.Domain` | `OfficeGraph.SoftwareProving.ObservabilityEvent` | `openspec/specs/mvp-persistence-inventory/spec.md`; `openspec/specs/domain-attachments/spec.md` | Planned - not implemented |
| `rich_text_documents` | `OfficeGraph.Content.Domain` | `OfficeGraph.Content.RichTextDocument` | `openspec/specs/portable-rich-text-persistence/spec.md`; `openspec/specs/mvp-persistence-inventory/spec.md` | Planned - not implemented |
| `rich_text_blocks` | `OfficeGraph.Content.Domain` | `OfficeGraph.Content.RichTextBlock` | `openspec/specs/portable-rich-text-persistence/spec.md`; `openspec/specs/mvp-persistence-inventory/spec.md` | Planned - not implemented |
| `rich_text_block_versions` | `OfficeGraph.Content.Domain` | `OfficeGraph.Content.RichTextBlockVersion` | `openspec/specs/portable-rich-text-persistence/spec.md` | Planned - not implemented |
| `rich_text_spans` | `OfficeGraph.Content.Domain` | `OfficeGraph.Content.RichTextSpan` | `openspec/specs/portable-rich-text-persistence/spec.md` | Planned - not implemented |
| `rich_text_mark_types` | `OfficeGraph.Content.Domain` | `OfficeGraph.Content.RichTextMarkType` | `openspec/specs/portable-rich-text-persistence/spec.md` | Planned - not implemented |
| `rich_text_marks` | `OfficeGraph.Content.Domain` | `OfficeGraph.Content.RichTextMark` | `openspec/specs/portable-rich-text-persistence/spec.md` | Planned - not implemented |
| `rich_text_references` | `OfficeGraph.Content.Domain` | `OfficeGraph.Content.RichTextReference` | `openspec/specs/portable-rich-text-persistence/spec.md` | Planned - not implemented |
| `rich_text_document_revisions` | `OfficeGraph.Content.Domain` | `OfficeGraph.Content.RichTextDocumentRevision` | `openspec/specs/portable-rich-text-persistence/spec.md`; `openspec/specs/mvp-persistence-inventory/spec.md` | Planned - not implemented |
| `rich_text_quote_snapshots` | `OfficeGraph.Content.Domain` | `OfficeGraph.Content.RichTextQuoteSnapshot` | `openspec/specs/portable-rich-text-persistence/spec.md`; `openspec/specs/mvp-persistence-inventory/spec.md` | Planned - not implemented; owns pinned snapshot metadata, source authorization context, and quote freshness state |
| `rich_text_quote_selection_segments` | `OfficeGraph.Content.Domain` | `OfficeGraph.Content.RichTextQuoteSelectionSegment` | `openspec/specs/portable-rich-text-persistence/spec.md`; `openspec/specs/mvp-persistence-inventory/spec.md` | Planned - not implemented |
| `rich_text_derived_plain_texts` | `OfficeGraph.Content.Domain` | `OfficeGraph.Content.RichTextDerivedPlainText` | `openspec/specs/portable-rich-text-persistence/spec.md` | Planned - not implemented; owns revision-tied derived plain text for search, fallback display, and agent context |
