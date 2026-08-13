## 1. Boundary Foundation PR

- [ ] 1.1 Add a focused tracked-source primitive scanner beside the existing gate
- [ ] 1.2 Preserve the two exact UUIDv7 fingerprints and approval provenance
- [ ] 1.3 Reject low-level aliases, imports, delegates, captures, reflection, dynamic SQL, and executable-script database tokens without interpretation
- [ ] 1.4 Add a module-level test and production BEAM import audit with only explicit repository infrastructure owners
- [ ] 1.5 Run focused tests, strict OpenSpec validation, and canonical verification
- [ ] 1.6 Publish `codex/database-boundary-foundation` against `main`

## 2. Migration Conformance PR

- [ ] 2.1 Keep `mix ash_postgres.generate_migrations --check` in canonical verification
- [ ] 2.2 Add PostgreSQL 18 terminal object inventory without repository-authored catalog SQL
- [ ] 2.3 Compare every relevant project-owned object class with Ash/resource ownership metadata
- [ ] 2.4 Require exact terminal-object approval provenance and focused behavior evidence
- [ ] 2.5 Run focused migration tests and canonical verification
- [ ] 2.6 Publish `codex/database-migration-conformance` on the foundation branch

## 3. Obsolete Analyzer Cleanup PR

- [ ] 3.1 Prove replacement source, compiled, drift, and terminal gates together while the old gates remain active
- [ ] 3.2 Switch canonical enforcement to the replacement gates
- [ ] 3.3 Delete the symbolic source analyzer, migration interpreter, and synthetic semantic fixtures
- [ ] 3.4 Run the full test suite, strict OpenSpec validation, and canonical verification
- [ ] 3.5 Publish `codex/remove-symbolic-database-analyzer` on migration conformance
- [ ] 3.6 Close PR 37 with links to the replacement stack
