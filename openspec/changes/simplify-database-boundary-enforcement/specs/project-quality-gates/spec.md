## MODIFIED Requirements

### Requirement: Non-growing database-boundary debt
Canonical verification SHALL compare current tracked project sources and
compiled project modules with the exact explicitly approved raw-SQL,
direct-Ecto, direct repository, migration, and low-level persistence exception
inventory. Verification SHALL reject every unmatched occurrence, unresolved
escape path, or stale approved exception.

#### Scenario: New repository-authored SQL is added

- **WHEN** verification detects a raw-SQL, direct-Ecto, direct repository,
  migration SQL, or low-level persistence occurrence that does not exactly
  match an explicitly approved exception
- **THEN** verification fails with the occurrence path and construct class

#### Scenario: Approved occurrence is removed or changed

- **WHEN** implementation removes, moves, rewrites, or broadens an approved
  occurrence
- **THEN** verification fails until the stale approval is removed or the exact
  changed occurrence receives user approval through an accepted OpenSpec change

#### Scenario: Dynamic escape path is present

- **WHEN** tracked source uses dynamic dispatch, reflection, unresolved
  database-shaped variable calls, migration helpers, arbitrary migration
  control flow, external SQL files, stored routines, triggers, DO blocks, or
  direct repository calls in persistence-sensitive code
- **THEN** the gate MUST fail closed instead of interpreting the construct

#### Scenario: Verification examines project scope

- **WHEN** the database-boundary scan runs
- **THEN** it MUST include every tracked Elixir and SQL-like source regardless
  of directory, including runtime code, tests, test support, Mix tasks,
  configuration, seeds, migrations, and scripts, while excluding dependency
  source and untracked build artifacts

#### Scenario: Verification runs from a clean checkout

- **WHEN** the planning and database-boundary checks complete
- **THEN** they MUST NOT rewrite an inventory, source file, or OpenSpec artifact

### Requirement: Database scanner classifies executable syntax

The project-local database-boundary scanner SHALL reject executable
database-boundary primitives and unresolved persistence-sensitive constructs
from parsed source without evaluating callbacks, helper bodies, dynamic module
construction, SQL bodies, macro output, or control flow.

#### Scenario: Forbidden primitive is present
- **WHEN** tracked source directly, fully qualified, aliased, or imported uses a
  known repository, SQL adapter, Postgrex, Ecto.Multi, migration SQL, query
  fragment, SQL-bearing query lock or hint, migration expression field, or
  direct repository transaction/connection primitive
- **THEN** the scanner MUST emit a fingerprinted occurrence requiring exact
  approval

#### Scenario: Dynamic database operation survives compilation
- **WHEN** BEAM abstract code contains `apply` or a dynamic receiver with a
  statically visible database operation
- **THEN** the compiled audit MUST reject the call as unresolved even when the
  source gate already reports its exact tracked-source occurrence

#### Scenario: Compiled environments are audited
- **WHEN** canonical verification reaches the compiled database-boundary audit
- **THEN** production output MUST already exist and the audit MUST inspect both
  test and production BEAMs whose compiler-recorded source remains tracked

#### Scenario: Compiled metadata is unavailable
- **WHEN** a current tracked-source BEAM lacks auditable abstract code
- **THEN** the audit MUST fail closed with a diagnostic attached to the
  compiler-recorded Elixir source path rather than the binary artifact

#### Scenario: Inert text mentions SQL
- **WHEN** ordinary strings, comments, or documentation mention SQL phrases
  without being an argument or option to a classified executable primitive
- **THEN** the scanner MUST NOT report an occurrence solely from that inert text

#### Scenario: Complex source requires interpretation
- **WHEN** proving safety would require evaluating helpers, callbacks, arbitrary
  control flow, macro expansion, SQL body semantics, dataflow, or alias-flow
- **THEN** the scanner MUST reject the source as unresolved when the construct
  is persistence-sensitive and otherwise leave it to the compiled audit

### Requirement: Conformance tests assert observable contracts

Architecture and conformance tests SHALL inspect parsed syntax for forbidden
source primitives, compiled BEAM imports/dependencies, configured Ash
resources, generated schemas, actual terminal database schema, or
consumer-visible behavior rather than synthetic evaluator semantics.

#### Scenario: Terminal database ownership is derived
- **WHEN** conformance compares database objects after real migrations run
- **THEN** it MUST derive terminal tables, columns, keys, constraints, indexes,
  sequences, views, materialized views, functions, procedures, ordinary,
  constraint, and event triggers, RLS policies and table enable/force state,
  grants, and extensions from the actual database and compare
  project-owned objects with Ash/resource ownership metadata, including
  normalized column type/default/nullability, key and constraint definitions,
  and index uniqueness/method/fields/null semantics

#### Scenario: Schema-qualified resources and composite references are derived
- **WHEN** resources use non-public schemas or references use multiple physical
  column pairs
- **THEN** conformance MUST key resources by schema-qualified table identity and
  require every terminal foreign-key pair to match the owning Ash `belongs_to`
  metadata, including configured `match_with` pairs

#### Scenario: Raw SQL changes ownership
- **WHEN** a migration attempts to create, alter, or drop schema ownership
  through SQL, helpers, external files, or unresolved dynamic constructs
- **THEN** conformance MUST reject the migration source before relying on
  terminal database state

