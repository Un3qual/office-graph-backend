## Why

The all-runs and product-native runtime batch exposed several upgrade, dispatch,
recovery, and pagination edge cases during local review. The affected contracts
also need a few ambiguities removed so the implementation and durable specs agree
before the batch is merged.

## What Changes

- Reconcile the canonical `run-review` definition for both upgraded and fresh
  databases with an idempotent forward migration.
- Prevent a cancelled or superseded execution claim from reaching the adapter.
- Recover orphaned Oban execution jobs without creating parallel retry jobs.
- Fetch subsequent run-activity pages with a focused Relay query.
- Tighten generated API coverage and clarify selection, replay, verification,
  approval, routing, and failure-classification contracts.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `agent-definitions`: Define upgrade-safe reconciliation of the canonical
  `run-review` definition.
- `agent-executions`: Clarify pre-dispatch cancellation, orphan recovery,
  output-routing idempotency, and permanent versus transient failures.
- `frontend-architecture`: Require focused continuation queries for independently
  paginated run activity.
- `packet-workspace`: Define opaque URL identifiers and default-versus-explicit
  selection behavior across pagination.
- `work-runs`: Clarify when a failed child execution affects parent verification.
- `verification-evidence`: Define replay behavior across candidate and observation
  outputs.
- `agent-approval-requests`: Define same-input approval decision replay.

## Impact

The change affects agent-runtime migrations and dispatch, Oban configuration,
run-detail Relay queries and generated artifacts, focused backend/frontend tests,
and the listed durable specifications. It does not add an OpenSpec product
feature or change public command shapes.
