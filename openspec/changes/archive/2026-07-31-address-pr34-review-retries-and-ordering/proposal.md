## Why

The next PR 34 review found three remaining fail-open or liveness gaps: prepared Postgrex APIs can bypass the raw-SQL scanner, a gate-expiry storage failure can exhaust its only forever-unique job, and distinct directory events with equal provider timestamps have no durable ordering key. Canonical verification also exposed a branch-local sandbox-owner race in the committed-concurrency helper. These gaps must close before the branch is merged so repository policy, agent liveness, directory authority, and verification remain deterministic.

## What Changes

- Classify every public Postgrex and Ecto SQL-adapter query, preparation, execution, and stream entry point as repository-authored raw SQL.
- Keep gate-expiry storage failures retryable through Oban snoozing, including after the nominal attempt budget, while preserving permanent-error behavior.
- Persist receipt-order metadata on directory users, groups, and memberships and use it as a deterministic tie-breaker when provider update timestamps are equal.
- Keep concurrency-test database ownership scoped directly to the task that executes each synchronous callback.
- Add focused regression coverage and a forward AshPostgres-generated migration; no repository-authored raw SQL is introduced.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `project-quality-gates`: Cover Postgrex prepared-query and execution APIs plus the adjacent Ecto SQL query/stream family in the canonical database-boundary scan.
- `agent-approval-requests`: Keep expiry terminalization retryable when storage is unavailable at the nominal attempt limit.
- `enterprise-directory-sync`: Order distinct equal-time directory events by durable receipt identity rather than discarding every equal timestamp as stale.

## Impact

Affected areas are the database-boundary scanner, the agent gate-expiry worker, WorkOS directory-event application, three directory resources, their generated migration and snapshots, the concurrency-test support helper, focused tests, and the three canonical OpenSpec capabilities. Public HTTP and GraphQL contracts, dependencies, and raw-SQL inventories do not change.
