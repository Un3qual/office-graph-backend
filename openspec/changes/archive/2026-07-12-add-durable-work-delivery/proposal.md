## Why

Office Graph commands now complete the operator workflow synchronously, but
there is no durable owner for retryable follow-up work and no typed delivery
boundary for notifying authorized clients after committed state changes. The
next product slices need a Postgres-backed job and event foundation before
provider processing or agent execution can be added safely.

## What Changes

- Add Oban as the sole durable background-work owner, configured with explicit
  queues, test isolation, idempotent job identities, bounded retry behavior,
  telemetry, and operator-readable terminal failure state.
- Add typed, tenant-scoped domain-event records written transactionally with
  the command they describe and dispatched only after durable commit.
- Add one projection-invalidation envelope that carries resource identity,
  scope, version, and operation hints while requiring subscribers to refetch
  authoritative projections.
- Add an authorization-filtered PubSub delivery boundary and a real operator
  command consumer so the infrastructure is exercised by product behavior.
- Add a deterministic test worker path that proves success, retryable failure,
  terminal failure, uniqueness, and dead-job visibility without a provider or
  model integration.

## Capabilities

### New Capabilities

- `durable-work-delivery`: Defines durable job ownership, typed domain events,
  retry classification, telemetry, terminal failure visibility, and delivery
  idempotency.

### Modified Capabilities

- `realtime-delivery`: Adds the concrete authorized projection-invalidation
  envelope and post-commit delivery/reconciliation behavior.
- `shared-operation-contracts`: Requires transaction-safe event and job
  creation to retain operation and causation correlation.
- `entrypoint-boundary-contracts`: Defines thin, fail-closed Oban worker and
  realtime subscriber entrypoint behavior.

## Impact

- Adds Oban runtime and test dependencies, configuration, supervision, and
  Postgres migrations.
- Adds a durable-delivery boundary under `OfficeGraph` plus narrow worker and
  projection-invalidation modules.
- Adds event creation to an existing operator command transaction and PubSub
  delivery after commit without changing command result envelopes.
- Adds focused persistence, retry, authorization, telemetry, and integration
  tests; normal verification continues through the project Nix shell.
