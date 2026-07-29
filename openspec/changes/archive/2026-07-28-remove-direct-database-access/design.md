## Context

The canonical database-boundary scanner currently records 894 repository
occurrences. This change owns the 721 entries whose `remediation_change` is
`remove-direct-database-access`: 92 in production code, 415 in tests, and 214
in test support. The exact starting set is the fingerprinted subset in
`openspec/specs/ecto-sql-boundaries/database-access-debt.json` at parent commit
`914b6564`; each entry includes path, owner, class, construct, function,
ordinal, and SHA-256 fingerprint.

The remaining 173 migration occurrences belong to
`rebaseline-unreleased-migrations`, and the single approved PostgreSQL 18
`uuidv7()` fragment remains in
`approved-database-exceptions.json`. This change grants no new SQL exception.

The production inventory consists of 42 raw-SQL and 50 direct-Ecto
occurrences across 34 files. Most direct-Ecto calls are explicit transaction
wrappers around Ash operations. Raw SQL falls into four groups: advisory locks,
mixed-resource projections, JSON/partial-index predicates, and direct
validation or state reads. Test SQL is concentrated in fixture mutation,
catalog assertions, and trigger/advisory-lock concurrency barriers.

## Goals / Non-Goals

**Goals:**

- Reduce the non-migration removal inventory from 721 occurrences to zero.
- Make Ash actions, code interfaces, relationships, aggregates, calculations,
  atomic changes, locks, and bulk APIs the only normal persistence interface.
- Preserve command atomicity, authorization, idempotency, lifecycle, audit,
  revision, event, and concurrency semantics.
- Find and eliminate read-modify-write hazards in every touched mutating path.
- Replace SQL-shaped tests with public behavior tests and typed test support.
- Make database debug logging quiet by default in the canonical gate and
  explicitly opt-in when diagnosing a failure.

**Non-Goals:**

- Rewriting or squashing unreleased migrations; that is the next dedicated
  change.
- Removing the already approved PostgreSQL 18 UUIDv7 default fragment.
- Changing public GraphQL, JSON API, or product behavior.
- Introducing a generic repository wrapper that merely hides Ecto or SQL.
- Approving a standing exception for projections, tests, bulk work, locks, or
  reconciliation.

## Decisions

### 1. The fingerprinted debt inventory is the exact removal ledger

The accepted scope is every entry whose `remediation_change` equals
`remove-direct-database-access` in the canonical debt inventory at
`914b6564`. Implementation removes entries only when the corresponding source
occurrence disappears, so the existing Credo gate proves both completeness and
fingerprint stability.

This is preferred over copying 721 rows into prose, which would create a second
inventory that could drift. The change will add a human-readable progress
summary by owner, but the canonical JSON remains the exact machine-checked
ledger.

### 2. Replace mechanisms, not names

A new helper that calls `Repo.query`, `Repo.transaction`, `Ecto.Multi`, or a
SQL fragment would only hide the boundary escape and is forbidden. Each path
must move to the owning resource/domain contract:

- single-resource writes use public Ash create, update, destroy, or generic
  actions;
- multi-record work is coordinated by an owning action using action hooks and
  the resource action's managed transaction;
- uniqueness and replay use identities, upsert support, atomic filters, and
  typed conflict errors;
- stale writes use `optimistic_lock`, atomic updates, or
  database-enforced constraints;
- bounded locking uses Ash query locks such as `:for_update` only where an
  identity or atomic operation cannot express the invariant;
- bulk work uses Ash bulk APIs with explicit authorization and error handling;
- projections use Ash reads, relationships, aggregates, calculations, manual
  relationships, or typed generic actions that return typed values.

The alternative—retaining explicit `Repo.transaction` around Ash calls—would
keep transaction ownership outside the action and make hooks, authorization,
and failure behavior harder to reason about.

### 3. Remove advisory-lock correctness dependencies

Current advisory locks serialize installation binding, agent invocation,
conversation append, reconciliation, session changes, observation creation,
and relationship-cycle checks. They will be replaced with the narrowest
declarative invariant:

