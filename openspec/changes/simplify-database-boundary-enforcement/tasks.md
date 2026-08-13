## 1. Bounded Source Enforcement

- [x] 1.1 Replace the symbolic scanner with a focused tracked-source primitive scanner
- [x] 1.2 Preserve exact UUIDv7 fingerprints and invalidate changed fragment or loop context
- [x] 1.3 Cover direct Repo, Ecto, Postgrex, DBConnection, fragment, SQL-bearing DSL, migration, and SQL-like file occurrences
- [x] 1.4 Reject nonliteral SQL payloads and nondeclarative migrations without interpreting dataflow or generic execution

## 2. Compiled Dependency Enforcement

- [x] 2.1 Audit test and production project BEAM import/source metadata after compilation
- [x] 2.2 Permit only explicit repository infrastructure owners and source-matched approved calls
- [x] 2.3 Fail closed on missing tracked BEAM metadata without auditing callbacks or abstract control flow

## 3. Migration And Terminal Conformance

- [x] 3.1 Keep the built-in AshPostgres non-mutating migration drift check in canonical verification
- [x] 3.2 Replace synthetic migration interpretation with PostgreSQL 18 terminal object inventory
- [x] 3.3 Compare all relevant project-owned terminal object classes with Ash/resource ownership metadata
- [x] 3.4 Preserve exact exception provenance and focused behavior evidence without adding catalog SQL

## 4. Focused Verification

- [x] 4.1 Replace synthetic semantic scanner tests with direct source, compiled import, fingerprint, and false-positive tests
- [x] 4.2 Add terminal dump parsing and migrated-baseline comparison tests for supported object classes
- [x] 4.3 Run focused tests, strict OpenSpec validation, and the canonical Nix verification pipeline
- [x] 4.4 Perform a final anti-slop review of module size, ownership, and finite policy tables

## 5. Replacement Publication

- [x] 5.1 Commit and push the clean replacement branch
- [x] 5.2 Open a replacement PR against main explaining the threat model and retained guarantees
- [x] 5.3 Close superseded PR 36 with a link to the replacement
