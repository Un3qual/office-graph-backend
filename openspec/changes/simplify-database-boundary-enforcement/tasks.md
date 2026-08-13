## 1. Bounded Source Enforcement

- [ ] 1.1 Replace the symbolic scanner with a focused tracked-source primitive scanner
- [ ] 1.2 Preserve exact UUIDv7 fingerprints and invalidate changed fragment or loop context
- [ ] 1.3 Cover direct Repo, Ecto, Postgrex, DBConnection, fragment, SQL-bearing DSL, migration, and SQL-like file occurrences
- [ ] 1.4 Reject nonliteral SQL payloads and nondeclarative migrations without interpreting dataflow or generic execution

## 2. Compiled Dependency Enforcement

- [ ] 2.1 Audit test and production project BEAM import/source metadata after compilation
- [ ] 2.2 Permit only explicit repository infrastructure owners and source-matched approved calls
- [ ] 2.3 Fail closed on missing tracked BEAM metadata without auditing callbacks or abstract control flow

## 3. Migration And Terminal Conformance

- [ ] 3.1 Keep the built-in AshPostgres non-mutating migration drift check in canonical verification
- [ ] 3.2 Replace synthetic migration interpretation with PostgreSQL 18 terminal object inventory
- [ ] 3.3 Compare all relevant project-owned terminal object classes with Ash/resource ownership metadata
- [ ] 3.4 Preserve exact exception provenance and focused behavior evidence without adding catalog SQL

## 4. Focused Verification

- [ ] 4.1 Replace synthetic semantic scanner tests with direct source, compiled import, fingerprint, and false-positive tests
- [ ] 4.2 Add terminal dump parsing and migrated-baseline comparison tests for supported object classes
- [ ] 4.3 Run focused tests, strict OpenSpec validation, and the canonical Nix verification pipeline
- [ ] 4.4 Perform a final anti-slop review of module size, ownership, and finite policy tables

## 5. Replacement Publication

- [ ] 5.1 Commit and push the clean replacement branch
- [ ] 5.2 Open a replacement PR against main explaining the threat model and retained guarantees
- [ ] 5.3 Close superseded PR 36 with a link to the replacement
