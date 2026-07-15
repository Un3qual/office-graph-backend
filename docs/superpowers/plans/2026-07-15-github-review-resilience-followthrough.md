# GitHub Review Integration Resilience Follow-through Plan

> Execute inline on `codex/github-review-integration`. Use the project Nix shell for all project commands, add failing regression coverage before behavior changes, commit coherent batches, and do not refresh GitHub after the final push.

## Goal

Resolve the fresh PR #25 bot findings at their shared boundaries: preserve retryable storage failures, keep health totals accurate without unbounded reads, make durable terminalization and history scope-safe, harden the migration/spec documentation, and prove the nested-transaction finding is not actionable.

## Task 1: Centralize test record-loader setup

- [x] Add a `configure!/1` helper to `RecordLoaderTestAdapter` that installs responses, registers cleanup, restores the previous application environment, and clears ETS state.
- [x] Replace duplicated private setup helpers in outbound-command and webhook-worker tests.
- [x] Run the two focused test modules in the Nix shell.
- [x] Commit the shared test-infrastructure change.

## Task 2: Preserve storage failures at GitHub integration read boundaries

- [x] Add receipt regressions for installation and webhook-credential lookup outages; expect `:receipt_unavailable` and no receipt effects.
- [x] Add outbound-command regression for installation lookup outage; expect `:integration_storage_unavailable` and no action or job.
- [x] Add reconciler regressions for installation and app-private-key binding lookup outages; expect retryable storage classification and a persisted retryable sync outcome.
- [x] Add health regression for installation lookup outage; expect a safe storage-unavailable result rather than `:forbidden`.
- [x] Route these lookups through `RecordLoader`, preserve non-enumerating missing/cross-scope behavior, and normalize loader errors to the public retryable error for each boundary.
- [x] Update canonical and archived OpenSpec requirements for the clarified failure contract.
- [x] Run focused tests and strict OpenSpec validation.
- [x] Commit the storage-boundary fix.

## Task 3: Keep health totals complete while reads stay bounded

- [ ] Add a regression with more failures than the display limit and assert full retryable/terminal totals alongside a capped `recent_failures` list.
- [ ] Add bounded filtered count aggregates for sync outcomes and outbound actions instead of deriving totals from the display sample.
- [ ] Update query-count expectations to account for the two bounded aggregate queries.
- [ ] Update canonical and archived integration-health specs to distinguish totals from the recent sample.
- [ ] Run the health projection tests and strict OpenSpec validation.
- [ ] Commit the health aggregation fix.

## Task 4: Make terminal delivery state durable and scope-exact

- [ ] Add an outbound-worker regression for final-attempt action-load storage failure: stage terminalization, then persist a terminal action once storage recovers before cancelling the job.
- [ ] Add a terminal-history regression where an organization-scoped job references a workspace-scoped event; require metadata fallback instead of trusting the mismatched event.
- [ ] Implement an explicit terminalization phase for exhausted outbound action-load failures.
- [ ] Key terminal event failure codes by event identity plus exact organization/workspace scope.
- [ ] Update canonical durable-delivery/GitHub integration specs and archived copies.
- [ ] Run focused worker and durable-delivery tests plus strict OpenSpec validation.
- [ ] Commit the durable terminalization fix.

## Task 5: Reconcile documentation, migration safety, and false-positive evidence

- [ ] Make missing review-thread state explicitly non-actionable in runtime and the archived implementation-plan snippet; retain the existing missing-thread regression.
- [ ] Split installation revocation from invalid credential handling in canonical and archived GitHub integration specs.
- [ ] Make the external-source identity index migration non-transactional and concurrent, using the original indexed columns when dropping the old index; retain irreversible rollback semantics.
- [ ] Add migration metadata coverage for disabled DDL transactions.
- [ ] Add a targeted nested-transaction rollback regression proving enqueue failure aborts the enclosing transaction with no partial event or job; do not change the correct `Repo.rollback/1` implementation.
- [ ] Run focused product-mapping, migration, and durable-event tests plus strict OpenSpec validation.
- [ ] Commit the hardening/documentation batch.

## Task 6: Verify, publish, and respond

- [ ] Run all affected tests in one Nix-shell command.
- [ ] Run `mix format --check-formatted`, `openspec validate --all --strict`, `mix verify`, and `git diff --check` in the Nix shell where applicable.
- [ ] Mark this plan complete, move it to `docs/superpowers/plans/archive/`, and commit the closeout.
- [ ] Push `codex/github-review-integration` once.
- [ ] Reply to each fresh inline bot thread with the root-cause fix or evidence-backed non-actionable explanation, and leave one consolidated PR comment for outside-diff findings.
- [ ] Stop without a post-push refresh.
