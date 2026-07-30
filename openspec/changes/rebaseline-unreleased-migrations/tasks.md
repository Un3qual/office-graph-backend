## 1. Lock The Baseline Contract

- [x] 1.1 Add architecture tests that require every PostgreSQL-backed Ash resource to participate in migration generation and require tracked current resource snapshots
- [x] 1.2 Add boundary tests that reject migration inserts, MD5-derived identifiers, execute calls, SQL checks, SQL predicates, and stale historical migration debt
- [x] 1.3 Add fresh PostgreSQL 18 migration and generator-drift tests that run without seeds or preexisting database state
- [x] 1.4 Add setup replay tests for exact capabilities, relationship definitions, endpoint rules, and the canonical run-review agent definition
- [x] 1.5 Add or retain race tests for every state-filtered identity that will move away from a partial index

## 2. Make Ash Resources Migration-Authoritative

- [x] 2.1 Remove blanket `migrate? false` declarations from tracked PostgreSQL resources and configure stable generated index names
- [x] 2.2 Replace nullable-key filtered identities with ordinary Ash identities or `nils_distinct?` identities that preserve current behavior
- [x] 2.3 Replace active, accepted, pending, and unrevoked filtered identities with private typed identity-slot attributes maintained by owning create and transition actions
- [x] 2.4 Update resource conformance inventories and tests for the terminal identity model, migration participation, and database-generated UUIDv7 metadata
- [x] 2.5 Run focused identity, idempotency, lifecycle, restore, session, intake replay, and agent gate concurrency tests

## 3. Move Canonical Data Into Ash Setup

- [x] 3.1 Add an Authorization-owned capability manifest and idempotent setup action using Ash identities and upserts
- [x] 3.2 Add WorkGraph-owned relationship-definition and endpoint-rule manifests plus an idempotent transactional setup action
- [x] 3.3 Add an AgentRuntime-owned canonical run-review definition manifest and idempotent setup action
- [x] 3.4 Add `OfficeGraph.Release.setup/0` to compose owning setup actions without direct Ecto or explicit `Repo.transaction`
- [x] 3.5 Update local setup, release documentation, and development seeds so migrations run schema only, canonical setup runs once, and demo data remains optional

## 4. Generate The Current Baseline

- [x] 4.1 Inventory every historical SQL check, predicate, execute call, and inserted application record and map it to current typed behavior or obsolete history
- [x] 4.2 Remove the 49-file unreleased migration chain and any obsolete migration-only tests as one reviewed baseline replacement
- [x] 4.3 Generate current AshPostgres resource snapshots and the logical initial migration from an empty snapshot state
- [x] 4.4 Review and normalize generated output so it uses declarative Ecto migration constructs and contains no raw SQL except the previously approved native UUIDv7 fragment
- [x] 4.5 Update the approved UUIDv7 exception fingerprint and remove all 173 `rebaseline-unreleased-migrations` debt occurrences

## 5. Canonical Verification

- [x] 5.1 Add non-mutating AshPostgres migration drift checking to the canonical gate
- [x] 5.2 Add isolated empty-database baseline and double-setup verification without duplicating the complete ExUnit suite
- [x] 5.3 Verify complete rollback and re-application where the generated logical baseline is reversible
- [x] 5.4 Run formatter, compilation with warnings as errors, strict Credo, architecture and smell gates, Dialyzer, dependency audit, strict OpenSpec validation, frontend verification, and the complete ExUnit suite
- [x] 5.5 Run canonical `bin/verify`, confirm a clean worktree after verification, and review the final diff for hidden SQL, weakened constraints, manual UUID generation, seed coupling, and unrelated behavior changes
