## Context

Office Graph is unreleased and has no active OpenSpec changes. OpenSpec is
already named as the workflow source of truth, but `docs/superpowers/**`
contains 36 parallel design and plan files. The canonical architecture
specifications also broadly permit direct Ecto and SQL for categories such as
projections, replay, analytics, and bulk work. That permission has grown into a
large exception ledger and many repository-authored SQL strings across runtime
code, tests, and migrations.

The approved remediation program will subsequently normalize Ash resources,
complete the Relay and generated API migration, replace generic JSONB and
tombstone modeling, eliminate direct SQL and read-modify-write races, adopt
PostgreSQL-generated UUIDv7 identifiers, rebaseline the unreleased migration
chain, reorganize large domains, and add a replaceable WorkOS SSO/Directory
Sync adapter. This first change establishes the repository boundaries those
changes need.

The Ash implementation baseline is the project-pinned stack in `mix.lock`: Ash
3.29, AshPostgres 2.10, AshGraphql 1.9, and AshJsonApi 1.6. Subsequent
remediation designs must consult the relevant pinned documentation before
choosing custom code. In particular:

- domain actions and generated code interfaces precede hand-built query and
  changeset orchestration;
- relationships, managed relationships, identities, aggregates, built-in
  changes and validations, optimistic locking, atomic changes, action hooks,
  generic actions, and action-managed transactions precede direct Ecto;
- AshPostgres-generated migrations and references precede handwritten DDL;
- AshGraphql Relay generation and generic actions precede custom Absinthe
  resolvers;
- AshJsonApi domain routes and relationship routes precede custom controllers.

## Goals / Non-Goals

**Goals:**

- Make OpenSpec the only repository location for durable proposals, designs,
  implementation tasks, and accepted project decisions.
- Remove `docs/superpowers/**` without losing any unique current product or
  architecture decision.
- Make Ash the default database interaction boundary.
- Require explicit user approval in an accepted OpenSpec change for every
  future repository-authored raw-SQL occurrence.
- Distinguish existing unapproved removal debt from genuinely approved
  exceptions.
- Prevent the current raw-SQL and direct-Ecto inventory from growing while
  later changes drive it to zero or to a narrowly approved set.
- Apply the boundary to runtime code, tests, seeds, and migrations, not only
  `lib/**`.

**Non-Goals:**

- Remove the existing SQL, direct Ecto, or explicit `Repo.transaction` paths in
  this first change.
- Change product APIs, database schemas, resource behavior, or external
  dependencies.
- Copy old Superpowers implementation plans into OpenSpec.
- Treat dependency source under `deps/**` or SQL generated inside external
  libraries as repository-authored code.
- Forbid Ecto as AshPostgres' internal implementation.

## Decisions

### 1. Reconcile decisions, then remove the parallel planning tree

Each `docs/superpowers/**` file will be classified as one of:

1. already represented by canonical OpenSpec or shipped code;
2. obsolete or contradicted by current OpenSpec;
3. containing a unique current normative decision.

The first two classes are deleted without copying them. Only the third class is
promoted into the owning canonical OpenSpec capability. Historical task
checklists, execution logs, review-fix plans, and implementation narration are
not durable requirements and will not be migrated.

The repository instructions and canonical verification will reject a recreated
`docs/superpowers` path. Research inputs and completed review evidence may
remain in purpose-specific locations when they are clearly labeled as
non-normative and OpenSpec remains the decision authority.

Alternative considered: archive the directory under another name. Rejected
because it preserves two searchable planning systems and invites stale plans to
be treated as current.

### 2. Separate raw SQL, direct Ecto, and action-managed database work

The quality boundary uses three classes:

- **Ash-managed work:** resource actions, code interfaces, relationships,
  aggregates, identities, atomic changes, optimistic locks, hooks, generic
  actions, and transactions opened by Ash. This is the default and does not
  require an exception.
- **Direct Ecto work:** explicit `Repo.transaction`, Ecto queries, `insert_all`,
  or similar application-owned data-layer access without handwritten SQL.
  This is remediation debt by default. A remaining use must identify the
  missing Ash capability and be accepted in OpenSpec, but it does not require a
  raw-SQL approval when it contains no SQL.
- **Repository-authored raw SQL:** SQL query calls, fragments, unsafe
  fragments, migration `execute` calls, handwritten check/partial-index SQL,
  tracked `.sql` files, and equivalent SQL-bearing constructs. This is
  prohibited unless the user explicitly approves the exact occurrence through
  an accepted OpenSpec change.

This distinction avoids calling an Ash-managed transaction "raw SQL" while
still ensuring that application-owned transaction orchestration is reviewed
and replaced where built-in Ash behavior is sufficient.

Alternative considered: preserve the current category-based list of permitted
SQL purposes. Rejected because broad labels such as "projection" and
"reconciliation" do not prove that a particular SQL occurrence is necessary.

### 3. Use separate debt and approval inventories

Canonical verification will compare a deterministic scan of tracked project
sources with two machine-readable inventories:

- a temporary **debt inventory** for existing occurrences that must be removed;
- an **approved-exception inventory** containing only occurrences the user has
  explicitly approved.

