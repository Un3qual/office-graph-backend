# backend-model-ownership Specification

## Purpose

Define the durable model ownership contract for Office Graph tables, Ash
domains/resources, direct Ecto exception control, and the architecture
conformance gate that keeps implementation and accepted OpenSpec evidence in
sync.
## Requirements
### Requirement: Durable Model Ash Ownership

Every durable table implemented by Office Graph SHALL have a canonical Ash
resource in the bounded context that owns its lifecycle.
`openspec/specs/backend-model-ownership/model-inventory.md` SHALL be the
normative inventory used by the architecture conformance gate, and SHALL
distinguish implemented migration-created tables from accepted planned MVP
resources that have not been migrated yet.

#### Scenario: A migration-created table is implemented

- **WHEN** a table exists in a committed migration for the backend
- **THEN** the table MUST be represented by exactly one canonical Ash resource
  module registered in exactly one owning Ash domain

#### Scenario: A table-backed model module exists

- **WHEN** production code under `lib/office_graph` defines a durable model
- **THEN** it MUST use `Ash.Resource` with `AshPostgres.DataLayer` rather than
  `Ecto.Schema`

#### Scenario: An existing model is promoted

- **WHEN** an existing manual Ecto schema is promoted to Ash
- **THEN** the existing canonical module path MUST become the Ash resource
  unless an OpenSpec design explicitly approves a different public module path

#### Scenario: A planned MVP resource is accepted before migration

- **WHEN** an accepted or active OpenSpec design requires a typed MVP resource
  that is not present in committed migrations yet
- **THEN** the model inventory MUST list the planned table, owning domain,
  canonical Ash resource, source spec, and implementation status without
  counting it as part of the implemented migration-created table inventory

### Requirement: No Duplicate Model Definitions

Office Graph SHALL avoid parallel model definitions for the same durable table.

#### Scenario: A table has an Ash resource

- **WHEN** a table is represented by an Ash resource
- **THEN** production code MUST NOT also define a manual Ecto schema for that
  table

#### Scenario: WorkGraph resources are converged

- **WHEN** WorkGraph resources are Ash-backed
- **THEN** they MUST be defined as `OfficeGraph.WorkGraph.GraphItem`,
  `OfficeGraph.WorkGraph.GraphRelationship`, `OfficeGraph.WorkGraph.Signal`,
  `OfficeGraph.WorkGraph.Task`, `OfficeGraph.WorkGraph.ReviewFinding`,
  `OfficeGraph.WorkGraph.VerificationCheck`, `OfficeGraph.WorkGraph.Artifact`,
  `OfficeGraph.WorkGraph.EvidenceItem`, and
  `OfficeGraph.WorkGraph.VerificationResult` rather than parallel
  `OfficeGraph.WorkGraph.Resources.*` modules

### Requirement: Direct Ecto Exception Control

Office Graph SHALL treat direct Ecto outside Ash-managed domain actions as
unapproved removal debt unless an accepted OpenSpec change documents the exact
missing Ash capability and bounded typed-Ecto exception. Repository-authored
raw SQL is prohibited unless the user explicitly approves the exact occurrence
in an accepted OpenSpec change.

#### Scenario: Existing direct database access remains

- **WHEN** a current direct-Ecto or raw-SQL occurrence has not received exact approval under the new boundary
- **THEN** it MUST appear only in the machine-readable removal-debt inventory with an owner and remediation change

#### Scenario: A normal mutation is implemented

- **WHEN** production code creates, updates, or deletes a durable domain record
- **THEN** it MUST use the owning Ash action, code interface, managed relationship, bulk action, or generic action rather than direct Ecto

### Requirement: Architecture Gate Covers Model Ownership

The backend verification gate SHALL fail when implementation, model ownership,
the database-access debt inventory, or the exact approved-exception inventory
diverge.

#### Scenario: Backend verification runs

- **WHEN** canonical project verification runs
- **THEN** it MUST verify table inventory, Ash domain and resource registration, absence of duplicate table-backed Ecto schemas, planned resource coverage, and exact non-growth of database-access debt

#### Scenario: Migration lifecycle uses qualified Ecto calls

- **WHEN** a forward migration invokes table lifecycle operations through
  `Ecto.Migration` or an explicit alias
- **THEN** canonical model-ownership verification MUST inventory the same table
  and foreign-key effects as the equivalent imported migration DSL calls

