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
- Preserve repository-wide tracked-source coverage for `lib`, tests, test support, Mix tasks, seeds, migrations, and SQL-like files.
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

The source layer scans every tracked project source whose path can express persistence behavior: runtime Elixir, tests, test support, Mix tasks, seeds, migrations, and tracked SQL-like files. It parses Elixir with `Code.string_to_quoted` for line metadata, but it does not evaluate helper bodies, callbacks, conditionals, quoted code, SQL strings, or macro output.

It reports exact occurrences for direct and imported uses of known low-level primitives: `OfficeGraph.Repo`, `Ecto.Adapters.SQL`, `Postgrex`, `Ecto.Multi`, `Ecto.Query.API.fragment`/`unsafe_fragment`, SQL-bearing Ecto query options, migration `execute`/`execute_file`/`fragment`, migration SQL options, direct migration inserts, and repository transaction/connection control. SQL-like tracked files are raw-SQL occurrences by definition. Dynamic `apply`, dynamic receivers with database operations, `Module.concat`, external SQL files, repository variable receivers, direct repository calls inside migrations, reflection, arbitrary migration helper calls, and migration branching/control flow including short-circuit operators are rejected as unresolved escape paths. Qualified `Ecto.Migration` calls receive the same enforcement as imported migration calls.

Alternative considered: retain symbolic expansion for statically provable constructs. Rejected because each extra evaluator rule creates another review surface and still cannot prove untaken runtime branches or transient data-plane behavior.

### 2. Compiled BEAM metadata audits aliases, imports, and dependencies

After compilation, the gate inspects application BEAM modules with `:beam_lib` and uses abstract code/import metadata to find calls and imports that source text might spell indirectly. This catches ordinary aliases and imported direct calls without implementing alias-flow or callback execution. Dynamic BEAM receivers and `apply` calls with statically visible database operations fail closed as a second defense, while the source layer preserves the exact tracked-source occurrence.

Alternative considered: source-only scanning. Rejected because aliases and imports are common Elixir syntax and should be checked from compiler output where possible.

### 3. AshPostgres remains the migration drift source of truth

`mix ash_postgres.generate_migrations --check` stays in canonical verification. Generated drift is not interpreted by project code; the built-in AshPostgres check owns resource/snapshot drift detection.

Alternative considered: reimplementing generated migration comparison in project tests. Rejected because AshPostgres already owns that contract.

### 4. Terminal inventory uses database-owned schema dump tooling

The terminal comparison runs the real migrated test database and inspects `pg_dump --schema-only --no-owner` output. Privileges remain in the dump so grants are part of the inventory. The parser extracts project-owned object classes from the dump: tables, columns, primary keys, foreign keys, constraints, indexes, sequences, views, materialized views, functions/procedures, triggers, RLS policies, grants, and extensions. This avoids repository-authored catalog SQL while still testing the actual terminal database after migrations.

The comparison derives expected project-owned tables, columns, key and constraint definitions, and identity/custom/reference index definitions from configured Ash and AshPostgres resource metadata. It compares normalized PostgreSQL 18 definitions for column type/default/nullability, primary and foreign keys, and index uniqueness/method/fields/null semantics. Normalization only folds database-equivalent output forms such as public-schema qualification, identifier quoting, automatically named `NOT NULL` constraints, and pair ordering in composite foreign keys. It fails if an Ash-owned object is absent, a definition differs, an unexpected object exists outside the allowed database-owned set, a terminal foreign key lacks the matching Ash relationship, or prohibited stored routines/triggers/views/policies/grants appear without exact approval.

Alternative considered: direct `pg_catalog` SQL. Rejected for this change because project policy requires exact SQL occurrence approval before adding repository-authored SQL, and `pg_dump` gives enough terminal evidence without adding that approval surface.

### 5. Exact exception approvals remain source-bound

Approved low-level exceptions must continue to match the occurrence locator and fingerprint, with owner, reason, verification coverage, and retirement condition. The source/compiled gates run even when the terminal schema is unchanged so rewritten SQL fragments, dynamic dispatch, locks, session commands, `NOTIFY`, or transient data-plane behavior cannot hide behind a final-schema comparison.

Alternative considered: approving terminal schema equivalence. Rejected because schema comparison does not prove data-plane, lock/session, notification, branch, or transient behavior.

## Risks / Trade-offs

- **Risk: simpler source scanning may report more violations than the old evaluator** -> Mitigation: this is intentional at persistence boundaries; dynamic or complex shapes must be rewritten to declarative Ash/AshPostgres/Ecto migration constructs or receive exact approval.
- **Risk: `pg_dump` text parsing may drift across PostgreSQL versions** -> Mitigation: canonical verification already requires PostgreSQL 18, and tests use representative dump snippets plus live schema checks.
- **Risk: external schema dump tooling might be unavailable outside the Nix shell** -> Mitigation: project commands run through the Nix flake, which supplies PostgreSQL tooling.
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
