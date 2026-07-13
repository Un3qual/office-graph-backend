## ADDED Requirements

### Requirement: One canonical repository gate
The project SHALL expose one documented verification entry point that runs inside the pinned Nix flake and validates canonical OpenSpec artifacts, dependency advisories, backend formatting and static analysis, the complete ExUnit suite, frontend generated artifacts and types, frontend tests, and production frontend and backend builds.

#### Scenario: Clean repository verification
- **WHEN** a contributor runs the canonical verification entry point from a clean checkout with required services available
- **THEN** every specified backend, frontend, OpenSpec, dependency, and production-build check runs exactly once and the command exits successfully

#### Scenario: Behavioral regression outside architecture tests
- **WHEN** any ExUnit test outside the focused architecture-conformance module fails
- **THEN** the canonical verification entry point exits unsuccessfully

#### Scenario: Layer-specific regression
- **WHEN** OpenSpec validation, a dependency advisory, frontend generation or type-checking, a frontend test or build, backend static analysis, an ExUnit test, or a production build fails
- **THEN** the canonical verification entry point exits unsuccessfully at that layer

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

