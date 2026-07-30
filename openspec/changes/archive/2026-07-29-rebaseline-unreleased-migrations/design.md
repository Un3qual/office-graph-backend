## Context

Office Graph has never been released, but it has accumulated 49 migrations
that recreate development-era intermediate schemas. Thirty-two of those files
account for 173 raw-SQL debt occurrences: 72 SQL check expressions, 64
`execute` calls, and 37 partial-index predicates. Several `execute` calls also
insert application records and derive deterministic UUIDs by casting MD5
hashes of stable capability or role-capability strings.

The current Ash resources now represent the intended schema, all runtime and
test persistence goes through Ash, PostgreSQL 18 is the repository baseline,
and ordinary primary keys use PostgreSQL's native UUIDv7 default. This is the
safe point to replace the unreleased history. Existing local databases are
disposable development state; there is no production database or released
upgrade path to preserve.

AshPostgres migration generation is not currently usable as the source of
truth because resources opt out with `migrate? false`, no resource snapshots
are checked in, and filtered identities do not provide generator metadata.
Those conditions must be corrected as part of the rebaseline.

## Goals / Non-Goals

**Goals:**

- Replace all 49 historical migrations with a current-schema PostgreSQL 18
  baseline generated from the Ash resource model.
- Check in current AshPostgres resource snapshots and make generator drift a
  verification failure.
- Remove all 173 migration debt occurrences, including MD5 identifiers,
  inserts, `execute`, SQL checks, and partial-index predicate strings.
- Preserve current uniqueness, lifecycle, authorization, idempotency, and
  concurrency behavior through Ash identities, typed attributes, actions, and
  declarative database constraints.
- Initialize required capabilities, relationship definitions, endpoint rules,
  and the canonical run-review agent through idempotent owning-domain Ash
  actions.
- Prove migration plus setup from an empty PostgreSQL 18 database and prove
  setup replay without duplicate rows.

**Non-Goals:**

- Preserve or transform arbitrary local development data.
- Provide a production upgrade from any historical migration version.
- Add WorkOS, SSO, Directory Sync, or other product features.
- Weaken the repository's raw-SQL approval boundary.
- Move domain data into migrations or preserve obsolete migration-specific
  compatibility tests.

## Decisions

### 1. Replace the chain as one reviewed rebaseline

The existing migration files will be removed together and replaced by a
current baseline generated from the resource model. The replacement is one
explicit unreleased-history operation, not piecemeal editing of old migrations.
Its commit and OpenSpec archive provide the review history.

The new baseline may use multiple generator-emitted files only when
AshPostgres must defer references or indexes for dependency ordering; they
remain one logical baseline and must all be generated from empty snapshots.

Alternative considered: add a 50th corrective migration. Rejected because it
would retain every obsolete state, data insertion, MD5 identifier, and raw-SQL
occurrence the change exists to remove.

Alternative considered: edit only the migrations containing MD5 or inserts.
Rejected because it would leave an unreviewable hybrid history and retain
schema drift from the current Ash model.

### 2. Make AshPostgres resources and snapshots authoritative

Tracked PostgreSQL-backed resources will participate in migration generation;
blanket `migrate? false` declarations will be removed. Generated resource
snapshots will be checked in next to the new baseline. Canonical verification
will run the generator's non-mutating check mode and fail when resources,
snapshots, or migrations diverge.

Migration review still applies. Generated output is not automatically accepted:
the boundary scanner and scratch-database tests must pass, and generator output
containing a new raw-SQL occurrence remains prohibited.

Alternative considered: hand-author a compact Ecto migration from the current
tables. Rejected because it would create a second schema model and repeat the
manual drift that caused the current chain.

### 3. Normalize filtered identities without SQL predicates

Nullable-key identities whose predicate only excludes `NULL` will become
ordinary unique identities because PostgreSQL unique indexes already permit
multiple null keys. Scope identities will use a single key set with Ash's
`nils_distinct?` semantics where that represents one unscoped record.

State-filtered identities such as active edges, accepted intake replay,
pending agent gates, and active sessions will use private typed identity-slot
attributes maintained by every owning create/transition action. Active or
pending rows receive the shared non-null slot value; terminal rows clear it.
A normal unique identity includes the slot, so PostgreSQL permits multiple
terminal rows but rejects a second live row without a handwritten `WHERE`
predicate. Transitions remain atomic in the owning Ash action and retain race
tests.

