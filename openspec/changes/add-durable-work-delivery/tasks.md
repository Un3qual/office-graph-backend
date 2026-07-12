## 1. Durable Runtime And Persistence

- [x] 1.1 Add failing runtime and migration tests, then add the pinned Oban dependency, explicit queues/plugins, test mode, supervision, standard Oban tables, and typed `domain_events` persistence with scope, operation, subject, causation, delivery-state, and growth indexes.
- [x] 1.2 Add architecture coverage and public DurableDelivery boundary modules so callers cannot reach Oban, domain-event storage, or another domain's truth tables directly.

## 2. Transactional Events And Workers

- [x] 2.1 Add failing event tests, then implement transaction-safe `record_and_enqueue/2` with typed validation, operation/scope checks, stable event identity, one unique dispatch job, replay, and rollback behavior.
- [x] 2.2 Add failing worker tests, then implement the shared success/retryable/terminal classification contract, idempotent event dispatch, bounded attempts, safe failure state, and deterministic test worker.

## 3. Observability And Failure Visibility

- [x] 3.1 Add failing scoped-read tests, then expose bounded terminal-job summaries that filter by organization/workspace and omit raw arguments, exception details, and other-tenant jobs.
- [x] 3.2 Add failing telemetry tests, then attach job lifecycle telemetry and metrics for worker, queue, state, attempt, and duration without tenant or argument metadata.

## 4. Authorized Projection Invalidation

- [x] 4.1 Add failing subscriber and dispatcher tests, then implement the typed projection-invalidation envelope, fail-closed session/scope subscription, post-commit PubSub delivery, duplicate-dispatch suppression, and authoritative-refetch hints.
- [ ] 4.2 Add failing integration tests, then record and enqueue `manual_intake.accepted` inside first-acceptance persistence while keeping operation replay and transaction rollback free of duplicate events or jobs.

## 5. Verification And Completion

- [ ] 5.1 Run focused migration, persistence, worker, authorization, telemetry, operator-command, architecture, and concurrency tests; then run strict OpenSpec validation, `mix verify`, and `git diff --check`.
- [ ] 5.2 Synchronize durable-delivery delta requirements into durable specs, archive `add-durable-work-delivery`, update the current plan index, confirm no active change remains, and push the verified commits to PR #21.
