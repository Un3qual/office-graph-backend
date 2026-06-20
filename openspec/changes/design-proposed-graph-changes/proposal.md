## Why

Agents, generated UI, ingestion adapters, and humans need a safe way to suggest
graph mutations without writing truth tables directly. This change defines the
shape, validation, authorization, and application semantics for proposed graph
changes before backend code generation.

## What Changes

- Define proposed graph change shape for structured graph/domain mutations.
- Define validation against target resource, operation, schema, lifecycle,
  idempotency, and domain constraints.
- Define authorization and approval requirements for proposed changes.
- Define application through domain actions that produce normal revisions,
  audit records, operation correlation, and evidence.
- This change is design-only and does not implement runtime, UI, API, jobs,
  migrations, or graph mutations.

## Capabilities

### New Capabilities

- `proposed-change-shape`: durable shape for proposed graph/domain mutations.
- `proposed-change-validation`: validation rules before approval/application.
- `proposed-change-authorization`: permission, approval, sensitivity, and
  agent authority rules.
- `proposed-change-application`: domain-action application and trace outputs.

### Modified Capabilities

- None. No durable specs have been archived yet.

## Impact

- Affects future agent runtime, generated UI, ingestion, work packets,
  runs/verification, graph mutations, and audit/revision integration.
- Creates no application code.
