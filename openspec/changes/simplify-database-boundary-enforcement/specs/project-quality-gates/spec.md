## ADDED Requirements

### Requirement: Compiled database auditing uses direct dependency evidence

Canonical verification SHALL inspect compiler-recorded source and BEAM import
metadata for tracked project modules after test and production compilation.

#### Scenario: Alias or import compiles to a low-level call

- **WHEN** ordinary source aliasing, importing, or macro expansion produces a
  direct call to a classified database module
- **THEN** the compiled audit MUST report that resolved module, function, arity,
  caller module, and tracked source path unless source approval or structural
  ownership permits it

#### Scenario: Compiled metadata is unavailable

- **WHEN** a tracked project BEAM lacks readable import or compiler source
  metadata
- **THEN** canonical verification MUST fail instead of silently omitting that
  module from the audit

#### Scenario: Generic callback remains generic

- **WHEN** compiled code imports only a generic callback, process, reflection,
  compiler, RPC, or shell function
- **THEN** the compiled database audit MUST NOT classify that import without a
  direct classified database dependency

## MODIFIED Requirements

### Requirement: Non-growing database-boundary debt

Canonical verification SHALL compare finite direct source occurrences and
compiled project-module dependencies with the exact approved exception
inventory and SHALL reject every unmatched occurrence or stale approval.

#### Scenario: New repository-authored SQL is added

- **WHEN** verification detects a raw-SQL or direct-Ecto occurrence that does
  not exactly match an explicitly approved exception
- **THEN** verification fails with the occurrence path, construct, and class

#### Scenario: Approved occurrence is removed or changed

- **WHEN** implementation removes, moves, rewrites, broadens, or changes the
  approved static context of an approved occurrence
- **THEN** verification fails until the stale approval is removed or the exact
  changed occurrence receives user approval through an accepted OpenSpec change

#### Scenario: SQL adapter execution spelling changes

- **WHEN** a caller invokes a classified SQL adapter operation through an
  explicit alias or import
- **THEN** source or compiled direct-dependency evidence MUST classify the same
  low-level operation as its fully qualified spelling

#### Scenario: Verification examines project scope

- **WHEN** the source scan runs
- **THEN** it MUST include all tracked Elixir and SQL-like runtime, test,
  support, Mix task, configuration, seed, migration, and script sources while
  excluding dependency and build artifacts

#### Scenario: Tracked script invokes a database client

- **WHEN** a tracked shell or `bin/` script directly names a PostgreSQL client
  command
- **THEN** the source gate MUST reject the command without interpreting shell
  variables or control flow

#### Scenario: Verification runs from a clean checkout

- **WHEN** planning and database-boundary checks complete
- **THEN** they MUST NOT rewrite an inventory, source, or OpenSpec artifact

### Requirement: Database scanner classifies executable syntax

The project-local source scanner SHALL classify explicit low-level database
calls and SQL-bearing DSL constructs without interpreting application dataflow,
callback behavior, helper bodies, process state, or generic runtime execution.

#### Scenario: Explicit low-level primitive is present

- **WHEN** tracked source directly or through a static alias/import invokes
  OfficeGraph.Repo, Ecto SQL or migration APIs, Postgrex, DBConnection,
  Ecto.Multi, a query fragment, or a listed SQL-bearing Ecto/AshPostgres DSL
  setting
- **THEN** the scanner MUST emit a deterministic occurrence containing the
  source path, line, enclosing function, class, construct, ordinal, and exact
  source fingerprint

#### Scenario: SQL payload is dynamic

- **WHEN** a direct raw-SQL primitive receives a payload that is not a complete
  static literal at the occurrence
- **THEN** the scanner MUST report the occurrence as unapprovable rather than
  evaluating helpers, variables, environment values, or files

#### Scenario: Migration uses nondeclarative syntax

- **WHEN** a migration entrypoint invokes an arbitrary helper, control-flow
  branch, external SQL file, direct repository call, or dynamic SQL-bearing
  option outside the exact UUIDv7 contexts
- **THEN** the scanner MUST fail closed without interpreting that construct

#### Scenario: Inert syntax mentions a primitive

- **WHEN** a comment, documentation string, ordinary binary, or quoted syntax
  mentions SQL or a database API without executing it
- **THEN** the scanner MUST NOT report an occurrence

#### Scenario: Generic execution has no direct database target

- **WHEN** source invokes a callback, process, compiler, reflection, RPC, or
  shell API without a statically direct database primitive
- **THEN** the scanner MUST leave that concern outside the database boundary

### Requirement: Canonical verification proves migration baseline integrity

Canonical verification SHALL prove that AshPostgres resources, tracked
snapshots, migrations, release setup, and the terminal PostgreSQL 18 object
inventory remain synchronized.

#### Scenario: Resource and snapshot drift check runs

- **WHEN** the canonical gate validates the migration baseline
- **THEN** it MUST run AshPostgres migration generation in non-mutating check
  mode and fail on resource or snapshot drift

#### Scenario: Fresh baseline check runs

- **WHEN** canonical verification starts its isolated PostgreSQL 18 service
- **THEN** it MUST migrate an empty scratch database, run release setup twice,
  and verify representative Ash reads without running the complete ExUnit suite
  a second time

#### Scenario: Terminal objects are compared

- **WHEN** the fresh baseline is ready
- **THEN** verification MUST compare project-owned schemas, relations, columns,
  keys, constraints, indexes, sequences, enums, views, materialized views,
  routines, triggers, RLS state and policies, grants, and extensions with
  resource ownership and approved exception metadata

#### Scenario: Baseline verification succeeds

- **WHEN** migration drift, setup, and terminal inventory checks pass from a
  clean checkout
- **THEN** the checks MUST leave the worktree clean and MUST NOT rewrite a
  migration, resource snapshot, inventory, or OpenSpec artifact