#### Scenario: Relay resource conformance is checked
- **WHEN** the generated GraphQL resource surface is verified
- **THEN** the expected resource types MUST be derived from configured Ash
  resources and their schema objects MUST implement Relay Node without a
  separately maintained type-name list

#### Scenario: Stable projection Node behavior is checked
- **WHEN** a stable projection is accepted as a Relay Node
- **THEN** a behavior test MUST prove it can be refetched by opaque ID rather
  than a source-text regular expression asserting macro formatting

### Requirement: Project boundaries use canonical static analysis
Office Graph SHALL enforce planning and database-boundary policy through one
project-local, repository-wide Credo check. The check MUST preserve
Git-tracked source discovery, SQL-file coverage, deterministic inventory
comparison, compiled module auditing, and non-mutating behavior even when
those paths are outside Credo's configured Elixir source list.

#### Scenario: Canonical static analysis runs
- **WHEN** canonical verification invokes `mix credo --strict`
- **THEN** planning and database-boundary enforcement MUST run exactly once and report violations as normal Credo issues

#### Scenario: Focused project-boundary linting runs
- **WHEN** a contributor selects only the project-boundary Credo check
- **THEN** it MUST apply the same repository-wide source, compiled-module, and inventory semantics as canonical verification

#### Scenario: A source violation is found
- **WHEN** a new, changed, unresolved, or prohibited database occurrence is detected
- **THEN** the Credo issue MUST identify the actionable source path, diagnostic kind, and available line, construct, and fingerprint context

#### Scenario: A compiled violation is found
- **WHEN** a compiled project module imports or depends on a low-level database primitive without an approved source occurrence
- **THEN** the Credo issue MUST identify the module and imported or referenced primitive

#### Scenario: An inventory violation is found
- **WHEN** a database-access entry is stale or malformed
- **THEN** the Credo issue MUST identify the owning inventory and the stale locator or missing metadata

#### Scenario: Credo receives a narrowed source list
- **WHEN** Credo's configured or command-line source selection excludes migrations, seeds, SQL files, removed files, or planning paths
- **THEN** the project-boundary check MUST still evaluate the complete Git-tracked repository boundary

#### Scenario: Canonical verification is configured
- **WHEN** the Credo check has behavior parity with the existing boundary commands
- **THEN** canonical verification MUST remove the separate planning-boundary and database-boundary command invocations rather than scanning twice

### Requirement: Canonical verification proves migration baseline integrity

Canonical verification SHALL prove that AshPostgres resources, tracked
snapshots, the current migration baseline, terminal database objects, and
required application setup remain synchronized and usable on PostgreSQL 18.

#### Scenario: Resource and snapshot drift check runs

- **WHEN** the canonical gate validates the migration baseline
- **THEN** it MUST run AshPostgres migration generation in non-mutating check
  mode and fail on resource or snapshot drift

#### Scenario: Fresh baseline check runs

- **WHEN** canonical verification starts its isolated PostgreSQL 18 service
- **THEN** it MUST migrate an empty scratch database, run release setup twice,
  compare terminal project-owned database objects with Ash/resource ownership
  metadata, and verify representative Ash reads without running the complete
  ExUnit suite a second time

#### Scenario: Terminal database inventory is complete

- **WHEN** terminal migration-baseline verification inventories the migrated
  database
- **THEN** it MUST cover tables, columns, primary keys, foreign keys,
  constraints, indexes, sequences, views, materialized views,
  functions/procedures, triggers, RLS policies, grants, and extensions as
  applicable

#### Scenario: Baseline verification succeeds

- **WHEN** migration drift, terminal database inventory, and fresh
  baseline/setup checks pass from a clean checkout
- **THEN** the checks MUST leave the worktree clean and MUST NOT rewrite a
  migration, resource snapshot, inventory, or OpenSpec artifact

## REMOVED Requirements

### Requirement: Database boundary scanning resolves explicit aliases

**Reason**: Alias-flow source evaluation is replaced by a source primitive scan
plus post-compilation BEAM dependency/import audit.

**Migration**: Direct, fully qualified, aliased, and imported low-level
primitives remain prohibited; the compiled audit covers ordinary alias/import
spelling without a source-level alias evaluator.

### Requirement: Database boundary scanning resolves imported operations

**Reason**: Import-flow source evaluation is replaced by a source primitive scan
plus post-compilation BEAM dependency/import audit.

**Migration**: Imported low-level primitives remain prohibited and are detected
through source import declarations and BEAM import metadata.

### Requirement: Database boundary scanning classifies Ecto query fragments

**Reason**: Fragment detection is kept as a forbidden primitive instead of a
standalone symbolic query-helper evaluator.

**Migration**: `fragment` and `unsafe_fragment` remain prohibited unless exact
approved occurrences match current source fingerprints.

### Requirement: Database boundary scanning classifies repository connection ownership

**Reason**: Repository transaction and connection ownership are now part of the
general forbidden-primitive source/compiled gates.

**Migration**: `Repo.checkout`, `Repo.rollback`, `Repo.transaction`, and related
direct repository primitives remain prohibited unless exactly approved.

### Requirement: Database boundary scanning classifies Ecto.Multi database operations

**Reason**: `Ecto.Multi` database reads and writes are now part of the general
forbidden-primitive source/compiled gates.

**Migration**: Low-level `Ecto.Multi` database operations remain prohibited
unless exactly approved.