- unique identities and upserts for create-once/idempotent records;
- row locks or optimistic locks for updates to an existing aggregate;
- atomic conditional updates for leases and lifecycle transitions;
- constraint-backed edge uniqueness plus an action-owned cycle check for graph
  relationships.

No business invariant may depend only on a process-local mutex. Concurrency
tests must prove the database-visible result under separate sandbox owners.

### 4. Treat read-modify-write as an action design defect

For every mutating occurrence, implementation will record the data read before
the write and classify it as one of:

- authorization or validation input loaded in the same Ash action transaction;
- expected-version input enforced with optimistic locking;
- uniqueness/idempotency input enforced by an identity/upsert;
- aggregate state updated atomically or recomputed from committed child rows.

A path is not complete merely because its `Repo.transaction` disappeared.
Tests must still demonstrate two concurrent writers cannot both commit an
invalid outcome and that a loser receives a typed safe conflict.

### 5. Tests use public boundaries and deterministic coordination

Tests will create and mutate records through public Ash/domain actions.
Database-catalog assertions will be replaced by behavior that proves the
constraint or index contract. Test-only triggers, functions, table renames,
advisory locks, and direct row mutation will be replaced by:

- action hooks or test adapters that pause at a typed domain seam;
- independent processes and sandbox owners coordinated with messages/barriers;
- resource actions dedicated to test setup only when the state is otherwise
  unreachable and the action itself preserves resource validation;
- observable behavior assertions instead of implementation-level catalog
  inspection.

The test API must not be callable from production entrypoints.

### 6. Quiet test SQL logging is configuration, not output filtering

The test environment will set Ecto/Ash query logging above the normal test
logger threshold. A documented environment switch will restore debug SQL for
one diagnostic run. Canonical verification will assert that a normal passing
test does not emit query logs rather than piping or discarding process output.

### 7. Implement in behavior-preserving owner batches

The 34 production files are handled in these dependency-aware batches:

1. foundation, tenancy, authorization, identity, and content;
2. integrations, proposed changes, work packets, runs, and verification;
3. work graph validation, relationship policy, and system commands;
4. agent runtime commands and workers;
5. GitHub reconciliation, webhook, and outbound processing;
6. node conversations and mixed projections;
7. tests and test support, followed by deletion of the remaining debt rows.

Each batch gets focused behavior and concurrency verification and a commit
before the next batch.

## Risks / Trade-offs

- **[Risk] Action-owned transaction refactors change failure ordering.**
  → Preserve typed error precedence in behavior tests and add failure-atomicity
  coverage before removing each wrapper.
- **[Risk] Replacing advisory locks exposes an unmodeled uniqueness gap.**
  → Add the identity/constraint first, prove concurrent behavior, then remove
  the lock.
- **[Risk] Projection rewrites introduce N+1 queries or over-fetching.**
  → Keep bounded query-count tests and use batched Ash relationships,
  aggregates, and keyset pagination.
- **[Risk] Behavior-only tests miss a performance-critical index.**
  → Preserve bounded-query and representative-volume tests; index DDL itself is
  handled and verified by the migration rebaseline.
- **[Risk] Test support becomes a parallel product API.**
  → Keep helpers under `test/support`, expose only narrow typed operations, and
  reject production references with architecture tests.
- **[Risk] The batch is too large for one review.**
  → Commit by owner batch and keep the exact inventory/count visible after
  every commit.

## Migration Plan

1. Add progress reporting that groups the exact removal inventory by owner and
   class without changing the canonical scanner.
2. Add failing tests for quiet logging, zero production occurrences, and the
   first owner batch's concurrency invariants.
3. Replace production occurrences batch by batch, removing matching debt rows
   in the same commit.
4. Replace test/test-support SQL and direct Ecto after production exposes the
   necessary typed seams.
5. Require zero `remove-direct-database-access` entries and run the complete
   canonical gate.

Rollback is commit-local: each owner batch can be reverted with its matching
inventory update. No persisted schema is removed in this change.

## Open Questions

None. If implementation discovers a database behavior that the pinned Ash and
AshPostgres versions cannot express safely, work stops at that exact
fingerprint for a new user decision; this change does not pre-approve it.
