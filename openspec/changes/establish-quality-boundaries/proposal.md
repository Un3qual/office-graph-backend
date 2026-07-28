## Why

Office Graph currently has two conflicting sources of planning truth and a
database-access policy that broadly permits repository-authored SQL. Before the
approved Ash, API, persistence, and migration remediation begins, the project
needs enforceable boundaries that keep OpenSpec canonical and prevent existing
architecture debt from growing.

## What Changes

- **BREAKING** Retire `docs/superpowers/**` as a repository planning system
  after reconciling any still-valid unique decisions into canonical OpenSpec
  artifacts.
- Require proposals, designs, implementation tasks, and durable project
  decisions to live in OpenSpec rather than parallel plan directories.
- **BREAKING** Replace category-based permission for direct Ecto and SQL with
  Ash-first database access and a default prohibition on repository-authored
  SQL, SQL fragments, and direct SQL query calls.
- Require each future raw-SQL exception to receive explicit user approval in an
  accepted OpenSpec change and to record its exact scope, owner, verification,
  and retirement condition.
- Require any remaining direct Ecto or explicit `Repo.transaction` path to
  document why an Ash action, atomic change, hook, generic action, relationship,
  aggregate, optimistic lock, or action-managed transaction is insufficient.
- Inventory existing raw-SQL and direct-database debt as unapproved remediation
  work, block new occurrences, and make later changes remove the inventory.
- Add the planning and direct-database checks to the canonical repository
  verification entry point.

This is the first change in the approved quality-remediation program. It
establishes the boundaries used by the subsequent Ash resource normalization,
Relay/API migration, concurrency and raw-SQL removal, migration rebaseline, and
WorkOS enterprise SSO/Directory Sync changes; it does not implement those
subsequent changes itself.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `project-quality-gates`: Make OpenSpec-only planning and non-growth of
  unapproved direct-database access part of canonical verification.
- `ecto-sql-boundaries`: Replace broad categories of permitted direct Ecto/SQL
  with Ash-first access, explicit justification for remaining direct Ecto, and
  explicit per-occurrence user approval for raw SQL.
- `backend-architecture`: Remove direct Ecto/SQL as a generally available Ash
  escape hatch.
- `architecture-stabilization`: Treat the current direct-database inventory as
  removal debt rather than accepted architecture exceptions.

## Impact

- Affects `openspec/project.md`, the four modified canonical specifications,
  repository verification code, architecture conformance coverage, and
  planning documentation.
- Removes `docs/superpowers/**` after reconciliation and prevents it from being
  recreated.
- Introduces a mechanically verifiable inventory of existing
  repository-authored raw SQL without treating that inventory as approval.
- Does not change product APIs, persisted data, runtime behavior, or external
  dependencies.