#### Scenario: Migration lifecycle uses pipeline syntax

- **WHEN** a forward migration pipes a table construct into a create, drop, or
  other supported lifecycle operation
- **THEN** canonical model-ownership verification MUST inventory the same table
  and foreign-key effects as the equivalent nested migration DSL call

#### Scenario: Migration lifecycle uses binary table names

- **WHEN** a forward migration creates, drops, alters, references, or renames a
  table using a binary name accepted by `Ecto.Migration`
- **THEN** canonical model-ownership verification MUST preserve that table
  identity and inventory the same lifecycle and foreign-key effects as the
  equivalent atom table name

#### Scenario: Migration creates a prefixed table

- **WHEN** a forward migration creates, drops, alters, references, or renames a
  table with a schema prefix
- **THEN** canonical model-ownership verification MUST preserve the schema in
  the table identity and compare it with the AshPostgres resource schema

#### Scenario: Ownership DDL separates keywords with SQL comments

- **WHEN** approved migration execution SQL contains table lifecycle or
  foreign-key DDL whose keywords are separated by line or block comments
- **THEN** canonical model-ownership verification MUST treat those comments as
  SQL whitespace and reject the unmodeled ownership change

#### Scenario: Ownership DDL is wrapped in an executable DO block

- **WHEN** approved migration execution SQL contains table lifecycle or
  foreign-key DDL inside a PostgreSQL `DO` block, including a statically quoted
  command passed directly to PL/pgSQL `EXECUTE`, used as the first template
  argument to `format`, or assembled from statically quoted concatenated command
  fragments
- **THEN** canonical model-ownership verification MUST inspect the executable
  block body and the executed command while continuing to ignore matching
  phrases in SQL comments, `format` data arguments, quoting-function arguments,
  and nested inert string literals, and MUST reject the unmodeled ownership
  change

#### Scenario: Ownership DDL is wrapped in a stored routine definition

- **WHEN** approved migration execution SQL defines a PostgreSQL procedure or
  function whose single-quoted or dollar-quoted body contains table lifecycle
  or foreign-key DDL
- **THEN** canonical model-ownership verification MUST inspect the routine body
  and reject the unmodeled ownership change while continuing to ignore matching
  phrases in comments and inert nested string literals

#### Scenario: Ownership DDL uses SELECT INTO table creation

- **WHEN** approved migration execution SQL uses PostgreSQL `SELECT ... INTO`
  to create a table directly or through a statically quoted dynamic `EXECUTE`
- **THEN** canonical model-ownership verification MUST reject the unmodeled
  table while leaving PL/pgSQL `SELECT ... INTO` variable assignment outside
  the table-ownership classification

#### Scenario: Ownership DDL imports a foreign schema

- **WHEN** approved migration execution SQL uses PostgreSQL
  `IMPORT FOREIGN SCHEMA` to create local foreign-table definitions
- **THEN** canonical model-ownership verification MUST reject the unmodeled
  table ownership change because declarative migration inventory cannot name
  the imported tables statically

#### Scenario: Migration try else selects a lifecycle branch

- **WHEN** a forward migration's `try` body has a statically resolvable result
  and its `else` clauses contain table or foreign-key lifecycle operations
- **THEN** canonical model-ownership verification MUST apply only the matching
  clause as definite and MUST retain schema state removed only by unmatched or
  unresolved clauses

#### Scenario: Migration lifecycle uses static apply

- **WHEN** a forward migration invokes an `Ecto.Migration` table lifecycle
  operation through a statically resolvable `Kernel.apply/3` or
  `:erlang.apply/3` call, including when the receiver or exported operation
  name comes from a sequentially resolved local binding
- **THEN** canonical model-ownership verification MUST normalize and inventory
  that lifecycle exactly as the equivalent direct call while leaving a matching
  shadowed local `apply/3` under ordinary local-function semantics

#### Scenario: Guarded migration entrypoint selects a lifecycle clause

- **WHEN** a public zero-arity `up` or `change` entrypoint has multiple clauses
  with guards
- **THEN** canonical model-ownership verification MUST inventory only the first
  statically matching clause and MUST fail closed when an earlier guard cannot
  be resolved statically or no entrypoint clause matches, instead of treating
  every clause body or a lower-precedence `change/0` entrypoint as definite

#### Scenario: Ownership DDL is loaded from a migration file

