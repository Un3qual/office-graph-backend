## Why

Office Graph is unreleased, but its 49-file migration history still contains
173 inventoried raw-SQL occurrences, application-data insertions, deterministic
MD5-derived UUIDs, and intermediate schema states that no release must support.
Now that the Ash resources and database-access boundaries are stable, the
project can replace that development history with a clean PostgreSQL 18
baseline and prove it from an empty database.

## What Changes

- **BREAKING** Replace the unreleased migration chain with an
  AshPostgres-generated baseline that represents the current resource schema
  directly instead of replaying obsolete intermediate states.
- Remove schema-migration insertion of capabilities, role grants, relationship
  definitions, agent definitions, and other application data; initialize
  required data through idempotent Ash-owned setup behavior.
- Remove migration `execute`, MD5-derived identifiers, handwritten DDL/data
  rewrites, and obsolete migration-specific compatibility tests.
- Retain only the explicitly approved PostgreSQL 18 native `uuidv7()` default
  occurrence when the generated baseline cannot express that default without a
  fragment.
- Replace the 173-entry migration debt inventory with the exact terminal
  baseline inventory and require zero entries assigned to
  `rebaseline-unreleased-migrations`.
- Make empty-database migration, setup, schema drift checking, PostgreSQL 18
  verification, and representative product bootstrapping part of the
  migration-baseline verification contract.

## Capabilities

### New Capabilities

- `migration-baseline`: Define the clean unreleased schema baseline,
  Ash-owned application-data initialization, and empty-database verification
  contract.

### Modified Capabilities

- `ecto-sql-boundaries`: Remove historical migration debt and constrain the
  terminal baseline to declarative migrations plus exact approved exceptions.
- `project-quality-gates`: Require migration generation drift and
  empty-database baseline/setup verification in the canonical gate.
- `unreleased-development-policy`: Permit replacing unreleased migration
  history only through an accepted, fully verified rebaseline rather than
  piecemeal edits to historical migrations.

## Impact

- Replaces `priv/repo/migrations/**` and introduces current AshPostgres resource
  snapshots.
- Affects local database setup, release/setup tasks, seeds, migration-focused
  tests, database-boundary inventories, and `bin/verify`.
- Existing local development data must be reset or exported and re-imported;
  there is no production upgrade path because Office Graph has not been
  released.
- Product APIs and runtime domain behavior remain unchanged.
