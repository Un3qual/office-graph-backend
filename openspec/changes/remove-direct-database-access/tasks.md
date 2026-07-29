## 1. Lock The Removal Boundary

- [x] 1.1 Pin the exact 721-entry starting inventory to the canonical fingerprinted `remove-direct-database-access` subset at parent commit `914b6564`
- [ ] 1.2 Add owner/class progress reporting and architecture tests that require zero non-migration debt at completion without weakening migration or approved-exception coverage
- [ ] 1.3 Add a production read-modify-write audit that records every touched mutating function, persisted reads, selected Ash safeguard, and concurrency test
- [ ] 1.4 Make Ecto, AshPostgres, and repository query logging quiet in normal tests with a documented opt-in diagnostic switch and focused regression test

## 2. Replace Foundation And Identity Escapes

- [ ] 2.1 Replace tenancy and content explicit transactions with action-owned Ash persistence and preserve bootstrap/document atomicity
- [ ] 2.2 Replace authorization partial-index fragments and explicit transactions with Ash identities, actions, and upserts
- [ ] 2.3 Replace identity bootstrap and session transactions, OIDC SQL, normalized-email fragments, and advisory locks with Ash actions, atomics, identities, and query locks
- [ ] 2.4 Add concurrent owner/session/OIDC/external-identity tests proving uniqueness, consumption, stale conflict, and failure atomicity

## 3. Replace Core Workflow Escapes

- [ ] 3.1 Replace integration intake transactions, insert-all path, and partial identity fragment with Ash action-managed replay behavior
- [ ] 3.2 Replace proposed-change transactions with owning actions and preserve all-or-nothing application and typed conflict ordering
- [ ] 3.3 Replace work-packet and run transaction wrappers, observation advisory lock, and child-count SQL with Ash actions, identities, atomics, and aggregates
- [ ] 3.4 Replace evidence acceptance and waiver transactions with action-owned Ash changes and atomic parent verification updates
- [ ] 3.5 Add concurrent intake, proposal, packet, run, observation, evidence, and waiver tests for replay, stale state, and failure atomicity

## 4. Replace Work Graph Escapes

- [ ] 4.1 Replace evidence-reference SQL validation with Ash relationships, scoped reads, and typed validation errors inside the owning action
- [ ] 4.2 Replace generic command transaction helpers with action-owned transactions and remove the reusable direct-Ecto escape hatch
- [ ] 4.3 Replace relationship-cycle advisory lock and recursive SQL with Ash query locking and typed graph traversal while preserving endpoint authorization
- [ ] 4.4 Add concurrent relationship creation and evidence validation tests proving cycle, scope, operation, and loser-conflict behavior

## 5. Replace Agent Runtime Escapes

- [ ] 5.1 Replace binding and invocation advisory locks plus transaction wrappers with identities, upserts, atomic actions, and typed replay behavior
- [ ] 5.2 Replace approval, cancellation, context expansion, and gate-expiry transactions with optimistic/atomic Ash actions
- [ ] 5.3 Replace execution-worker claim, completion, failure, and finalization SQL/transactions with lease-aware atomic actions and query locks
- [ ] 5.4 Add separate-owner concurrency tests for invocation, binding, approval/context resolution, cancellation, leases, retry, and terminal transitions

## 6. Replace GitHub Integration Escapes

- [ ] 6.1 Replace installation partial identities, advisory lock, and explicit binding transaction with Ash identities, upserts, and action-owned writes
- [ ] 6.2 Replace outbound enqueue, webhook receipt, reconciliation, failure, and worker transaction wrappers with Ash actions and bulk/upsert behavior
- [ ] 6.3 Add separate-owner concurrency tests for installation binding, webhook replay, reconciliation ordering, outbound idempotency, revocation, and failure atomicity

## 7. Replace Conversation And Projection SQL

- [ ] 7.1 Replace conversation start/append transactions and advisory lock with Ash identities, relationship reads, query locking, and action-owned writes
- [ ] 7.2 Replace proposal/context/agent-state conversation SQL with scoped Ash relationships and typed projection results
- [ ] 7.3 Replace operator-workflow relationship, packet-check, and run SQL with batched Ash relationships, aggregates, and keyset-backed reads
- [ ] 7.4 Replace run-state activity, command-option, and summary SQL with typed Ash reads while preserving cursor and bounded-query contracts
- [ ] 7.5 Run projection query-count, pagination, redaction, soft-deletion, authorization, and cross-scope regression suites

## 8. Remove Test And Test-Support Escapes

- [ ] 8.1 Replace foundation, authorization, authentication, identity, integrations, and durable-delivery test SQL/direct Ecto with public behavior and typed fixtures
- [ ] 8.2 Replace agent-runtime test SQL/direct Ecto with public actions and test adapter seams
- [ ] 8.3 Replace GitHub integration test SQL/direct Ecto with public actions, provider adapters, and typed ordering controls
- [ ] 8.4 Replace work-graph, work-packet, run, projection, and web API test SQL/direct Ecto with public actions and behavior assertions
- [ ] 8.5 Replace concurrency-support triggers, functions, advisory locks, row mutation, and catalog helpers with typed action/adapter barriers and independent sandbox owners
- [ ] 8.6 Remove obsolete migration-specific tests that are superseded by the unreleased-migration rebaseline, without editing migration history in this change

## 9. Verify And Finish

- [ ] 9.1 Remove all matching debt rows and prove the inventory contains zero `remove-direct-database-access` entries, 173 migration debt entries, and only the existing approved UUIDv7 exception
- [ ] 9.2 Run focused authorization, lifecycle, idempotency, replay, optimistic-lock, concurrency, projection query-count, worker, and failure-atomicity suites
- [ ] 9.3 Run formatter, compile with warnings as errors, strict Credo/database-boundary checks, type analysis, and strict OpenSpec validation
- [ ] 9.4 Run the complete canonical `bin/verify` gate and confirm quiet SQL logging, 104 canonical specs plus the active change, frontend verification, and the full backend suite
- [ ] 9.5 Review the final diff for hidden Repo wrappers, raw fragments, generic repository abstractions, weakened tests, source-string coupling, accidental API changes, and unapproved exceptions
