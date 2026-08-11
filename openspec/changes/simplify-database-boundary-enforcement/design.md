## Context

Office Graph currently enforces database-boundary policy through one repository-wide Credo check backed by a large Elixir source scanner and a migration-conformance helper. The scanner attempts to symbolically model aliases, imports, callbacks, control flow, local helpers, module construction, macro expansion, SQL payloads, and migration table/FK lifecycle. PR 35 hardened several real gaps in that evaluator, but the architecture remains difficult to audit and encourages adding more interpretation whenever a new escape shape appears.

The approved direction keeps strict fail-closed enforcement and exact OpenSpec approval, but changes the implementation model. The gate should reject constructs whose safety depends on dataflow, callback, alias-flow, SQL-body, or control-flow evaluation rather than growing another interpreter.

Project constraints:

- OpenSpec remains the durable source of truth.
- Canonical project/runtime commands run through the pinned Nix flake.
- Repository-authored raw SQL requires exact user approval in an accepted OpenSpec change.
- The two existing UUIDv7 fragment exceptions must retain their exact fingerprints and provenance.

## Goals / Non-Goals

**Goals:**

- Preserve strict fail-closed enforcement for raw SQL, direct Ecto, migration SQL, and direct repository access.
- Preserve exact exception fingerprinting and invalidation, including when terminal schema output is unchanged.
- Preserve repository-wide coverage for every tracked Elixir and SQL-like source, including `lib`, tests, test support, Mix tasks, configuration, seeds, migrations, and scripts.
- Replace the current symbolic evaluator with four independent, comprehensible layers:
  1. forbidden-primitive source scan;
  2. post-compilation dependency/import audit;
  3. built-in AshPostgres migration drift check;
  4. terminal database-object comparison against Ash/resource ownership metadata.
- Fail closed on dynamic or complex migration/persistence constructs.
- Cover terminal project-owned database objects beyond tables and FKs.
- Require behavior tests for approved low-level exceptions.

**Non-Goals:**

- No new product behavior, schema migration, dependency, or public API.
- No repository-authored catalog SQL in this change.
- No replacement symbolic evaluator for callback, control-flow, alias-flow, SQL-body, or helper expansion.
- No approval for additional raw SQL occurrences.

## Decisions

### 1. Source scan bans primitives and dynamic escape shapes

The source layer scans every tracked `.ex`, `.exs`, and SQL-like project source regardless of its directory or extension casing, including runtime Elixir, tests, test support, Mix tasks, configuration, seeds, migrations, and scripts. It parses Elixir with `Code.string_to_quoted` for line metadata, but it does not evaluate helper bodies, callbacks, conditionals, quoted code, SQL strings, or macro output.

It reports exact occurrences for direct and imported uses of known low-level primitives: `OfficeGraph.Repo`, `Ecto.Adapters.SQL`, `Ecto.Migrator`, private migration execution namespaces such as `Ecto.Migration.Runner`, `Postgrex` including its Notifications and SimpleConnection execution namespaces, `Ecto.Multi`, local or qualified `Ecto.Query.API.fragment`/`unsafe_fragment`, SQL-bearing Ecto query options, migration `execute`/`execute_file`/`fragment`, migration SQL options, direct migration inserts, and repository transaction/connection control. SQL-like tracked files are raw-SQL occurrences by definition. Dynamic `apply`, module-function-argument process/task/RPC/`proc_lib`/`:erlang.hibernate` dispatch, statically visible Elixir and OTP supervisor child-spec start MFAs, EEx compilation/evaluation/function-definition entrypoints, Erlang expression evaluation including `:file.eval`/`script`/`path_eval`/`path_script`, `Code.eval_quoted_with_env`, `Kernel.ParallelCompiler` source-compilation entrypoints, dynamic receivers with database operations, `Module.concat`, external SQL files, repository variable receivers, direct repository calls inside migrations, nonliteral migration SQL-option containers, Elixir and Erlang runtime code loading, database-mutating CLI subprocesses, shell/interpreter dispatch, arbitrary migration helper calls, migration compile/verification callbacks, and migration branching/control flow including short-circuit operators are rejected as unresolved escape paths. Migration module bodies and transaction hooks are execution contexts subject to the same helper and control-flow restrictions as `change`, `up`, and `down`. Qualified `Ecto.Migration` calls receive the same enforcement as imported migration calls. Because tracked `.exs` files have no persisted application BEAM, and tracked `.ex` files outside compiler coverage may not have one, opaque dependency macro capabilities introduced through `require`, `import`, or `use` fail closed unless compiler-recorded BEAM source metadata proves the exact tracked path has compiled coverage or the provider is an explicitly recognized declarative framework surface; project-authored macro providers remain covered by their tracked source. The database-owned `pg_dump` inspection call remains statically visible and read-only; mutable PostgreSQL clients and shell dispatch that could conceal them fail closed, and read-only command seams require the exact executable spelling rather than a matching basename. The existing test-only invocation of the tracked canonical `bin/verify` script remains an exact source-path and argument-shape seam, not a general interpreter allowance, and exact SHA-256 fingerprints bind that seam to `bin/verify` and its invoked migration-baseline script. The three private `Kernel.ParallelCompiler.compile_to_path/3` helpers required to generate BEAM audit fixtures are independent exact OpenSpec exceptions with empty terminal-object inventories and focused scanner, gate, and Credo behavior tests. Each approved call directly contains its byte-hash guard and complete generated-source SHA-256 allowlist, so changing the guard, fixture input, compiled path, or allowlist invalidates the exact exception even when terminal schema is unchanged; any new path, locator, call shape, or generated-source fingerprint remains unresolved.

