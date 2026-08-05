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
Canonical verification SHALL compare current tracked project sources with the
exact explicitly approved raw-SQL and direct-Ecto exception inventory and SHALL
reject every unmatched occurrence or stale approved exception.

#### Scenario: New repository-authored SQL is added

- **WHEN** verification detects a raw-SQL or direct-Ecto occurrence that does
  not exactly match an explicitly approved exception
- **THEN** verification fails with the occurrence path and construct class

#### Scenario: Approved occurrence is removed or changed

- **WHEN** implementation removes, moves, rewrites, or broadens an approved
  occurrence
- **THEN** verification fails until the stale approval is removed or the exact
  changed occurrence receives user approval through an accepted OpenSpec change

#### Scenario: SQL adapter execution spelling changes

- **WHEN** tracked code calls a public Postgrex or Ecto SQL-adapter API that
  queries, prepares, executes, or streams SQL through a fully qualified,
  aliased, or imported receiver
- **THEN** the database-boundary scanner MUST classify the call as repository-authored raw SQL

#### Scenario: Ecto SQL adapter explains a generated query

- **WHEN** tracked code calls `Ecto.Adapters.SQL.explain` through a fully
  qualified, aliased, or imported receiver
- **THEN** the database-boundary scanner MUST classify the call as direct Ecto
  access without treating its generated query as repository-authored raw SQL

#### Scenario: Ecto SQL adapter checks out a connection

- **WHEN** tracked code calls `Ecto.Adapters.SQL.checkout` through a fully
  qualified, aliased, or imported receiver
- **THEN** the database-boundary scanner MUST classify the call as direct Ecto
  connection access

#### Scenario: Verification examines project scope

- **WHEN** the database-boundary scan runs
- **THEN** it MUST include tracked runtime code, tests, test support, seeds,
  migrations, and SQL files while excluding dependency source and untracked
  build artifacts

#### Scenario: Verification runs from a clean checkout

- **WHEN** the planning and database-boundary checks complete
- **THEN** they MUST NOT rewrite an inventory, source file, or OpenSpec artifact

### Requirement: Database scanner classifies executable syntax

The project-local database-boundary scanner SHALL classify executable
repository calls and SQL-bearing migration constructs rather than unrelated
binary literals or documentation text.

#### Scenario: Migration documentation mentions SQL

- **WHEN** a migration module attribute or other non-executed literal mentions
  `insert into`, `md5(`, or another SQL phrase
- **THEN** the scanner MUST NOT report an occurrence unless that literal is an
  argument or option value of a classified executable SQL-bearing construct

#### Scenario: SQL-bearing migration option uses a module attribute

- **WHEN** a classified migration `check` or `where` option references a module
  attribute containing SQL
- **THEN** the scanner MUST resolve that attribute for both classification and
  occurrence fingerprinting so changing the SQL invalidates the exact approval

#### Scenario: SQL payload uses an accumulated module attribute

- **WHEN** a SQL-bearing call references a module attribute registered with
  `accumulate: true`
- **THEN** the scanner MUST fingerprint every accumulated value in compiler
  order, and MUST reject exact approval when accumulation semantics cannot be
  determined statically

#### Scenario: SQL payload contains literal interpolation

- **WHEN** a classified raw-SQL payload interpolates only statically resolvable
  literal values
- **THEN** the scanner MUST retain the exact interpolation AST in its
  fingerprint and allow exact approval while continuing to reject payloads
  that interpolate runtime values

#### Scenario: Static callback receives a database receiver

- **WHEN** a direct literal-function invocation, a known Kernel value callback,
  or a supported `Enum` operation, including predicate overloads such as
  `take_while/2`, passes a statically resolvable repository receiver into a
  literal `fn`, positional capture callback pattern, or captured local function,
  including through a match or assignment expression evaluated as the callback
  argument or through an explicit static `Enum` accumulator
- **THEN** the scanner MUST normalize positional and matching local-function
  captures without executing source, bind the callback pattern before
  classifying and fingerprinting database calls in its body, bind independently
  known callback parameters even when another parameter is dynamic, and MUST
  NOT assume Kernel or `Enum` callback semantics when the receiver resolves to
  an unrelated local, imported, or qualified function

#### Scenario: Static local helper receives a database receiver

- **WHEN** a matching local function is called with a statically resolvable
  repository or `Ecto.Multi` receiver and its body invokes a classified
  database operation through that parameter
- **THEN** the scanner MUST bind the local parameters and classify and
  fingerprint the helper body without executing source, while bounding
  recursive helper expansion

#### Scenario: Static comprehension enumerates database receivers

- **WHEN** a `for` comprehension enumerates a statically resolvable list that
  contains one or more receiver spellings accepted by database-operation
  classification, including bare `Repo` and `Multi`
- **THEN** the scanner MUST evaluate the body under every distinct statically
  matching generator binding, classify database calls for the matching
  receiver values, and omit statically impossible pattern branches

#### Scenario: Database apply target is static but invocation data is unresolved

