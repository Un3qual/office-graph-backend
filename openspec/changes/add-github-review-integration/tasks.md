## 1. System Operations Foundation

- [ ] 1.1 Add failing operation/event/migration tests for authenticated organization-scoped system work, optional governing workspace/subject version, and unchanged human-session invariants.
- [ ] 1.2 Implement the generic system-operation request, constraints, authorization, idempotency scope, DurableDelivery support, organization invalidations, and a non-GitHub conformance worker.

## 2. Provider-Neutral Software Resources

- [ ] 2.1 Add failing resource/migration tests for repositories, refs, commits, pull requests, review threads/comments, check runs, provider versions, scope, lifecycle, and extension separation.
- [ ] 2.2 Add provider-neutral SoftwareProving resources/domain/migrations, GitHub extension resources, external references, indexes, and backend/API ownership ledger entries.

## 3. Installation, Principals, And Secrets

- [ ] 3.1 Add failing tests for authorized installation binding, backend service/webhook principals, permission snapshots, credential metadata, cross-tenant rejection, and secret non-disclosure.
- [ ] 3.2 Implement installation binding GraphQL/JSON commands, credential references, `SecretStore` behavior, deterministic test adapter, and environment-backed development adapter.

## 4. Verified Webhook Receipt

- [ ] 4.1 Add failing controller/adapter tests for raw-body signature verification, active installation lookup, supported events, duplicate delivery, invalid/unknown rejection before archive, and prompt response.
- [ ] 4.2 Implement the GitHub adapter boundary, webhook route/controller, verified archive receipt, system operation creation, unique Oban enqueue, and safe response/error mapping.

## 5. Reconciliation And Product Mapping

- [ ] 5.1 Add deterministic provider fixtures and failing tests for pull request, review/comment, check, installation, and repository-access reconciliation, batching, rate limits, stale versions, replay, and out-of-order delivery.
- [ ] 5.2 Implement reconciliation workers and provider-neutral upserts with GitHub extensions, sync outcomes, external references, typed relationships, signals, operation/audit/revision provenance, and projection invalidations.

## 6. Outbound Actions And Health

- [ ] 6.1 Add failing tests for authorized/idempotent review replies and status/check updates, unsupported repository writes, permission/credential failures, retry/terminal classification, and provider response provenance.
- [ ] 6.2 Implement narrow outbound commands/workers and keep GitHub clients unreachable from resolvers, agents, and unrelated domains.
- [ ] 6.3 Add failing health/query-count tests, then implement bounded installation, sync, retry, credential, and terminal-state GraphQL/JSON projections.

## 7. Verification And Archive

- [ ] 7.1 Run focused migration, operation, durable delivery, adapter, webhook, reconciliation, outbound, health, authorization, concurrency, API, and architecture tests.
- [ ] 7.2 Run strict OpenSpec validation, deterministic provider contract tests, the canonical Nix-backed `mix verify` gate, and `git diff --check`.
- [ ] 7.3 Synchronize delta specs, archive `add-github-review-integration`, and publish the generic system-operation contract for the agent stack.
