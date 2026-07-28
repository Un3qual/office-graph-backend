## ADDED Requirements

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
