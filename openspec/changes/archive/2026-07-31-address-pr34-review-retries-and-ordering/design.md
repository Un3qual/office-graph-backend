## Context

PR 34 already centralizes raw-SQL detection, schedules one unique expiry job per approval or context-expansion request, and serializes directory application through the owning Ash action. Three narrower assumptions remain unsafe: the scanner lists only two Postgrex entry points, an Oban error at `max_attempts` discards a forever-unique expiry job, and directory freshness compares only the provider timestamp even though WorkOS can emit distinct events within the same timestamp precision.

Canonical verification also exposed a branch-local test-infrastructure regression: wrapping each synchronous concurrency callback in a separate sandbox-owner process races Ecto ownership cleanup and can fail with `{:already, :allowed}` before test cleanup runs.

The implementation must remain inside Ash transactions, use a forward AshPostgres-generated migration, introduce no raw SQL, and avoid speculative terminal-state machinery.

## Goals / Non-Goals

**Goals:**

- Cover the public Postgrex APIs that accept, prepare, execute, or stream SQL.
- Retry only transient gate-expiry storage failures beyond the nominal attempt budget.
- Produce one deterministic accepted directory state regardless of equal-time worker execution order.
- Preserve exact provider-event replay handling and older-event rejection.
- Keep committed concurrency tests isolated without an intermediate sandbox-owner process.

**Non-Goals:**

- Treat every Postgrex utility function as a raw-SQL occurrence.
- Add a second gate-expiry job, a manual repair queue, or a new terminal state.
- Infer causal order from WorkOS event-ID spelling.
- Rewrite or backfill existing migrations with repository-authored SQL.

## Decisions

### Classify the complete Postgrex SQL operation family

The scanner will use an explicit Postgrex operation set covering `query`, `query!`, `prepare`, `prepare!`, `prepare_execute`, `prepare_execute!`, `execute`, `execute!`, and `stream`. The adjacent Ecto SQL-adapter set will cover `query`, `query!`, `query_many`, `query_many!`, and `stream`. These are the public APIs that accept SQL or execute a prepared SQL value in the pinned dependency versions. Receiver resolution already covers fully qualified, aliased, and imported calls, so explicit operation sets close the bypass without source-text heuristics or false positives for unrelated modules.

### Snooze transient gate-expiry storage failures

`GateExpiryWorker` will translate only `:integration_storage_unavailable` into a short Oban snooze. Oban's basic engine increments `max_attempts` for a snoozed job, so the same forever-unique job remains eligible until the transactional expiry and durable failure event commit. Permanent Ash validation or authorization errors retain normal error behavior instead of retrying forever. The regression exercises the production result adapter directly, avoiding a test-only runtime seam.

### Order equal provider timestamps by durable receipt order

Every applied user, group, and membership fact will retain `provider_event_id` and `provider_received_at`. Webhook processing derives `provider_received_at` from the immutable `DirectorySyncEvent.inserted_at`; the provider event ID is the deterministic final tie-breaker when two receipts share the same microsecond. Freshness compares the tuple `(provider_updated_at, provider_received_at, provider_event_id)`, while an exact provider-event ID is always replay/stale. This ensures a later-received equal-time removal wins even if its worker acquires the directory lock first, and an earlier worker cannot overwrite it afterward.

The direct internal event helper uses the provider occurrence time as its receipt time because it intentionally bypasses webhook receipt persistence. Membership history reads sort by the same tuple before the UUID fallback so subsequent lifecycle events compare against the actual latest accepted fact.

The two receipt-order fields are nullable only for forward migration compatibility; every new create and synchronize action writes both. A legacy row without receipt metadata accepts the first equal-time event, which upgrades the row into the new ordering contract.

### Use direct scoped checkout for synchronous concurrency callbacks

`with_unboxed_connection/1` executes its callback synchronously in the calling test task. It therefore checks an unboxed connection out to that task and checks it back in in `after`, instead of starting an intermediary sandbox-owner agent and allowing the task onto that agent's connection. DBConnection already monitors the checkout owner, so task termination still releases the connection. This removes the owner-agent cleanup race while keeping each concurrent task on its own real database connection.

## Risks / Trade-offs

- **A permanently unavailable database keeps an expiry job scheduled indefinitely** → This is intentional: leaving a request pending is observable and repairable, while silently discarding the only expiry job is not. Snoozes remain delayed and do not create duplicate jobs.
- **Receipt order is not provider causal order when WorkOS itself delivers out of order** → Provider update time remains primary; receipt order is used only when the provider supplies no finer ordering signal. The provider event ID makes the result deterministic for same-microsecond receipts.
- **Existing rows lack receipt metadata** → Nullable columns avoid unsafe backfill SQL, and the first equal-time or newer accepted event populates the durable ordering fields.
- **A concurrency callback crashes before normal cleanup** → DBConnection monitors the task that owns the direct checkout and reclaims the connection when the task exits.

## Migration Plan

1. Add nullable receipt-order attributes to the three Ash resources and include them in create/update actions.
2. Generate one forward AshPostgres migration and updated snapshots.
3. Deploy code and migration together; all subsequent accepted events populate the fields.
4. Rollback removes only the new columns and reverts freshness comparison to provider time.

## Open Questions

None.
