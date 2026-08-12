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
  of directory or extension casing, including compound SQL template suffixes,
  runtime code, tests, test support, Mix tasks, configuration, seeds,
  migrations, and scripts, while excluding dependency source and untracked
  build artifacts

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
  known repository, SQL adapter, Ecto.Migrator, Postgrex, Ecto.Multi, migration
  SQL, query fragment, SQL-bearing query lock or hint, migration expression
  field, SQL-bearing AshPostgres custom-index predicate or expression field,
  SQL-bearing AshPostgres resource-level calculation, identity predicate, or
  base filter,
  verbatim AshPostgres migration-default override, direct repository
  transaction/connection primitive, or mutable database CLI subprocess
- **THEN** the scanner MUST emit a fingerprinted occurrence requiring exact
  approval

#### Scenario: Database import excludes a local operation
- **WHEN** tracked source imports a database module with an arity-specific
  `except` list and defines or calls the excluded operation locally
- **THEN** the scanner MUST preserve the exclusion instead of classifying the
  local call as an imported database primitive

#### Scenario: Quoted definitions are inert
- **WHEN** tracked source contains a module or local function definition only
  inside quoted syntax
- **THEN** the scanner MUST NOT use that inert definition to trust an opaque
  provider or suppress a live migration primitive

#### Scenario: Nested project provider uses lexical module identity
- **WHEN** tracked source defines a shorthand `defmodule` inside another
  executable module body
- **THEN** project-provider trust MUST use the fully nested module identity and
  MUST NOT authorize an unrelated top-level dependency module with the same
  shorthand name

#### Scenario: Dynamic database operation survives compilation
- **WHEN** BEAM abstract code contains `apply`, module-function-argument
  process/task dispatch, or a dynamic receiver with a statically visible
  database operation
- **THEN** the compiled audit MUST reject the call as unresolved even when the
  source gate already reports its exact tracked-source occurrence

#### Scenario: Dispatch target and operation are both unresolved
- **WHEN** tracked source or BEAM abstract code invokes `apply`, function
  capture, or module-function-argument process/task dispatch with unresolved
  target and operation expressions
- **THEN** the scanner MUST reject the dispatch primitive without relying on
  database-shaped variable names or dataflow interpretation

#### Scenario: Function capture targets an execution namespace
- **WHEN** tracked source or BEAM abstract code captures a forbidden process or
  reflection operation, or captures a dynamic operation from one of those
  execution-capable namespaces
- **THEN** the scanner MUST reject the capture through the existing process or
  reflection inventory without interpreting later invocation dataflow

#### Scenario: Private persistence execution namespace is called
- **WHEN** repository-authored source or non-generated BEAM code directly calls
  a private Ecto repository, migration runner, or PostgreSQL adapter execution
  namespace
- **THEN** the scanner MUST classify the call as a low-level persistence
  primitive regardless of its function name

#### Scenario: Process launcher can conceal database execution
- **WHEN** tracked source or compiled code uses a dynamic executable, shell or
  interpreter wrapper, unknown command dispatcher, or process port
- **THEN** the scanner MUST reject the launcher without interpreting the
  command body while preserving only statically identified non-dispatch tools
  and the approved read-only `pg_dump` seam

#### Scenario: Runtime execution namespaces are audited
- **WHEN** tracked source or compiled code uses `Postgrex.Notifications`, an
  Erlang runtime code loader, code-path mutator, or expression evaluator, IEx
  compilation or recompilation helpers, `Mix.Tasks.Run`, `Mix.Tasks.Eval`, or `Mix.Task`
  dispatch, `Mix.Project.in_project/3,4`, every Agent MFA executor, exported
  `:erpc.execute_call/3,4` or `:erpc.execute_cast/3`, low-level `:elixir`
  quoted/form evaluation or `:elixir_compiler` execution, Erlang shell or
  `:compile` source compilation/loading, `Mix.install/1,2`,
  `:erlang.load_nif/2`,
  `Config.Reader` evaluation or nonliteral, relative, aliased-path, or external
  config reads, runtime macro expansion, Mix shell command execution including
  expression receivers returned by `Mix.shell/0`, untrusted or dynamic
  protocol derivation through `@derive`, any supported MFA-executing RPC form,
  `Postgrex.SimpleConnection`, `Ecto.Repo.Supervisor`, a statically visible
  supervisor child spec passed through `start_child`, `Supervisor.start_link/2`,
  or `Supervisor.child_spec/2`, including standard module and
  `{module, argument}` shorthands, a statically visible persistence callback
  module passed to `Supervisor.start_link/3`, `DynamicSupervisor.start_link/3`,
  or `:supervisor.start_link/2,3`, or a compile/verification callback attribute
  or Erlang `:core_transform`/`:parse_transform` compiler option in any tracked
  module