Alternative considered: retain symbolic expansion for statically provable constructs. Rejected because each extra evaluator rule creates another review surface and still cannot prove untaken runtime branches or transient data-plane behavior.

### 2. Compiled BEAM metadata audits aliases, imports, and dependencies

After current, test, and production compilation, the gate inspects application BEAM modules with `:beam_lib` and uses abstract code/import metadata to find calls and imports that source text might spell indirectly. It fails closed when any required environment has no project BEAM output. It reads each module's compiler-recorded source path and audits only artifacts backed by a currently tracked source, so deleted or renamed modules cannot produce stale results. This catches ordinary aliases and imported direct calls without implementing alias-flow or callback execution. Dynamic BEAM receivers, module-function-argument dispatch, generated functions in the canonical Repo source, and `apply` calls with statically visible database operations fail closed as a second defense; only exact AshPostgres-generated Repo function/arity and target-call shapes at the canonical macro expansion locator retain narrow call-level suppression. Source-to-BEAM reconciliation retains function provenance and never lets a primitive found only in quoted source data or nested beneath an opaque call whose compile-time behavior is not proven suppress a live compiled call. Missing abstract code also fails closed against the compiler-recorded source path so static-analysis diagnostics never attempt to parse a BEAM binary as Elixir.

Alternative considered: source-only scanning. Rejected because aliases and imports are common Elixir syntax and should be checked from compiler output where possible.

### 3. AshPostgres remains the migration drift source of truth

`mix ash_postgres.generate_migrations --check` stays in canonical verification. Generated drift is not interpreted by project code; the built-in AshPostgres check owns resource/snapshot drift detection.

Alternative considered: reimplementing generated migration comparison in project tests. Rejected because AshPostgres already owns that contract.

### 4. Terminal inventory uses database-owned schema dump tooling

The terminal comparison runs the real migrated test database and inspects `pg_dump --schema-only --no-owner` output. Privileges remain in the dump so direct and default-privilege grants are part of the inventory. The parser extracts project-owned object classes from the dump: regular, foreign, and unlogged tables, columns, primary keys, foreign keys, constraints, indexes, sequences, enum types, views, materialized views, functions/procedures, ordinary, constraint, and event triggers plus their non-default firing modes, RLS policies and table enable/force state, grants, and extensions. This avoids repository-authored catalog SQL while still testing the actual terminal database after migrations.

The comparison derives schema-qualified project-owned table identities, columns, key and constraint definitions, and identity/custom/reference index definitions from configured Ash and AshPostgres resource metadata, including explicit PostgreSQL migration types and migration-ignored attributes. Foreign-key and reference-index expectations are emitted only when every source, destination, and `match_with` attribute is migration-visible. Expected defaults mirror the pinned AshPostgres generator: unsupported nonempty map or array literals remain omitted unless the resource declares an explicit `migration_defaults` value. It compares normalized PostgreSQL 18 definitions for column type/default/nullability, primary and foreign keys, and index uniqueness/method/fields/null semantics, and pins the Oban job-state enum labels in order. Exact version-pinned shapes for present framework-owned tables and enums prevent their ownership exemption from hiding definition drift. Normalization only folds database-equivalent output forms such as public-schema qualification, identifier quoting, PostgreSQL-compatible UTF-8 byte clipping for every generated identifier, and pair ordering in composite foreign keys. The dump parser recognizes dollar quotes only at PostgreSQL token boundaries, preserves quoted identifiers that spell SQL keywords, and splits composite foreign-key identifiers only outside quoted tokens. Foreign-key conformance compares the complete physical source/destination column pair set, including configured `match_with` columns, and fails closed on unknown tables or attributes originating from a project-owned table. It also fails if an Ash-owned or present framework-owned object is absent, a definition differs, an unexpected object exists outside the exact database-owned set, or prohibited enum/routine/trigger/view/policy/grant objects appear without exact approval. Enum types participate in the same exact terminal-object approval schema as other prohibited stored behavior. Indexes on approved materialized views are independent exact terminal approval objects so subordinate behavior cannot change under an unchanged view fingerprint. A stored-object approval is nested under its exact source exception as a class, terminal identity, and SHA-256 fingerprint of the actual `pg_dump` statement; accepted-change evidence must mirror that record, and terminal verification fails when the object is missing or its definition changes. RLS table state is an accepted terminal approval class under the same exact fingerprint contract.

