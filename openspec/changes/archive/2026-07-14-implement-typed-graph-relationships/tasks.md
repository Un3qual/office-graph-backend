## 1. Registry Persistence And Migration

- [x] 1.1 Add failing migration/resource tests for relationship definitions, endpoint rules, migration-installed MVP vocabulary, and absent generic registry mutations.
- [x] 1.2 Add registry and endpoint-rule migrations plus Ash resources/domain registration, indexes, identities, and backend ownership inventory entries.
- [x] 1.3 Add failing legacy-data migration tests, then backfill all five current values to canonical `generated_from`, `review_finding_for`, `requires_check`, and `evidenced_by` rows with direction validation and bounded unknown-value failure.

## 2. Definition-Backed Relationship Resource

- [x] 2.1 Add failing resource tests for definition foreign keys, explicit scope/lifecycle/provenance, uniqueness, and removal of free-form create input.
- [x] 2.2 Extend `GraphRelationship`, migrations, and relationships to canonical definitions, operation/actor, scope, validity, run/integration provenance, and supersession/tombstone references.

## 3. WorkGraph Relationship Commands

- [x] 3.1 Add failing command tests for create, supersede, archive, restore, replay, endpoint compatibility, cross-workspace authorization, and adapter/agent direct-write rejection.
- [x] 3.2 Implement focused WorkGraph relationship command modules and route proposal application plus verification evidence linking through canonical definitions.
- [x] 3.3 Add failing concurrency tests and implement organization/definition-scoped serialization plus bounded forbidden-cycle traversal.

## 4. Reads, APIs, And Projections

- [x] 4.1 Update projection and traversal tests for canonical definition identity, lifecycle, redacted endpoints, and constant/batched query shape.
- [x] 4.2 Update GraphQL/JSON relationship types, generated schema/artifacts, projection assembly, and API migration ledger without adding registry administration.

## 5. Verification And Archive

- [x] 5.1 Run focused migrations, WorkGraph, authorization, concurrency, projection, GraphQL/JSON, and architecture tests; fix all failures.
- [x] 5.2 Run strict OpenSpec validation, the canonical Nix-backed `mix verify` gate, and `git diff --check`.
- [x] 5.3 Synchronize delta specs, archive `implement-typed-graph-relationships`, and confirm GitHub and agent branches can target the archived canonical contract.
