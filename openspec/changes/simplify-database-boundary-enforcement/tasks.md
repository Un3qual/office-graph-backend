## 1. Boundary Foundation PR

- [x] 1.1 Add a focused tracked-source primitive scanner beside the existing gate
- [x] 1.2 Preserve the two exact UUIDv7 fingerprints and approval provenance
- [x] 1.3 Reject low-level delegates, captures, reflection, dynamic SQL, and executable-script database tokens without interpretation
- [x] 1.4 Add a module-level test and production BEAM import audit with only explicit repository infrastructure owners
- [x] 1.5 Run focused tests, strict OpenSpec validation, and canonical verification
- [x] 1.6 Publish `codex/database-boundary-foundation` against `main`

## 2. Migration Conformance PR

- [x] 2.1 Keep `mix ash_postgres.generate_migrations --check` in canonical verification
- [x] 2.2 Add PostgreSQL 18 terminal object inventory without repository-authored catalog SQL
- [x] 2.3 Compare every relevant project-owned object class with Ash/resource ownership metadata
- [x] 2.4 Require exact terminal-object approval provenance and focused behavior evidence
- [x] 2.5 Run focused migration tests and canonical verification
- [x] 2.6 Publish `codex/database-migration-conformance` on the foundation branch

## 3. Obsolete Analyzer Cleanup PR

- [x] 3.1 Prove replacement source, compiled, drift, and terminal gates together while the old gates remain active
- [x] 3.2 Switch canonical enforcement to the replacement gates
- [x] 3.3 Delete the symbolic source analyzer, migration interpreter, and synthetic semantic fixtures
- [x] 3.4 Run the full test suite, strict OpenSpec validation, and canonical verification
- [ ] 3.5 Publish `codex/remove-symbolic-database-analyzer` on migration conformance
- [ ] 3.6 Close PR 37 with links to the replacement stack
