## MODIFIED Requirements

### Requirement: Non-growing database-boundary debt
Canonical verification SHALL compare tracked project sources with deterministic
raw-SQL and direct-Ecto inventories and SHALL reject unclassified occurrences,
changed fingerprints, and stale inventory entries.

#### Scenario: New repository-authored SQL is added
- **WHEN** verification detects a raw-SQL occurrence that is absent from both the temporary debt inventory and the explicitly approved exception inventory
- **THEN** verification fails with the occurrence path and construct class

#### Scenario: SQL adapter execution spelling changes
- **WHEN** tracked code calls a public Postgrex or Ecto SQL-adapter API that queries, prepares, executes, or streams SQL through a fully qualified, aliased, or imported receiver
- **THEN** the database-boundary scanner MUST classify the call as repository-authored raw SQL

#### Scenario: Existing debt is removed
- **WHEN** implementation removes or replaces an inventoried raw-SQL or direct-Ecto occurrence
- **THEN** verification fails until the stale debt entry is removed in the same change

#### Scenario: Verification examines project scope
- **WHEN** the database-boundary scan runs
- **THEN** it MUST include tracked runtime code, tests, seeds, migrations, and SQL files while excluding dependency source and untracked build artifacts

#### Scenario: Verification runs from a clean checkout
- **WHEN** the planning and database-boundary checks complete
- **THEN** they MUST NOT rewrite an inventory, source file, or OpenSpec artifact