- **WHEN** `Kernel.apply/3` or `:erlang.apply/3` statically targets a known
  repository, Ecto, migration, SQL-adapter, or Postgrex module while its
  operation or argument list remains runtime-provided
- **THEN** the scanner MUST retain the known database target, classify any
  statically known operation, and fail closed for a dynamic operation that
  could execute repository-authored SQL

#### Scenario: Dynamic apply targets the Ecto query builder

- **WHEN** `Kernel.apply/3` or `:erlang.apply/3` statically targets
  `Ecto.Query` while its operation or argument list remains runtime-provided
- **THEN** the scanner MUST NOT classify the call as database access solely
  because `Ecto.Query` constructs queries without executing them

#### Scenario: Static apply invokes migration constructs with SQL options

- **WHEN** `Kernel.apply/3` or `:erlang.apply/3` statically invokes an
  `Ecto.Migration` create operation whose index, constraint, table, or generated
  column construct contains an executable SQL-bearing option or expression
- **THEN** the scanner MUST classify and fingerprint the SQL-bearing construct
  from the normalized invocation exactly as it does for a direct migration call

#### Scenario: Reversible migration execute carries two commands

- **WHEN** a migration uses `execute(up_command, down_command)`
- **THEN** both executable commands MUST be statically fingerprintable before
  the occurrence can receive an exact raw-SQL approval

#### Scenario: Migration executes SQL from files

- **WHEN** a migration uses `execute_file/1` or reversible `execute_file/2`
  through an imported, aliased, or fully qualified migration receiver
- **THEN** the scanner MUST classify the call as repository-authored raw SQL
  and require every executable path to remain inside the project root and
  resolve to a tracked project file whose contents participate in the
  occurrence fingerprint before the occurrence can receive an exact approval

#### Scenario: External migration helper invokes an explicit SQL API

- **WHEN** tracked code outside `priv/repo/migrations` invokes
  `Ecto.Migration.execute` or `Ecto.Migration.fragment` through a fully
  qualified, aliased, or imported receiver
- **THEN** the scanner MUST classify that explicit SQL-bearing call exactly as
  it would inside a migration file

#### Scenario: Block-form table creation carries SQL options

- **WHEN** an unqualified, aliased, or fully qualified migration `create`
  operation receives a table construct with raw `options` or `modifiers` and a
  trailing `do` block
- **THEN** the scanner MUST classify each SQL-bearing table option without
  treating the trailing block as part of the construct identity or payload

#### Scenario: Migration construction uses pipeline syntax

- **WHEN** a migration pipes an index, constraint, or table construct into an
  unqualified, aliased, or fully qualified creation operation
- **THEN** the scanner MUST classify and fingerprint the executable construct
  exactly as it does for the equivalent nested call

#### Scenario: Migration index carries raw expression fields

- **WHEN** an index or unique-index construct includes a string expression
  field or a field whose safety cannot be resolved statically
- **THEN** the scanner MUST classify the field as repository-authored raw SQL,
  bind its fingerprint to the enclosing index target and field position, and
  reject exact approval for unresolved fields while leaving atom column fields
  unclassified

#### Scenario: Generated column carries a SQL expression

- **WHEN** a migration table block uses `add` or `modify` with a `generated`
  expression
- **THEN** the scanner MUST classify the expression as repository-authored SQL,
  bind its fingerprint to the enclosing table and column, and reject an
  expression that cannot be resolved statically

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

#### Scenario: Migration table ownership is derived

- **WHEN** conformance derives tables created by ordered forward migrations
- **THEN** it MUST parse executable `create table` and `drop table` calls from
  quoted AST, including multiline calls, while ignoring comments, strings, and
  rollback-only functions

#### Scenario: Raw SQL changes foreign-table ownership

- **WHEN** a statically resolvable migration execution creates, alters, or drops
  a PostgreSQL foreign table
- **THEN** conformance MUST reject the SQL and require declarative migration
  constructs rather than omitting the table from the ownership inventory

#### Scenario: Relay resource conformance is checked

- **WHEN** the generated GraphQL resource surface is verified
- **THEN** the expected resource types MUST be derived from configured Ash
  resources and their schema objects MUST implement Relay Node without a
  separately maintained type-name list

#### Scenario: Stable projection Node behavior is checked

- **WHEN** a stable projection is accepted as a Relay Node
- **THEN** a behavior test MUST prove it can be refetched by opaque ID rather
  than a source-text regular expression asserting macro formatting

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

### Requirement: Canonical verification proves migration baseline integrity

Canonical verification SHALL prove that AshPostgres resources, tracked
snapshots, the current migration baseline, and required application setup
remain synchronized and usable on PostgreSQL 18.

#### Scenario: Resource and snapshot drift check runs

- **WHEN** the canonical gate validates the migration baseline
- **THEN** it MUST run AshPostgres migration generation in non-mutating check
  mode and fail on resource or snapshot drift

#### Scenario: Fresh baseline check runs

