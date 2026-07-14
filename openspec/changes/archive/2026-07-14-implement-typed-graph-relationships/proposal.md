## Why

Office Graph currently stores graph edges with an unrestricted string and two
endpoints, so it cannot enforce the accepted relationship vocabulary, endpoint
compatibility, lifecycle, provenance, scope, or cycle rules. GitHub ingestion
and internal agents both need a stable typed relationship contract before they
can add external context or propose graph links safely.

## What Changes

- Add a relational, migration-owned relationship definition and endpoint-rule
  registry for the accepted MVP vocabulary.
- Add named WorkGraph commands for relationship creation, supersession,
  archival, and eligible restoration with transactional validation.
- Add explicit organization/governing-workspace scope, lifecycle, operation,
  actor, validity, and optional run/integration-event provenance to relationship
  persistence.
- Enforce type-specific endpoint compatibility, uniqueness, authorization, and
  cycle rules without allowing graph edges to grant target access.
- **BREAKING** Replace the unreleased `produced_task`, `has_review_finding`,
  `requires_verification`, `has_evidence`, and `references_artifact` values with
  canonical `generated_from`, `review_finding_for`, `requires_check`, and
  `evidenced_by` relationships, reversing legacy endpoints where required.
- Update GraphQL, JSON API, projections, architecture ledgers, and query-count
  gates to use canonical relationship definitions and lifecycle.

## Capabilities

### New Capabilities

- `typed-relationship-registry`: Owns relational relationship definitions,
  endpoint compatibility rules, migration-installed vocabulary, and registry
  lookup behavior.

### Modified Capabilities

- `graph-relationships`: Implements typed relationship commands, lifecycle,
  provenance, scope, authorization, and cycle enforcement.
- `graph-storage-contract`: Requires persisted edges to reference canonical
  definitions and explicit scope/provenance fields.

## Impact

- Adds Ash resources and migrations for relationship definitions and endpoint
  rules, and changes the existing `graph_relationships` table and resource.
- Changes WorkGraph proposal application, projection assembly, GraphQL schema,
  JSON API output, generated artifacts, and relationship-focused tests.
- Updates the existing backend ownership and API ledgers without changing their
  general requirements.
- Requires a deterministic data migration for the existing unreleased edge
  vocabulary and concurrency tests for cycle enforcement.
- Becomes the required parent change for GitHub integration and the internal
  agent runtime.