- **THEN** the scanner MUST reject the occurrence as an unresolved low-level
  persistence or runtime-execution path

#### Scenario: Compile-time file import is constrained
- **WHEN** tracked source invokes an IEx file-import helper or imports Config
  from a path that is external, untracked, or dynamically unresolved
- **THEN** the source scanner MUST reject the compile-time loader before macro
  expansion can erase its execution from compiled metadata
- **AND** `Config.import_config/1` MAY remain unreported only when its lexical
  target is a tracked project config source or the canonical tracked
  `config_env()` import in `config/config.exs`

#### Scenario: Mix project alias contains an executable escape
- **WHEN** the tracked `mix.exs` project `:aliases` configuration contains a
  static `cmd` task
- **THEN** the source scanner MUST emit a fingerprinted occurrence requiring
  exact approval without interpreting its shell body
- **AND** a statically visible database CLI in that command MUST be classified
  as raw SQL
- **AND** an inline `run -e` or `eval` task, dynamic command string, or dynamic
  command container MUST remain unresolved and unapprovable
- **AND** `mix do` task composition MUST remain unresolved instead of parsing
  or interpreting its nested task sequence
- **AND** ordinary static task aliases and static tracked `run` script paths
  MUST remain covered by their independently scanned implementations

#### Scenario: AshPostgres custom index contains authored SQL
- **WHEN** a tracked Ash resource declares a custom index with a SQL predicate,
  an expression field, or a nonliteral option container
- **THEN** the source scanner MUST emit an exact raw-SQL occurrence or fail the
  dynamic container closed without classifying unrelated application functions
  named `index`

#### Scenario: AshPostgres check constraint contains authored SQL
- **WHEN** a tracked Ash resource declares a check constraint with a static or
  dynamic `check` expression or a nonliteral option container
- **THEN** the source scanner MUST emit an exact raw-SQL occurrence or fail the
  dynamic container closed without classifying unrelated application functions
  named `check_constraint`

#### Scenario: AshPostgres migration default injects migration source
- **WHEN** a tracked Ash resource declares `migration_defaults` in its
  `postgres` section
- **THEN** the source scanner MUST fingerprint every static attribute override
  for exact approval and reject a dynamic value or option container without
  interpreting it or classifying unrelated application functions named
  `migration_defaults`

#### Scenario: AshPostgres resource setting contains authored SQL
- **WHEN** a tracked Ash resource declares `calculations_to_sql`,
  `identity_wheres_to_sql`, or `base_filter_sql` in its `postgres` section
- **THEN** the source scanner MUST fingerprint every static SQL value for exact
  approval and reject dynamic values or containers without classifying
  unrelated application functions with the same names

#### Scenario: AshPostgres custom statement contains authored SQL
- **WHEN** a tracked Ash resource declares `up` or `down` payloads inside
  `postgres.custom_statements`
- **THEN** the source scanner MUST fingerprint each static payload for exact
  approval and reject dynamic payloads or section containers without
  classifying unrelated application functions named `up` or `down`

#### Scenario: Wildcard import exposes an MFA dispatcher
- **WHEN** tracked source wildcard-imports a supported process, task,
  supervisor, RPC, timer, or `proc_lib` dispatcher and invokes its local MFA
  form
- **THEN** the source scanner MUST resolve the operation against that
  dispatcher's existing operation inventory and reject a database target

#### Scenario: Migration invokes an anonymous function
- **WHEN** a migration execution context invokes an anonymous function value
  whose behavior would require capture or value-flow interpretation
- **THEN** the scanner MUST reject the invocation as an unresolved helper call
  without attempting to trace the function value

