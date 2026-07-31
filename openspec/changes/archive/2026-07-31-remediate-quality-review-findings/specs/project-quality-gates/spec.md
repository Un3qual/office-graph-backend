## MODIFIED Requirements

### Requirement: Non-growing database-boundary debt

Canonical verification SHALL compare current tracked project sources with the
exact explicitly approved raw-SQL exception inventory and SHALL reject every
unmatched occurrence or stale approved exception.

#### Scenario: New repository-authored SQL is added

- **WHEN** verification detects a raw-SQL or direct-Ecto occurrence that does
  not exactly match an explicitly approved exception
- **THEN** verification fails with the occurrence path and construct class

#### Scenario: Approved occurrence is removed or changed

- **WHEN** implementation removes, moves, rewrites, or broadens an approved
  occurrence
- **THEN** verification fails until the stale approval is removed or the exact
  changed occurrence receives user approval through an accepted OpenSpec change

#### Scenario: Verification examines project scope

- **WHEN** the database-boundary scan runs
- **THEN** it MUST include tracked runtime code, tests, test support, seeds,
  migrations, and SQL files while excluding dependency source and untracked
  build artifacts

#### Scenario: Verification runs from a clean checkout

- **WHEN** the planning and database-boundary checks complete
- **THEN** they MUST NOT rewrite an inventory, source file, or OpenSpec artifact

## ADDED Requirements

### Requirement: Database scanner classifies executable syntax

The project-local database-boundary scanner SHALL classify executable
repository calls and SQL-bearing migration constructs rather than unrelated
binary literals or documentation text.

#### Scenario: Migration documentation mentions SQL

- **WHEN** a migration module attribute or other non-executed literal mentions
  `insert into`, `md5(`, or another SQL phrase
- **THEN** the scanner MUST NOT report an occurrence unless that literal is an
  argument or option value of a classified executable SQL-bearing construct

### Requirement: Duplicate static-analysis configuration is prohibited

Each static analyzer SHALL have one canonical invocation and one path/options
configuration used by the repository gate.

#### Scenario: ExDNA runs during static analysis

- **WHEN** the canonical static-analysis alias runs
- **THEN** ExDNA MUST scan the current configured paths exactly once and MUST
  NOT retain a second path list that can drift after files move

### Requirement: Conformance tests assert observable contracts

Architecture and conformance tests SHALL inspect parsed syntax, configured Ash
resources, generated schemas, or consumer-visible behavior rather than count
source-text spellings or duplicate inventories already derivable from those
artifacts.

#### Scenario: Relay resource conformance is checked

- **WHEN** the generated GraphQL resource surface is verified
- **THEN** the expected resource types MUST be derived from configured Ash
  resources and their schema objects MUST implement Relay Node without a
  separately maintained type-name list

#### Scenario: Stable projection Node behavior is checked

- **WHEN** a stable projection is accepted as a Relay Node
- **THEN** a behavior test MUST prove it can be refetched by opaque ID rather
  than a source-text regular expression asserting macro formatting
