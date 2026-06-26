## Why

The walking skeleton starts from an incoming signal, but the current plan does
not yet define how manual or external events become normalized Office Graph
signals without coupling the first demo to GitHub or Sentry webhooks. This
change defines a manual-first ingestion and integration contract before
backend code generation.

## What Changes

- Make manual pasted intake the first adapter for the walking skeleton.
- Define raw payload archives, normalized external events, signals,
  provider-neutral resources, review findings, evidence, and sync events as
  distinct records.
- Define idempotency, replay, duplicate handling, out-of-order behavior,
  retries, and operation-correlation linkage.
- Define provider adapter outputs and credential/webhook principal inputs.
- Define a sync state machine for external sources and later webhook/API
  integrations.
- This change is design-only and does not implement integrations, webhooks,
  jobs, migrations, API endpoints, or UI.

## Capabilities

### New Capabilities

- `manual-intake-adapter`: first adapter for pasted/manual messy signals.
- `external-event-normalization`: raw archive, normalized event, signal,
  resource, finding, evidence, and sync-event boundaries.
- `idempotency-and-replay`: source identity, replay identity, duplicate and
  out-of-order behavior, retry, and operation correlation.
- `provider-adapter-contract`: typed provider-neutral adapter output contract.
- `sync-state-machine`: lifecycle for external source ingestion and replay.

### Modified Capabilities

- None. No durable specs have been archived yet.

## Impact

- Affects OpenSpec planning for ingestion, integration adapters, raw archives,
  external references, manual intake, and future webhook/API imports.
- Feeds persistence, code organization, change proposals, work packets,
  runs/verification, and future API/UI work.
- Creates no application code.