- **WHEN** a forward migration invokes `execute_file/1` or the forward path of
  reversible `execute_file/2`
- **THEN** canonical model-ownership verification MUST inspect the referenced
  tracked file contents and reject table lifecycle or foreign-key DDL that the
  declarative migration inventory cannot model

#### Scenario: Ownership DDL uses a repository query receiver

- **WHEN** a forward migration sends statically resolvable table lifecycle or
  foreign-key DDL through `repo().query/query!`, an Ecto SQL adapter, or a
  fully qualified or explicitly aliased repository module
- **THEN** canonical model-ownership verification MUST reject the unmodeled
  ownership change and require declarative migration constructs

#### Scenario: Migration delegates lifecycle work to a repository helper

- **WHEN** a forward migration invokes an imported, aliased, or fully
  qualified repository-authored helper, including a sibling module defined in
  the same migration file, whose lifecycle effects cannot be inventoried from
  the recognized migration module
- **THEN** canonical model-ownership verification MUST fail closed and require
  the declarative lifecycle constructs to remain visible to the migration
  inventory, while leaving dependency-owned migration entrypoints outside this
  repository-helper rule

### Requirement: Exception Ledger Is A Burn-Down Contract

Office Graph SHALL distinguish unapproved database-access removal debt from
accepted non-SQL architecture exceptions and explicitly approved raw-SQL
occurrences.

#### Scenario: Existing database debt is touched

- **WHEN** code covered by a database-access debt entry is moved, rewritten, broadened, or removed
- **THEN** verification MUST reject the stale or changed fingerprint until the same change removes or updates the debt through its owning remediation

#### Scenario: Database debt is retired

- **WHEN** a direct database, raw SQL, broad `authorize?: false`, or manual transaction path is replaced
- **THEN** tests MUST prove the replacement preserves or strengthens authorization, idempotency, concurrency, operation correlation, audit and revision behavior, and partial-commit safety

### Requirement: New Direct Database Paths Require Coverage

Office Graph SHALL reject new direct-Ecto occurrences by default and SHALL
reject every new repository-authored raw-SQL occurrence until the user
explicitly approves that exact occurrence in an accepted OpenSpec change.

#### Scenario: A direct-Ecto path is proposed

- **WHEN** implementation proposes direct Ecto without handwritten SQL
- **THEN** the design MUST first exhaust built-in Ash and AshPostgres behavior and document the exact missing capability before an exception can be accepted

#### Scenario: A raw-SQL occurrence is proposed

- **WHEN** implementation proposes a SQL query, fragment, unsafe fragment, migration execution, SQL-bearing DDL option, or tracked SQL file
- **THEN** implementation MUST stop until the user explicitly approves the exact occurrence and its verification and retirement metadata in OpenSpec

### Requirement: Broad Authorization Bypass Is Accounted For

Office Graph SHALL account for broad Ash authorization bypasses used inside
domain internals.

#### Scenario: `authorize?: false` is introduced

- **WHEN** production code adds or broadens `authorize?: false` or
  authorization-bypassing Ash reads/writes
- **THEN** the path MUST be inside an owning domain boundary, protected by an
  explicit public authorization check or private command invariant, and covered
  by architecture conformance or an exception ledger entry

#### Scenario: Internal command bypasses Ash policy

- **WHEN** an internal command bypasses Ash policy for a private action
- **THEN** the command MUST verify actor, scope, capability, operation context,
  and lifecycle invariants before the bypassed action runs

### Requirement: Model Ownership Gate Covers API Exposure

Office Graph SHALL include API exposure checks in model ownership verification.
`openspec/specs/backend-model-ownership/api-migration-ledger.md` SHALL be the
normative inventory of approved hand-written GraphQL and JSON surfaces.

#### Scenario: Ash resource is API-exposed

- **WHEN** an Ash resource is exposed through AshGraphql, AshJsonApi, or custom
  transport code
- **THEN** verification MUST confirm the resource has one canonical owning
  domain, public/private action posture is intentional, and API exposure does
  not bypass the owning domain lifecycle contract

#### Scenario: A hand-written API surface is declared

- **WHEN** production transport code declares a manual GraphQL root field, JSON
  route, or command serializer
- **THEN** architecture verification MUST discover it structurally and require
  an API migration ledger entry with owner, reason, replacement target,
  safety/parity tests, and retirement condition