#### Scenario: Tracked source invokes dependency macros
- **WHEN** any tracked source introduces an opaque dependency macro through
  `require`, `import`, or `use` outside exact trusted framework providers and
  tracked project-authored module definitions
- **THEN** the source gate MUST reject the capability without expanding or
  evaluating the macro, regardless of whether a matching BEAM exists, because
  compilation can erase transient macro side effects
- **AND** project-authored trust MUST come from the repository-wide tracked
  module-definition set rather than an `OfficeGraph` namespace prefix

#### Scenario: Canonical config read is source-anchored
- **WHEN** tracked source reads `config/config.exs` or `config/runtime.exs`
  through `Config.Reader`
- **THEN** the source gate MUST trust only an exact `Path.expand/2` form anchored
  to that source's `__DIR__` that resolves to the project-root file
- **AND** a relative literal, aliased path module, or resolved external path
  MUST remain unresolved

#### Scenario: Canonical verifier script changes
- **WHEN** the test-only canonical verifier subprocess seam still has its exact
  source locator and arguments but `bin/verify` or its invoked migration-baseline
  script differs from the reviewed content
- **THEN** the source gate MUST invalidate the exemption before executing the
  script

#### Scenario: Compiled environments are audited
- **WHEN** canonical verification reaches the compiled database-boundary audit
- **THEN** current, test, and production output MUST already exist and the audit
  MUST inspect their BEAMs when compiler-recorded source remains tracked
- **THEN** the audit MUST fail closed when any required environment has no
  project BEAM output

#### Scenario: Compiled metadata is unavailable
- **WHEN** a current tracked-source BEAM lacks auditable abstract code
- **THEN** the audit MUST fail closed with a diagnostic attached to the
  compiler-recorded Elixir source path rather than the binary artifact

#### Scenario: Canonical Repo contains generated dependency code
- **WHEN** a dependency macro emits a generated function in the canonical Repo
  source that calls a private persistence namespace
- **THEN** the compiled audit MUST inspect the generated function and preserve
  only the narrow call-level suppression for named AshPostgres Repo wrappers

#### Scenario: Inert text mentions SQL
- **WHEN** ordinary strings, comments, or documentation mention SQL phrases
  without being an argument or option to a classified executable primitive
- **THEN** the scanner MUST NOT report an occurrence solely from that inert text

#### Scenario: Local function shares a query primitive name
- **WHEN** a module defines and calls a local function or macro whose name and
  arity match an Ecto query primitive without importing or using the Ecto query
  context
- **THEN** the source scanner MUST treat the call as local and leave ordinary
  compiled dependency detection to the compiled audit

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
- **THEN** it MUST derive regular, foreign, unlogged, partitioned-parent, and
  attached-partition tables, columns, keys,
  constraints, indexes, sequences, enum types, views, materialized views,
  functions, procedures, ordinary, constraint, and event triggers and their
  firing modes, RLS policies and table enable/force state, direct and
  default-privilege grants, and extensions from the actual database and compare
  project-owned objects with Ash/resource ownership metadata, including
  normalized column type/default/nullability, key and constraint definitions,
  index uniqueness/method/fields/null semantics, configured PostgreSQL
  migration types, and exact shapes for present framework-owned tables

#### Scenario: Framework enum definition drifts
- **WHEN** the present Oban job-state enum has missing, added, or reordered labels
- **THEN** terminal conformance MUST report a framework enum definition mismatch,
  and non-framework enums MUST require an exact terminal-object approval

#### Scenario: Terminal definitions use quoted identifiers and literals
- **WHEN** `pg_dump` emits quoted schema or object identifiers, string or
  dollar-quoted payloads, named constraints, or schema-qualified custom types
- **THEN** conformance MUST preserve identifier and literal semantics while
  normalizing only database-equivalent spelling outside quoted payloads

#### Scenario: Relation and sequence definitions drift
- **WHEN** an owned relation changes between regular, unlogged, foreign,
  partitioned-parent, or attached-partition kind,
  or an owned sequence changes type, range, start, increment, min/max, cache,
  cycle, or column ownership
- **THEN** terminal conformance MUST report the definition mismatch even when
  the object identity is unchanged

#### Scenario: Schema-qualified resources and composite references are derived
- **WHEN** resources use non-public schemas or references use multiple physical
  column pairs
