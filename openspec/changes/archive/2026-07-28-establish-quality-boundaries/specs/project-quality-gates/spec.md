## MODIFIED Requirements

### Requirement: One canonical repository gate
The project SHALL expose one documented verification entry point that runs
inside the pinned Nix flake and validates canonical OpenSpec artifacts,
repository planning boundaries, raw-SQL and direct-database inventories,
dependency advisories, backend formatting and static analysis, the complete
ExUnit suite, frontend generated artifacts and types, frontend tests, and
production frontend and backend builds.

#### Scenario: Clean repository verification
- **WHEN** a contributor runs the canonical verification entry point from a clean checkout with required services available
- **THEN** every specified backend, frontend, OpenSpec, planning-boundary, database-boundary, dependency, and production-build check runs exactly once and the command exits successfully

#### Scenario: Behavioral regression outside architecture tests
- **WHEN** any ExUnit test outside the focused architecture-conformance module fails
- **THEN** the canonical verification entry point exits unsuccessfully

#### Scenario: Layer-specific regression
- **WHEN** OpenSpec validation, a planning-boundary check, a database-boundary check, a dependency advisory, frontend generation or type-checking, a frontend test or build, backend static analysis, an ExUnit test, or a production build fails
- **THEN** the canonical verification entry point exits unsuccessfully at that layer

## ADDED Requirements

### Requirement: OpenSpec-only durable planning
OpenSpec SHALL be the repository's only durable system for proposals, designs,
implementation tasks, and accepted project decisions.

#### Scenario: Parallel planning directory is present
- **WHEN** canonical verification finds `docs/superpowers/**` or another prohibited durable planning tree outside OpenSpec
- **THEN** verification fails and identifies the conflicting path

#### Scenario: Historical planning file contains a current decision
- **WHEN** a parallel planning file contains a unique decision that remains current
- **THEN** the decision MUST be promoted into the owning canonical OpenSpec capability before the parallel file is removed

#### Scenario: Historical execution narration is reviewed
- **WHEN** an old plan contains only completed tasks, execution narration, or decisions already represented by OpenSpec or shipped behavior
- **THEN** it MUST be removed without copying that non-normative content into OpenSpec

### Requirement: Non-growing database-boundary debt
Canonical verification SHALL compare tracked project sources with deterministic
raw-SQL and direct-Ecto inventories and SHALL reject unclassified occurrences,
changed fingerprints, and stale inventory entries.

#### Scenario: New repository-authored SQL is added
- **WHEN** verification detects a raw-SQL occurrence that is absent from both the temporary debt inventory and the explicitly approved exception inventory
- **THEN** verification fails with the occurrence path and construct class

#### Scenario: Existing debt is removed
- **WHEN** implementation removes or replaces an inventoried raw-SQL or direct-Ecto occurrence
- **THEN** verification fails until the stale debt entry is removed in the same change

#### Scenario: Verification examines project scope
- **WHEN** the database-boundary scan runs
- **THEN** it MUST include tracked runtime code, tests, seeds, migrations, and SQL files while excluding dependency source and untracked build artifacts

#### Scenario: Verification runs from a clean checkout
- **WHEN** the planning and database-boundary checks complete
- **THEN** they MUST NOT rewrite an inventory, source file, or OpenSpec artifact
