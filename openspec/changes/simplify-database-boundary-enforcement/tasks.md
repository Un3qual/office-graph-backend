## 1. OpenSpec And Design Audit

- [x] 1.1 Validate the active OpenSpec change strictly.
- [x] 1.2 Self-review the design against the approved false-negative risks and update artifacts if gaps are found.

## 2. Replacement Boundary Layers

- [x] 2.1 Add focused tests for forbidden source primitives, unresolved escape paths, SQL-like tracked files, and exact approval matching.
- [x] 2.2 Implement the repository-wide forbidden-primitive source scan without symbolic helper, callback, alias-flow, SQL-body, or control-flow evaluation.
- [x] 2.3 Add focused tests for BEAM dependency/import auditing of compiled low-level database primitives.
- [x] 2.4 Implement the compiled dependency/import audit and wire diagnostics through the database-boundary gate.
- [x] 2.5 Preserve the existing UUIDv7 approved exception fingerprints and provenance.

## 3. Terminal Database Inventory

- [x] 3.1 Add focused tests for terminal database-object inventory parsing and comparison across tables, columns, keys, constraints, indexes, sequences, views, materialized views, routines, triggers, policies, grants, and extensions.
- [x] 3.2 Implement database-owned terminal inventory through PostgreSQL schema dump tooling without repository-authored catalog SQL.
- [x] 3.3 Compare terminal project-owned database objects with Ash/resource ownership metadata and existing foreign-key relationship expectations.
- [x] 3.4 Wire terminal inventory into migration-baseline verification.

## 4. Remove Obsolete Scanner

- [x] 4.1 Run the replacement focused tests while the old scanner remains present.
- [x] 4.2 Delete the symbolic scanner/interpreter and synthetic semantic tests after replacement coverage passes.
- [x] 4.3 Update Credo issue formatting and project-quality tests for the replacement diagnostics.

## 5. Verification And Publication

- [x] 5.1 Run focused project-quality, migration-conformance, and architecture tests in the Nix flake.
- [ ] 5.2 Run canonical `./bin/verify` in the Nix flake. Current run reaches dependency audit and fails on existing `ash`/`postgrex` advisories inherited from the base branch.
- [x] 5.3 Perform a final anti-slop diff review.
- [x] 5.4 Commit, push `codex/simplify-database-boundary-enforcement`, and open a stacked PR targeting `codex/remediate-quality-review`.

## 6. Review Follow-Up

- [x] 6.1 Add regressions for dynamic dispatch, Ecto query fragments and locks, qualified migration SQL options, and short-circuit migration branches.
- [x] 6.2 Audit dynamic database operations in both tracked source and BEAM abstract code without general dataflow analysis.
- [x] 6.3 Preserve and compare terminal column, constraint, and index definitions against Ash/AshPostgres metadata.
- [x] 6.4 Run focused and canonical verification and review the final diff before the follow-up push.

## 7. Review Bot Follow-Up

- [x] 7.1 Scan every tracked Elixir/SQL-like source and resolve ordinary alias prefixes without dataflow analysis.
- [x] 7.2 Audit current tracked-source BEAMs from both test and production output, and keep metadata failures source-addressable.
- [x] 7.3 Preserve schema-qualified resource identities and fail closed on unresolved or composite foreign-key ownership.
- [x] 7.4 Pin PostgreSQL 18 client tooling in the Nix shell and preserve the container fallback when local `pg_dump` is unavailable.
- [x] 7.5 Run final focused and canonical verification and perform the final diff review before publication.