- **THEN** conformance MUST key resources by schema-qualified table identity and
  require every terminal foreign-key pair to match the owning Ash `belongs_to`
  metadata, including configured `match_with` pairs

#### Scenario: Relationship attributes are excluded from migrations
- **WHEN** a belongs-to source, destination, or `match_with` attribute is listed
  in its resource's `migration_ignore_attributes`
- **THEN** conformance MUST omit the foreign-key and reference-index expectation
  derived from that relationship

#### Scenario: Generated identifier truncation crosses a multibyte character
- **WHEN** PostgreSQL shortens an automatically generated constraint, index, or
  sequence identifier whose component names contain multibyte UTF-8 characters
- **THEN** conformance MUST apply the PostgreSQL byte budget while clipping only
  at complete UTF-8 codepoint boundaries

#### Scenario: Generated sequence identity contains an apostrophe
- **WHEN** a generated integer sequence identity contains an apostrophe
- **THEN** expected and dumped `regclass` defaults MUST preserve the identifier
  while escaping the apostrophe as a PostgreSQL string literal

#### Scenario: Quoted identifier contains delimiter or keyword text
- **WHEN** a valid quoted column is named `constraint`, contains a comma in a
  composite foreign key, or an unquoted identifier contains dollar-quote-shaped
  suffix text
- **THEN** terminal parsing MUST preserve the identifier token and MUST NOT treat
  its contents as a declaration keyword, list delimiter, or dollar-quote opener

#### Scenario: Approved project enum is inventoried
- **WHEN** an accepted change approves a non-framework enum type as an exact
  terminal object
- **THEN** the approval inventory MUST accept the `enum` class and terminal
  conformance MUST still require its exact identity and statement fingerprint

#### Scenario: Built-in migration type remains catalog-owned
- **WHEN** an AshPostgres resource configures a PostgreSQL 18 built-in migration
  type or alias such as `:smallint`, `:oid`, or `:regclass`
- **THEN** terminal conformance MUST compare its canonical unqualified
  `pg_catalog` type while continuing to resource-schema-qualify unknown custom
  type atoms

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

#### Scenario: A compiled boundary module is already loaded
- **WHEN** Credo starts after an older project-boundary BEAM has been loaded
- **THEN** the standalone static-analysis workflow MUST first force-compile the
  production environment and then the current checked-out test boundary
  sources with warnings as errors
- **AND** Credo configuration MUST avoid redefining the resulting modules so
  compiled-audit BEAM provenance remains available
- **AND** canonical verification MUST build production BEAMs before static
  analysis invokes the compiled audit

#### Scenario: A source violation is found
- **WHEN** a new, changed, unresolved, or prohibited database occurrence is detected
- **THEN** the Credo issue MUST identify the actionable source path, diagnostic kind, and available line, construct, and fingerprint context

#### Scenario: A compiled violation is found
- **WHEN** a compiled project module imports or depends on a low-level database primitive without an approved source occurrence
- **THEN** the Credo issue MUST identify the module and imported or referenced primitive

#### Scenario: Quoted source and compiled execution collide
- **WHEN** quoted source data and a live compiled primitive share a source line,
  class, and construct
- **THEN** the quoted occurrence MUST NOT suppress the compiled diagnostic, and
  source-to-BEAM matching MUST retain enclosing function provenance

#### Scenario: Opaque expansion replaces an approved source call
- **WHEN** a low-level source primitive is nested beneath a call whose
  compile-time behavior the scanner cannot prove, and compiled code reports a
  primitive at the same source locator
- **THEN** the nested source occurrence MUST NOT suppress the compiled diagnostic,
  even when the source occurrence has an exact approval

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
  constraints, indexes, sequences, enum types, views, materialized views,
  functions/procedures, triggers, RLS policies, grants, and extensions as
  applicable

#### Scenario: Database dump falls back to a container
- **WHEN** the local PostgreSQL dump command fails and the configured database
  host is loopback
- **THEN** verification MAY use only the current Compose project's `postgres`
  service container
- **AND** a non-loopback configured host MUST surface the original dump failure
  without querying Docker
- **AND** verification MUST NOT select an unrelated local container by port

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
