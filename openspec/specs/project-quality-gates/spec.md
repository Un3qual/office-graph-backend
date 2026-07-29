# project-quality-gates Specification

## Purpose

Define the canonical, non-mutating repository verification contract across
OpenSpec, backend, frontend, dependencies, production builds, CI, and isolated
local worktrees.

## Requirements

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

### Requirement: Verification is non-mutating
The canonical verification and precommit entry points MUST NOT intentionally rewrite dependency lockfiles, generated artifacts, source files, or planning artifacts.

#### Scenario: Verify a clean checkout
- **WHEN** the canonical verification or precommit entry point runs from a clean checkout
- **THEN** the worktree remains clean after the command finishes

#### Scenario: Unused locked dependency
- **WHEN** the dependency lockfile contains an unused entry
- **THEN** verification fails with a diagnostic instead of editing the lockfile

### Requirement: Concurrent worktree isolation
Local verification SHALL isolate Compose resources and test database identity per worktree or explicit caller-provided partition while preserving an opt-out for an externally managed PostgreSQL service.

#### Scenario: Concurrent worktree gates
- **WHEN** two worktrees run the canonical verification entry point concurrently on the same host
- **THEN** they use distinct Compose project identities, host ports, and test database identities and cannot drop or mutate each other's test barriers or fixtures

#### Scenario: Externally managed PostgreSQL
- **WHEN** a caller opts out of Compose startup and supplies its connection and partition settings
- **THEN** verification uses those settings without starting or mutating a Compose service

### Requirement: Tracked continuous integration
The repository SHALL contain a tracked pull-request and branch CI workflow that installs the pinned Nix development environment and invokes the same canonical verification entry point used locally.

#### Scenario: Pull request verification
- **WHEN** a pull request changes tracked project files
- **THEN** CI runs the canonical gate and reports one required pass or failure for the repository

### Requirement: Durable specification hygiene
Canonical specifications MUST contain a concise capability purpose and MUST NOT retain generated placeholder purpose text.

#### Scenario: Generated purpose placeholder
- **WHEN** a canonical specification contains the generated `TBD - created by archiving change` purpose
- **THEN** the canonical verification entry point fails with the affected specification path

#### Scenario: Purpose describes the capability
- **WHEN** a change is archived into canonical specifications
- **THEN** each affected specification retains a concise purpose that distinguishes its capability from adjacent specifications

### Requirement: Project boundaries use canonical static analysis
Office Graph SHALL enforce planning and database-boundary policy through one
project-local, repository-wide Credo check. The check MUST preserve
Git-tracked source discovery, SQL-file coverage, deterministic inventory
comparison, and non-mutating behavior even when those paths are outside
Credo's configured Elixir source list.

#### Scenario: Canonical static analysis runs
- **WHEN** canonical verification invokes `mix credo --strict`
- **THEN** planning and database-boundary enforcement MUST run exactly once and report violations as normal Credo issues

#### Scenario: Focused project-boundary linting runs
- **WHEN** a contributor selects only the project-boundary Credo check
- **THEN** it MUST apply the same repository-wide source and inventory semantics as canonical verification

#### Scenario: A source violation is found
- **WHEN** a new or changed database occurrence or a prohibited planning path is detected
- **THEN** the Credo issue MUST identify the actionable source path, diagnostic kind, and available line, construct, and fingerprint context

#### Scenario: An inventory violation is found
- **WHEN** a database-access entry is stale or malformed
- **THEN** the Credo issue MUST identify the owning inventory and the stale locator or missing metadata

#### Scenario: Credo receives a narrowed source list
- **WHEN** Credo's configured or command-line source selection excludes migrations, seeds, SQL files, removed files, or planning paths
- **THEN** the project-boundary check MUST still evaluate the complete Git-tracked repository boundary

#### Scenario: Canonical verification is configured
- **WHEN** the Credo check has behavior parity with the existing boundary commands
- **THEN** canonical verification MUST remove the separate planning-boundary and database-boundary command invocations rather than scanning twice

### Requirement: Canonical test database logging is quiet by default

Office Graph SHALL suppress Ecto, AshPostgres, and repository query debug logs
during normal test and canonical verification runs while preserving an
explicit opt-in diagnostic mode.

#### Scenario: Canonical test suite passes

- **WHEN** `bin/verify` runs the normal ExUnit suite
- **THEN** query text and bound parameter dumps MUST NOT be emitted for
  successful database operations

#### Scenario: Contributor diagnoses a database failure

- **WHEN** a contributor enables the documented SQL diagnostic switch for a
  focused test run
- **THEN** database query debug logging MUST be available without changing
  tracked configuration

#### Scenario: Logging contract regresses

- **WHEN** a normal test environment emits successful query logs at its
  configured logger level
- **THEN** project-quality verification MUST fail with a focused logging
  configuration diagnostic
