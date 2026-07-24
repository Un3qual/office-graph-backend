## Context

`RunIndex` filters by organization and workspace, then keyset-orders by
`inserted_at DESC, id DESC`. The database has no matching index, and three
lifecycle columns remain nullable because they were added after the original
`runs` table. GraphQL intentionally exposes those summary fields as non-null.

Oban Lifeline currently rescues every job that has remained `executing` for
five minutes. Oban workers have no execution timeout by default, so Lifeline
can make a live job available while its original process is still running.

## Goals / Non-Goals

**Goals:**

- Make the non-null run lifecycle contract a database and resource invariant.
- Backfill legacy rows without claiming a known lifecycle state.
- Let Postgres satisfy the scoped run-index filter and total order from one
  composite index.
- Ensure every live Oban worker reaches a hard deadline before Lifeline can
  classify its job as orphaned.

**Non-Goals:**

- Change run lifecycle meanings or add new API fields.
- Replace Lifeline, add Oban Pro, or introduce heartbeat infrastructure.
- Redesign worker retry or idempotency behavior.

## Decisions

1. A forward migration will replace null lifecycle values with `unknown`,
   enforce `NOT NULL`, and add the composite run index. Projection-only
   coalescing was rejected because it would leave invalid storage visible to
   other non-null run surfaces. Reusing `state` was rejected because the
   legacy aggregate state does not reliably determine execution and
   verification state.

2. The index will use
   `(organization_id, workspace_id, inserted_at DESC, id DESC)`, exactly
   matching the equality scope filter and keyset order. A wider covering index
   was rejected because the selected labels can evolve and the bounded page
   does not justify duplicating those columns in the index.

3. The agent execution worker will have a three-minute Oban deadline, leaving
   headroom above the maximum two-minute adapter manifest timeout. All other
   production workers will have a thirty-minute deadline. Lifeline will use
   its conservative sixty-minute window, so it cannot rescue any job whose
   original worker is still allowed to execute.

4. Existing replay, unique-job, and durable-state behavior remains the defense
   against retries after either an execution timeout or orphan recovery.

## Risks / Trade-offs

- [Legacy null state becomes `unknown`] → Preserve uncertainty explicitly
  rather than deriving a misleading lifecycle value.
- [A genuinely long integration job reaches thirty minutes] → Oban records a
  timeout and applies the worker's existing retry/idempotency contract before
  Lifeline can intervene.
- [The new index increases write and storage cost] → Limit it to the four
  columns required by the new read path.

## Migration Plan

Deploy the forward migration before serving the updated resource contract. The
migration backfills nulls, applies non-null constraints, and creates the index.
Rollback drops the index and relaxes the constraints; it does not turn
`unknown` values back into nulls.

## Open Questions

None.
