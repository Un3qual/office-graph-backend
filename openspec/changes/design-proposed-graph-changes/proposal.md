## Why

Agents, generated UI, ingestion adapters, and humans need a safe way to suggest
domain mutations without writing truth tables directly. This change defines the
shape, validation, authorization, and application semantics for change
proposals before backend code generation.

## What Changes

- Define change proposal shape for structured domain-action mutation requests.
- Define validation against target resource, operation, schema, lifecycle,
  idempotency, and domain constraints.
- Define authorization and approval requirements for change proposals.
- Define application through domain actions that produce normal revisions,
  audit records, operation correlation, and evidence.
- This change is design-only and does not implement runtime, UI, API, jobs,
  migrations, or graph mutations.

## Capabilities

### New Capabilities

- `change-proposal-shape`: durable shape for proposed domain-action mutation
  requests.
- `change-proposal-validation`: validation rules before approval/application.
- `change-proposal-authorization`: permission, approval, sensitivity, and
  agent authority rules.
- `change-proposal-application`: domain-action application and trace outputs.

### Modified Capabilities

- None. No durable specs have been archived yet.

## Impact

- Affects future agent runtime, generated UI, ingestion, work packets,
  runs/verification, graph mutations, and audit/revision integration.
- Creates no application code.
