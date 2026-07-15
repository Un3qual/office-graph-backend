# GitHub Review Integration Consistency Follow-through Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve the fresh PR #25 review findings by preserving storage failures, making stale and concurrent writes converge safely, retaining exhausted inbound failures durably, and scoping system idempotency to the governing workspace.

**Architecture:** Keep the existing GitHub integration boundaries and make their read semantics uniform through `RecordLoader`: missing or cross-scope data remains non-enumerating, while loader failures remain `integration_storage_unavailable`. Order durable side effects behind the winning sync outcome, skip reference refreshes for stale provider results, terminalize pre-operation webhook exhaustion through the receipt operation/event plus a terminal `SyncOutcome`, and make the system-operation lookup, Ash identity, and forward database index use the same workspace-aware key.

**Tech Stack:** Elixir 1.20, Erlang/OTP 29, Ash 3, AshPostgres 2, Ecto/PostgreSQL, Oban, ExUnit, OpenSpec, Nix.

## Global Constraints

- Run all project commands through `nix --extra-experimental-features 'nix-command flakes' develop`.
- Treat canonical `openspec/specs/` and the archived GitHub change specs as the behavior contract.
- Add a failing behavior regression and observe the expected failure before each production fix.
- Do not broaden into deferred identity/governance or unrelated refactors.
- Commit coherent batches, push `codex/github-review-integration` once at the end, reply from the cached pre-push review snapshot, and do not refresh GitHub after pushing.

---

### Task 1: Preserve Integration Storage Failure Classification

**Files:**
- Modify: `lib/office_graph/github_integration/record_loader.ex`
- Modify: `test/support/office_graph/github_record_loader_test_adapter.ex`
- Modify: `lib/office_graph/integrations.ex`
- Modify: `lib/office_graph/github_integration/webhook_worker.ex`
- Modify: `lib/office_graph/github_integration/secret_store.ex`
- Modify: `lib/office_graph/github_integration/outbound_commands.ex`
- Modify: `lib/office_graph/github_integration/health.ex`
- Test: `test/office_graph/github_integration/webhook_worker_test.exs`
- Test: `test/office_graph/github_integration/secret_store_test.exs`
- Test: `test/office_graph/github_integration/outbound_commands_test.exs`
- Test: `test/office_graph/projections/integration_health_test.exs`

**Interfaces:**
- Consumes: `RecordLoader.get/3` and `RecordLoader.read_one/3`.
- Produces: `RecordLoader.read/3` and `RecordLoader.aggregate/4`; storage-aware archive reads; safe `{:error, :integration_storage_unavailable}` results at secret, outbound-command, and health boundaries.

- [ ] Add regressions for archive, credential-metadata, permission, target, and health-dependency read outages.
- [ ] Run the focused tests and confirm they fail because storage errors are currently collapsed or raised.
- [ ] Extend `RecordLoader` and route the affected reads through it without changing missing/cross-scope behavior.
- [ ] Run the focused tests and confirm they pass.
- [ ] Commit the storage-classification batch.

### Task 2: Make Concurrent And Stale Reconciliation Side Effects Converge

**Files:**
- Modify: `lib/office_graph/github_integration/reconciler.ex`
- Test: `test/office_graph/github_integration/reconciliation_test.exs`
- Test: `test/office_graph/github_integration/reconciliation_concurrency_test.exs`

**Interfaces:**
- Consumes: `SoftwareProving.upsert_provider_resource/5` result `%{record: struct(), status: :created | :updated | :stale}` and `persist_outcome!/2`.
- Produces: reference updates only for created/updated resources; installation revocation only when the persisted winning outcome is terminal `installation_revoked`.

- [ ] Add a stale-URL regression and a deterministic success-then-revocation race regression.
- [ ] Run both tests and confirm the stale URL and lifecycle assertions fail on the current ordering.
- [ ] Gate reference writes on non-stale status and move lifecycle application behind the winning persisted outcome.
- [ ] Run reconciliation and concurrency tests and confirm they pass.
- [ ] Commit the reconciliation-ordering batch.

### Task 3: Retain Exhausted Pre-Operation Webhook Failures

**Files:**
- Modify: `lib/office_graph/github_integration/webhook_worker.ex`
- Modify: `lib/office_graph/github_integration/reconciler.ex`
- Test: `test/office_graph/github_integration/webhook_worker_test.exs`

**Interfaces:**
- Consumes: receipt `event_id`, installation/delivery job scope, `Operations.lock_operation/1`, and `DurableDelivery.mark_failed/3`.
- Produces: a staged `pre_operation` terminalization phase, a terminal `provider_delivery` `SyncOutcome`, a failed receipt event, and safe `integration_storage_unavailable` terminal history before job cancellation.

- [ ] Add a final-attempt installation-read outage regression that forces the first terminal outcome write to fail, then recovers storage.
- [ ] Run it and confirm the current worker cancels without staged metadata or a terminal outcome.
- [ ] Add pre-operation terminalization and accept `integration_storage_unavailable` in staged retry decoding.
- [ ] Run webhook worker tests and confirm terminalization persists before cancellation.
- [ ] Commit the durable inbound-terminalization batch.

### Task 4: Scope System Operation Idempotency By Workspace

**Files:**
- Modify: `lib/office_graph/operations.ex`
- Modify: `lib/office_graph/operations/operation_correlation.ex`
- Create: `priv/repo/migrations/20260715143000_scope_system_operation_idempotency.exs`
- Modify: `test/office_graph/system_operations_test.exs`
- Modify: `test/office_graph/system_operation_migration_test.exs`

**Interfaces:**
- Consumes: `SystemOperationRequest.workspace_id`.
- Produces: exact workspace-aware replay lookup and Ash identity; a concurrent forward index with `nulls_distinct: false` so organization-scoped nil work remains unique.

- [ ] Add behavior and migration-shape regressions for identical system keys in two workspaces and nil-scope uniqueness.
- [ ] Run them and confirm the second workspace currently conflicts.
- [ ] Update lookup/identity and add an idempotent forward migration rather than editing the applied historical migration.
- [ ] Run system-operation and migration tests and confirm they pass.
- [ ] Commit the idempotency-scope batch.

### Task 5: Synchronize Contracts And Verify

**Files:**
- Modify: `openspec/specs/github-review-integration/spec.md`
- Modify: `openspec/specs/integration-health/spec.md`
- Modify: `openspec/specs/shared-operation-contracts/spec.md`
- Modify: `openspec/changes/archive/2026-07-14-add-github-review-integration/specs/github-review-integration/spec.md`
- Modify: `openspec/changes/archive/2026-07-14-add-github-review-integration/specs/integration-health/spec.md`
- Modify: `openspec/changes/archive/2026-07-14-add-github-review-integration/specs/shared-operation-contracts/spec.md`
- Modify: `docs/superpowers/plans/README.md`
- Move: this plan to `docs/superpowers/plans/archive/`

**Interfaces:**
- Consumes: implemented behavior and cached PR review thread IDs.
- Produces: canonical/archived contract parity, strict validation, one pushed head, and evidence-backed thread replies.

- [ ] Update canonical and archived scenarios for all clarified contracts.
- [ ] Run the complete affected test set, `mix format --check-formatted`, `openspec validate --all --strict`, `mix verify`, and `git diff --check` in the Nix shell.
- [ ] Mark all plan steps complete, archive the plan, and commit closeout.
- [ ] Push `codex/github-review-integration` once.
- [ ] Reply to and resolve the 10 fresh inline threads, post one consolidated outside-diff reply if needed, and stop without a post-push refresh.