Alternative considered: direct `pg_catalog` SQL. Rejected for this change because project policy requires exact SQL occurrence approval before adding repository-authored SQL, and `pg_dump` gives enough terminal evidence without adding that approval surface.

### 5. Exact exception approvals remain source-bound

Approved low-level exceptions must continue to match the occurrence locator and fingerprint, with owner, reason, verification coverage, retirement condition, and an explicit `terminal_objects` list. An empty list records that the accepted occurrence owns no stored database object; omission is invalid rather than equivalent to no ownership. The source/compiled gates run even when the terminal schema is unchanged so rewritten SQL fragments, dynamic dispatch, locks, session commands, `NOTIFY`, or transient data-plane behavior cannot hide behind a final-schema comparison.

Alternative considered: approving terminal schema equivalence. Rejected because schema comparison does not prove data-plane, lock/session, notification, branch, or transient behavior.

### 6. Review hardening remains lexical and responsibility-bound

The source and compiled layers reject fully unresolved dispatch primitives even
when neither the target nor operation has a database-shaped variable name.
Repository-authored calls into private Ecto repository and PostgreSQL adapter
execution namespaces are low-level persistence primitives regardless of the
particular function name. Subprocess enforcement classifies launch mechanisms
and statically visible executable capabilities; it rejects dynamic executables,
shell and interpreter wrappers, and process ports instead of interpreting
command bodies or argument dataflow. A shallow module-local name/arity inventory
prevents unrelated local functions such as `fragment/1` from being classified as
Ecto calls without weakening explicit Ecto import and `use` contexts.

Terminal dump parsing uses a PostgreSQL-aware lexical layer only for statement
boundaries, Unicode and quoted identifiers, and quote-preserving definition normalization.
It does not evaluate SQL expressions or stored-routine bodies. Relation
persistence kind and sequence configuration/ownership remain part of the
terminal object definition, and normalization never changes bytes inside string
or dollar-quoted payloads.

Alternative considered: expand the scanner into a general Elixir or SQL
evaluator. Rejected because the approved architecture requires unresolved
execution paths to fail closed and terminal parsing to stay bounded to
database-owned `pg_dump` output.

## Risks / Trade-offs

- **Risk: simpler source scanning may report more violations than the old evaluator** -> Mitigation: this is intentional at persistence boundaries; dynamic or complex shapes must be rewritten to declarative Ash/AshPostgres/Ecto migration constructs or receive exact approval.
- **Risk: `pg_dump` text parsing may drift across PostgreSQL versions** -> Mitigation: canonical verification already requires PostgreSQL 18, and tests use representative dump snippets plus live schema checks.
- **Risk: external schema dump tooling might be unavailable outside the Nix shell** -> Mitigation: project commands run through the Nix flake, which pins the PostgreSQL 18 client; the terminal audit falls back to the PostgreSQL container's `pg_dump` when the local executable is unavailable or incompatible.
- **Risk: terminal inventory alone misses non-schema database behavior** -> Mitigation: source and compiled gates remain mandatory and run independently of the terminal comparison.

## Migration Plan

1. Add OpenSpec proposal, design, delta specs, and tasks; validate the active change strictly.
2. Add focused tests for the four replacement layers while the current gate remains active.
3. Implement small source, compiled, and terminal inventory modules and wire them through the existing Credo check.
4. Prove current repository parity, preserving the two UUIDv7 exceptions.
5. Delete the obsolete symbolic scanner and synthetic semantic tests after replacement tests pass.
6. Run focused tests and the full canonical `./bin/verify` in the Nix flake.

## Open Questions

- None. If a future change needs direct catalog SQL, that exact SQL occurrence must be proposed and explicitly approved in OpenSpec before implementation.
