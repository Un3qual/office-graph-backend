# Resource Ownership Inventory

Derived from committed migrations; expected count: 40 tables.

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
| `external_references` | `OfficeGraph.ExternalRefs.Domain` | `OfficeGraph.ExternalRefs.ExternalReference` |
| `graph_items` | `OfficeGraph.WorkGraph.Domain` | `OfficeGraph.WorkGraph.GraphItem` |
| `graph_relationships` | `OfficeGraph.WorkGraph.Domain` | `OfficeGraph.WorkGraph.GraphRelationship` |
| `signals` | `OfficeGraph.WorkGraph.Domain` | `OfficeGraph.WorkGraph.Signal` |
| `tasks` | `OfficeGraph.WorkGraph.Domain` | `OfficeGraph.WorkGraph.Task` |
| `review_findings` | `OfficeGraph.WorkGraph.Domain` | `OfficeGraph.WorkGraph.ReviewFinding` |
| `verification_checks` | `OfficeGraph.WorkGraph.Domain` | `OfficeGraph.WorkGraph.VerificationCheck` |
| `artifacts` | `OfficeGraph.WorkGraph.Domain` | `OfficeGraph.WorkGraph.Artifact` |
| `evidence_items` | `OfficeGraph.WorkGraph.Domain` | `OfficeGraph.WorkGraph.EvidenceItem` |
| `verification_results` | `OfficeGraph.WorkGraph.Domain` | `OfficeGraph.WorkGraph.VerificationResult` |
| `work_packets` | `OfficeGraph.WorkPackets.Domain` | `OfficeGraph.WorkPackets.WorkPacket` |
| `runs` | `OfficeGraph.Runs.Domain` | `OfficeGraph.Runs.Run` |
| `run_events` | `OfficeGraph.Runs.Domain` | `OfficeGraph.Runs.RunEvent` |
| `proposed_graph_changes` | `OfficeGraph.ProposedChanges.Domain` | `OfficeGraph.ProposedChanges.ProposedGraphChange` |