Alternative considered: configure `identity_wheres_to_sql` and retain partial
indexes. Rejected because that would replace old raw SQL with newly approved
raw SQL when the invariant is expressible through typed resource state.

### 4. Keep cross-field policy in Ash instead of SQL check strings

The baseline will use declarative column types, nullability, foreign keys,
ordinary indexes, unique indexes, and PostgreSQL-native UUID defaults. Current
cross-field and lifecycle rules will be enforced by resource constraints,
action validations, atomic changes, and accepted transition actions. The
project's zero-direct-database boundary ensures product writes cannot bypass
those actions.

The rebaseline verification will map every removed historical SQL check to an
owning Ash validation or prove that it described an obsolete intermediate
state. Missing validation is fixed before the check is removed.

Alternative considered: retain Ecto `constraint(..., check: "...")` calls.
Rejected because the check body is repository-authored SQL and the user has not
approved those exact occurrences.

### 5. Move application data into idempotent domain setup

Each owning domain will expose a private setup action for its canonical data:

- Authorization owns the recognized capability catalog.
- WorkGraph owns relationship definitions and endpoint rules.
- AgentRuntime owns the canonical `run-review` definition.

`OfficeGraph.Release.setup/0` will orchestrate those public domain boundaries
after migrations. It will use Ash actions, identities, upserts, and
action-managed transactions only. Running setup twice must produce the same
records and no duplicates. Local `ecto.setup` will run release setup before
optional demo seeds; a packaged release can invoke the same module through
`eval`.

Alternative considered: keep reference inserts in the baseline because they
are convenient. Rejected because schema migration and application bootstrap
have different ownership, replay, authorization, and failure semantics.

### 6. Verify both structure and usable startup

Focused verification will:

1. create a fresh isolated PostgreSQL 18 database;
2. run the baseline without seeds;
3. assert generator/snapshot drift is absent;
4. run release setup twice;
5. verify exact reference-data manifests and UUIDv7 identifiers through Ash;
6. run representative local bootstrap, relationship, agent binding, and
   authorization behavior;
7. rollback and re-apply the complete logical baseline where reversible;
8. confirm database-boundary debt is zero and the only approved SQL exception
   remains the native `uuidv7()` default.

Canonical `bin/verify` will include the non-mutating drift and empty-baseline
checks without running the full ExUnit suite twice.

## Risks / Trade-offs

- [A current database constraint exists only in an old migration] → Inventory
  every check and partial index before deletion, map it to resource behavior,
  and retain concurrency tests for live uniqueness.
- [Identity-slot state drifts from lifecycle state] → Make the slot private,
  set or clear it in every owning action, reject direct writes, and add
  transition plus race coverage.
- [Generator output introduces hidden SQL] → Run the project boundary scanner
  before accepting the baseline and stop for exact user approval if a truly
  unavoidable occurrence remains.
- [Local data is lost] → Document a required volume reset and permit explicit
  export/import before reset; do not pretend an unreleased compatibility path
  exists.
- [Setup partially completes] → Give each owning setup action idempotent
  identities/upserts and make the orchestrator safely resumable.
- [One giant generated migration is hard to review] → Review by resource/table
  inventory and generated snapshots, then prove the result with schema drift,
  boundary, and scratch-database tests.

## Migration Plan

1. Add failing baseline, setup replay, identity, and migration-boundary tests.
2. Make PostgreSQL-backed Ash resources participate in migration generation
   and normalize filtered identities without SQL predicates.
3. Add domain-owned reference-data manifests and idempotent setup actions.
4. Remove historical migrations and snapshots, generate the current baseline,
   and review the output against the raw-SQL scanner.
5. Replace migration debt and approved-exception inventories with the exact
   terminal state.
6. Run fresh PostgreSQL 18 migration/setup, rollback/re-apply, focused behavior
   and concurrency tests, strict OpenSpec validation, and `bin/verify`.

Rollback is a normal code revert plus recreation of the disposable local
database. The old migration chain is recoverable from Git history but is not a
supported runtime migration path after this change.

## Open Questions

None. The project is unreleased, the history replacement and PostgreSQL 18
upgrade were approved, and no additional raw-SQL exception is assumed.