- **WHEN** canonical verification starts its isolated PostgreSQL 18 service
- **THEN** it MUST migrate an empty scratch database, run release setup twice,
  and verify representative Ash reads without running the complete ExUnit
  suite a second time

#### Scenario: Baseline verification succeeds

- **WHEN** migration drift and fresh baseline/setup checks pass from a clean
  checkout
- **THEN** the checks MUST leave the worktree clean and MUST NOT rewrite a
  migration, resource snapshot, inventory, or OpenSpec artifact

### Requirement: Database boundary scanning resolves explicit aliases

The project-local database-boundary scanner SHALL recognize explicitly aliased
repository receivers before classifying raw SQL and direct Ecto calls.

#### Scenario: Repository is renamed with an alias

- **WHEN** tracked Elixir source aliases `OfficeGraph.Repo` to another valid
  module name and invokes a prohibited repository operation through that alias
- **THEN** the canonical Credo boundary check MUST report the same raw-SQL or
  direct-Ecto occurrence it would report for `Repo`

#### Scenario: Unrelated receiver has a database-like function name

- **WHEN** source calls `query`, `query!`, or another classified operation on a
  receiver that is not `OfficeGraph.Repo` or its explicit alias
- **THEN** the scanner MUST NOT classify that call as repository database
  access solely from the function name

#### Scenario: Aliases remain within their lexical scope

- **WHEN** a repository alias is followed by a sibling or nested lexical scope
  that does not inherit it or explicitly shadows it with a non-database module
- **THEN** the scanner MUST classify calls using the repository alias only
  where that alias is active and MUST restore the enclosing alias after leaving
  a nested scope

### Requirement: Database boundary scanning resolves imported operations

The project-local database-boundary scanner SHALL recognize local calls that
resolve to imported database operations, including import name and arity
filters.

#### Scenario: SQL adapter query is imported

- **WHEN** tracked Elixir source imports `Ecto.Adapters.SQL.query/3` and invokes
  `query/3` as a local call
- **THEN** the canonical Credo boundary check MUST report the same raw-SQL
  occurrence it would report for `Ecto.Adapters.SQL.query/3`

#### Scenario: Database imports remain within their lexical scope

- **WHEN** an imported database operation is invoked in its declaring scope and
  a same-named local call appears in an unrelated sibling scope
- **THEN** the scanner MUST classify only the call whose lexical import resolves
  to the database operation

### Requirement: Database boundary scanning classifies Ecto query fragments

The project-local database-boundary scanner SHALL classify repository-authored Ecto query fragments as raw SQL regardless of whether the fragment macro is called locally, fully qualified, or through an explicit alias.

#### Scenario: Ecto query fragment is fully qualified

- **WHEN** tracked Elixir source calls `Ecto.Query.API.fragment`, `Ecto.Query.API.unsafe_fragment`, or the same operation through an explicit alias
- **THEN** the canonical Credo boundary check MUST report a raw-SQL occurrence requiring the same exact approval as a locally imported fragment

#### Scenario: Unrelated module defines a fragment function

- **WHEN** tracked source calls `fragment` on a receiver that does not resolve to the Ecto query API
- **THEN** the scanner MUST NOT classify the call solely from the operation name

### Requirement: Database boundary scanning classifies repository connection ownership

The project-local database-boundary scanner SHALL classify explicit connection
and transaction control through the Office Graph repository as direct Ecto
access.

#### Scenario: Repository connection is checked out

- **WHEN** tracked Elixir source calls `OfficeGraph.Repo.checkout` directly or
  through an explicit repository alias
- **THEN** the canonical Credo boundary check MUST report the call as direct
  Ecto access requiring an inventory entry or removal

#### Scenario: Repository transaction is rolled back

- **WHEN** tracked Elixir source calls `OfficeGraph.Repo.rollback` directly or
  through an explicit repository alias
- **THEN** the canonical Credo boundary check MUST report the call as direct
  Ecto access requiring an inventory entry or removal

#### Scenario: Unrelated connection-control function is called

- **WHEN** tracked Elixir source calls `checkout` or `rollback` on a receiver
  that does not resolve to `OfficeGraph.Repo`
- **THEN** the database-boundary scanner MUST NOT classify the call solely from
  its function name

### Requirement: Database boundary scanning classifies Ecto.Multi database operations

The project-local database-boundary scanner SHALL classify database-reading and
database-changing operations composed through `Ecto.Multi` as direct Ecto
access while resolving the operation receiver before classification.

#### Scenario: Ecto.Multi composes database reads

- **WHEN** tracked Elixir source calls `Ecto.Multi.all`, `Ecto.Multi.one`, or
  `Ecto.Multi.exists?` through a fully qualified or explicitly aliased receiver
- **THEN** the canonical Credo boundary check MUST report each call as direct
  Ecto access requiring an inventory entry or removal

#### Scenario: Unrelated multi-like receiver reads data

- **WHEN** tracked Elixir source calls `all`, `one`, or `exists?` on a receiver
  that does not resolve to `Ecto.Multi`
- **THEN** the database-boundary scanner MUST NOT classify the call solely from
  its function name