A debt entry is not approval. It records a stable occurrence fingerprint,
location, construct class, and owning future remediation change. The gate
allows an existing debt fingerprint only so this first boundary can land
before the full cleanup; it rejects new or changed occurrences. Later changes
must remove debt entries as they remove code, and the intended terminal state
is an empty debt inventory.

An approved raw-SQL entry must record:

- exact occurrence fingerprint and file;
- owning module or migration;
- explicit approving OpenSpec change;
- reason built-in Ash, AshPostgres, Ecto's declarative migration DSL, and typed
  data modeling are insufficient;
- verification coverage;
- retirement condition.

Framework-generated tracked output is still repository content and is scanned.
If a generated migration necessarily contains SQL, the exact generated
occurrence still requires approval. Dependency source and untracked build
artifacts are excluded.

Alternative considered: put current debt into the existing architecture
exception ledger. Rejected because that would mislabel unapproved debt as
accepted architecture.

### 4. Scan syntax-aware constructs across the whole tracked project

The gate will inspect tracked Elixir and SQL sources rather than grep only
`lib/**`. It will classify syntax associated with:

- `Repo.query/2`, `Repo.query!/2`, `Ecto.Adapters.SQL`, and direct Postgrex
  execution;
- `fragment`, `unsafe_fragment`, and SQL-bearing query fragments;
- migration `execute`, SQL-bearing `check`, `where`, and default expressions;
- tracked `.sql` files;
- direct Ecto and explicit transaction constructs tracked separately from raw
  SQL.

Occurrence fingerprints are based on normalized syntax plus path and construct
class, not line number alone, so unrelated line movement does not rewrite the
inventory. The scanner reports an actionable diff: new, changed, stale, and
approved occurrences.

The scanner is a repository architecture gate, not a behavior test. Product
behavior remains covered through action, policy, API, migration, and
concurrency tests.

Alternative considered: a free-form Markdown ledger checked by source-string
tests. Rejected because it is easy to drift, difficult to update
mechanically, and conflates documentation with enforcement.

### 5. Put both checks in the canonical non-mutating gate

The canonical `bin/verify` path will fail when:

- `docs/superpowers/**` exists;
- a durable planning artifact is added outside OpenSpec in a prohibited
  planning location;
- a scanned database construct is absent from the debt or approved inventory;
- an inventory entry is stale or its fingerprint no longer matches;
- an approved exception lacks required OpenSpec metadata.

Verification will never update inventories automatically. A separate explicit
developer command may print or compare the current scan, but accepting a new
baseline remains a reviewed edit.

### 6. Sequence the approved remediation as separate OpenSpec changes

After this boundary change is implemented and archived, work proceeds in this
order:

1. normalize Ash resources and physical domain organization, including
   relationships, belongs-to attributes, typed replacements for all eight
   current `:map` fields, in-table soft deletion, struct ownership, and
   PostgreSQL-generated UUIDv7 identifiers;
2. complete AshGraphql Relay and AshJsonApi generation and retire the
   `operator_commands` compatibility layer;
3. replace raw SQL, direct Ecto, explicit transaction orchestration, and
   read-modify-write validations with built-in Ash behavior wherever possible;
4. rebuild the unreleased migration baseline after the final resource schema is
   stable and re-run it against an empty database;
5. add WorkOS standalone enterprise SSO and optional Directory Sync while
   Office Graph retains principal, session, membership, and authorization
   authority.

Each change is independently verified and archived before beginning a
dependent change. Narrow correctness or security fixes may still land during
the program, but broad feature expansion remains paused.

## Risks / Trade-offs

- **The initial debt inventory is large.** → Generate it mechanically once,
  review classifications, prohibit growth, and remove entries incrementally
  rather than pretending the current state is compliant.
- **Syntax scanning can produce false positives or miss novel SQL wrappers.**
  → Scan AST construct classes plus tracked `.sql` files, test the scanner
  against representative fixtures, and treat new database wrappers as scanner
  changes requiring review.
- **Deleting old plans could lose a still-valid decision.** → Classify every
  file and promote only unique normative content before deletion; compare the
  result against canonical specs and recent shipped behavior.
- **A zero-SQL goal can tempt awkward Ash abstractions.** → Prefer built-in Ash
  features, but permit a narrowly approved SQL exception when evidence shows it
  is safer and clearer. Approval is per occurrence, never by broad category.
- **Replacing explicit transactions may weaken concurrency behavior.** → The
  later change must preserve or strengthen atomicity with Ash action
  transactions, atomic changes, locks, identities, and real race tests before
  removing an existing boundary.

## Migration Plan

1. Reconcile and remove `docs/superpowers/**`.
2. Update project instructions and the four affected canonical capability
   specifications through this OpenSpec delta.
3. Add the syntax-aware scanner and create reviewed debt inventories from the
   unchanged current tree.
4. Add non-mutating planning and database-boundary checks to canonical
   verification.
5. Prove the gate rejects representative new planning and raw-SQL occurrences,
   accepts the unchanged reviewed baseline, and leaves a clean worktree.
6. Archive this change before starting the first resource-normalization change.

Rollback is a normal revert because this change does not alter runtime behavior
or persisted data. Reintroducing the parallel planning directory or broad SQL
permission is not an accepted rollback strategy.

## Open Questions

None. The planning, SQL-approval, Ash-first, remediation-sequencing, and WorkOS
boundaries were approved before this artifact was created.
