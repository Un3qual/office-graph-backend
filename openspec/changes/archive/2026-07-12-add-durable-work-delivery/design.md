## Context

Office Graph already has synchronous domain commands, operation correlation,
Phoenix PubSub supervision, projection reads, and stable command identities.
It has no durable job dependency, domain-event store, or application-owned
realtime contract. Provider ingestion and internal-agent execution both depend
on these primitives, while missed realtime notifications must remain harmless
because Postgres and authorized projections are authoritative.

This implementation is added to the existing PR at the user's direction even
though the program originally placed it in a separate PR. The capability still
keeps one active OpenSpec owner and independently reviewable commits.

## Goals / Non-Goals

**Goals:**

- Make Oban the only durable async execution mechanism and keep job insertion
  transactionally consistent with the command that requests work.
- Persist small typed domain-event facts with organization, workspace,
  operation, subject, version, event kind, causation, and delivery state.
- Deliver one authorized projection-invalidation envelope after commit and
  require consumers to refetch authoritative projections.
- Classify retryable and terminal worker failures consistently, expose terminal
  job state through a scoped read, and emit useful telemetry.
- Exercise the boundary through a deterministic worker and one existing
  operator command without adding a provider or model runtime.

**Non-Goals:**

- Do not implement GitHub, webhook, sync, provider, model, or agent behavior.
- Do not make PubSub messages durable state or send record bodies over realtime.
- Do not add a general event bus, arbitrary payload JSON, Kafka, RabbitMQ,
  Redis, or another queue.
- Do not add frontend socket ownership or broad notification UI in this slice.

## Decisions

### 1. Oban jobs and domain events commit in the owning transaction

Add Oban with Postgres-backed queues and insert a dispatch job through
`Oban.insert/2` using the application's Repo while the owning domain transaction
is open. The same transaction creates a typed `domain_events` row. Rollback
therefore removes both the product write and its requested delivery; commit
leaves a durable job that survives process restart.

Direct `Task`, process mailboxes, and post-transaction best-effort enqueue were
rejected because a crash can lose work. A polling-only outbox was rejected for
this slice because Oban already supplies the durable claim/retry mechanism and
can reference the event row by id.

### 2. Domain events are typed facts, not generic payload documents

Each event stores event kind, subject kind and id, optional subject version,
organization, optional workspace, operation, optional causation event,
delivery state, attempt timestamps, and a safe terminal reason. The event does
not copy product state. Event kinds and subject kinds use constrained strings
so later domains can extend the vocabulary without a polymorphic foreign-key
model or JSON payload becoming product truth.

The initial event is `manual_intake.accepted` for a normalized intake event.
The command transaction creates it only for the first accepted intake, not for
idempotent replay, and enqueues one unique dispatch job.

### 3. One worker boundary owns failure classification

`OfficeGraph.DurableDelivery.Worker` is the common Oban worker contract. Worker
implementations return success, `{:error, {:retryable, reason}}`, or
`{:error, {:terminal, reason}}`. The wrapper maps retryable failures to Oban
retry behavior and terminal failures to cancellation while recording a safe
event failure. Unexpected exceptions remain Oban failures and retain normal
stack traces in server logs, never in product-facing event fields.

Job uniqueness is based on worker, event id, and queue. The dispatcher is
idempotent: already-delivered events return success without broadcasting again.

### 4. Realtime delivery sends only authorized invalidation hints

`ProjectionInvalidation` is a typed struct derived from a domain event. Topics
are organization and workspace scoped. Subscription requires a current
`RequestSession`; delivery revalidates scope through the authorization boundary
before registering the subscriber. The envelope contains event id, event kind,
subject kind/id/version, operation id, and scope ids—never the subject body or
hidden policy details.

The dispatcher publishes through Phoenix PubSub only after loading the durable
event. A missed message is safe because clients use the identity/version hint
to refetch GraphQL projections. Absinthe and Channel adapters added later must
consume this same contract rather than inventing transport-specific semantics.

### 5. Terminal work is observable through scoped reads and telemetry

The durable-delivery context exposes a bounded terminal-job read filtered by
organization and workspace ids embedded in job args. It returns stable job
identity, worker, queue, state, attempt counts, safe reason, and timestamps;
raw args, stack traces, and other tenants are never returned.

Telemetry attaches to Oban job lifecycle events and reports queue, worker,
state, and duration measurements without tenant identifiers or job arguments.
The existing telemetry supervisor owns handler attachment and metrics.

## Risks / Trade-offs

- **Event and job creation touches existing command transactions** → Keep one
  narrow `record_and_enqueue/2` API and prove rollback plus replay behavior.
- **PubSub authorization can become stale after subscription** → Deliver only
  non-sensitive invalidation identities and require a fresh authorized read;
  later long-lived transports must reauthorize on reconnect and policy change.
- **Terminal reasons can leak internals** → Persist only classified safe codes
  from a fixed vocabulary and keep exceptions in server telemetry/logs.
- **The event table can grow quickly** → Add scope, operation, subject, status,
  and occurred-time indexes; retain a future partitioning path without adding
  partitioning prematurely.
- **Oban test modes can hide production behavior** → Use manual mode for
  deterministic worker assertions plus an integration test that commits jobs
  through the real Repo transaction.

## Migration Plan

1. Add Oban configuration and its standard jobs migration plus the typed
   domain-events migration.
2. Add the durable-delivery context, event resource, worker contract, test
   worker, terminal-job projection, and focused tests.
3. Add the authorized projection-invalidation subscriber and dispatcher.
4. Record and enqueue the first event inside manual-intake acceptance and prove
   replay and rollback behavior.
5. Run migrations, strict OpenSpec validation, focused tests, and `mix verify`.

Rollback first stops Oban queues, then reverts the consumer, event migration,
and Oban migration. Dropping event/job tables is allowed only while the product
remains unreleased and after confirming no pending work needs preservation.

## Open Questions

None. Frontend socket ownership, Absinthe subscription fields, provider workers,
and agent workers remain later consumers of this contract.
