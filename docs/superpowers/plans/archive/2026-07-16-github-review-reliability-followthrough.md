# GitHub Review Reliability Follow-Through Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the five current PR #25 bot findings and the newly-relevant duplicate conformance retry finding with durable retry, identity, ordering, and lifecycle behavior.

**Architecture:** Keep error classification at the boundary that owns the operation: webhook pre-operation handling translates structured system-operation persistence failures into the existing integration retry contract, system conformance retries structured persistence failures while retaining terminal handling for deterministic domain errors, and integration signal synchronization translates structured transaction failures into `integration_storage_unavailable`. Use operation identity for conformance event keys, reconciled thread records for actionability, and a single invariant that provider reactivation clears the soft-delete timestamp.

**Tech Stack:** Elixir 1.20, Erlang/OTP 29, Ash, AshPostgres, Ecto/PostgreSQL, Oban, ExUnit, OpenSpec 1.4.1, Nix flakes.

## Global Constraints

- Use the pinned project Nix flake for every project runtime and CLI command.
- Treat `openspec/specs/github-review-integration/spec.md` and `openspec/specs/shared-operation-contracts/spec.md` as the behavior source of truth; this batch repairs conformance and adds no new product capability.
- Preserve fixed retry budgets, safe public error codes, tenant scope, replay identity, provider ordering, and transactional rollback.
- Retry only structured persistence failures; deterministic authorization, replay, validation, and event-contract errors remain terminal.
- Use behavior tests and explicit red/green runs; do not add source-string assertions.
- Push once after all checks pass, reply to cached review threads, and do not fetch review state after the push.

---

### Task 1: Preserve retry semantics for structured persistence failures

**Files:**
- Modify: `test/office_graph/github_integration/webhook_worker_test.exs`
- Modify: `test/office_graph/system_operations_test.exs`
- Modify: `test/office_graph/github_integration/product_mapping_test.exs`
- Modify: `lib/office_graph/github_integration/webhook_worker.ex`
- Modify: `lib/office_graph/durable_delivery/system_conformance_worker.ex`
- Modify: `lib/office_graph/work_graph/system_commands.ex`

**Interfaces:**
- Consumes: `Operations.start_system_operation/1`, `DurableDelivery.record_system_and_enqueue/2`, `WorkGraph.sync_integration_signal/4`, and the workers' existing retry normalization.
- Produces: valid webhook work returns the existing `integration_storage_unavailable` retry result when operation persistence fails; conformance returns an Oban retry for structured persistence failures; signal transaction failures reach reconciliation as `integration_storage_unavailable` without partial product writes.

- [x] **Step 1: Write failing operation-store regressions**

Add a temporary database check constraint in the webhook worker test that rejects only `integration.reconcile` operation rows. Assert a valid archived delivery returns `{:error, "integration_storage_unavailable"}` and stages no terminal metadata. Add a conformance worker regression with a constraint that rejects its operation row and assert the worker returns an Oban retry instead of cancellation.

- [x] **Step 2: Run the operation-store tests and verify RED**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop -c zsh -lc 'mix test test/office_graph/github_integration/webhook_worker_test.exs test/office_graph/system_operations_test.exs'
```

Expected: the webhook test receives `invalid_worker_result`, and conformance cancels as `invalid_system_conformance_job`.

- [x] **Step 3: Classify structured worker failures narrowly**

In `WebhookWorker.perform/1`, add a clause before the terminal catch-all that routes structured errors returned after the validated operation request through `normalize_pre_operation_storage_failure/1`. In `SystemConformanceWorker`, return `{:error, "system_conformance_storage_unavailable"}` only when the error is a struct; preserve the explicit forbidden and deterministic terminal branches.

- [x] **Step 4: Write and run the failing signal-storage regression**

Add a product-mapping test that temporarily rejects the external-reference graph item write, reconciles an actionable comment, and asserts the safe retry classification, no partial signal/provider-neutral state, and successful replay after the constraint is removed. Run the product-mapping file and verify the raw Ash error currently escapes.

- [x] **Step 5: Normalize signal transaction failures and verify GREEN**

In `WorkGraph.SystemCommands.sync_integration_signal/4`, preserve atom and tuple domain errors but translate structured transaction errors to `:integration_storage_unavailable`. Re-run the three focused test files and confirm all pass.

- [x] **Step 6: Commit**

```bash
git add lib/office_graph/github_integration/webhook_worker.ex lib/office_graph/durable_delivery/system_conformance_worker.ex lib/office_graph/work_graph/system_commands.ex test/office_graph/github_integration/webhook_worker_test.exs test/office_graph/system_operations_test.exs test/office_graph/github_integration/product_mapping_test.exs
git commit -m "fix: preserve integration storage retries"
```

### Task 2: Scope conformance event identity to the exact operation

**Files:**
- Modify: `test/office_graph/system_operations_test.exs`
- Modify: `lib/office_graph/durable_delivery/system_conformance_worker.ex`

**Interfaces:**
- Consumes: exact-workspace system operation idempotency and global `DomainEvent.event_key` uniqueness.
- Produces: one stable event key per system operation, replayed within the same workspace and independent across governing workspaces.

- [x] **Step 1: Write the failing cross-workspace regression**

Create two workspaces in one organization, use the same system principal and conformance idempotency key, run one job per workspace, and assert both complete with distinct operations and domain events. Re-run the test and verify the second job currently collides with the first global event key.

- [x] **Step 2: Use operation identity in the event key**

Replace the organization/principal/key concatenation with `"system-conformance:#{operation.id}"`. The operation id already includes exact workspace-scoped idempotency and remains stable on replay.

- [x] **Step 3: Run the system-operation tests and verify GREEN**

Run the system-operation file and confirm organization-scoped replay and cross-workspace independence both pass.

- [x] **Step 4: Commit**

```bash
git add lib/office_graph/durable_delivery/system_conformance_worker.ex test/office_graph/system_operations_test.exs
git commit -m "fix: scope conformance events by operation"
```

### Task 3: Compute comment actionability from reconciled thread truth

**Files:**
- Modify: `test/office_graph/github_integration/product_mapping_test.exs`
- Modify: `lib/office_graph/github_integration/reconciler.ex`

**Interfaces:**
- Consumes: `SoftwareProving.upsert_provider_resource/5` result records for review threads and comments.
- Produces: comment foreign keys and signal actionability use the same reconciled thread record, including its authoritative state when the incoming thread snapshot is stale.

- [x] **Step 1: Write the failing stale-thread regression**

Seed an open comment signal, advance its stored thread independently to a newer resolved provider sequence, then reconcile an intermediate snapshot whose pull request and comment are current enough to process but whose thread is stale/open. Assert the stored thread remains resolved and the signal remains closed.

- [x] **Step 2: Run the product-mapping test and verify RED**

Expected: current code uses the raw snapshot's open thread state and reopens the signal.

- [x] **Step 3: Carry reconciled thread records**

Change `reconcile_threads!/4` to return a node-id map of persisted `ReviewThread` records. Derive comment `review_thread_id` and the actionability state map from those records, not from the adapter snapshots. Keep stale comment/check suppression unchanged.

- [x] **Step 4: Run the product-mapping tests and verify GREEN**

Confirm the new stale-thread regression plus existing open/resolved/reopen signal lifecycle tests pass.

- [x] **Step 5: Commit**

```bash
git add lib/office_graph/github_integration/reconciler.ex test/office_graph/github_integration/product_mapping_test.exs
git commit -m "fix: use reconciled thread actionability"
```

### Task 4: Clear tombstones when provider resources reactivate

**Files:**
- Modify: `test/office_graph/github_integration/reconciliation_test.exs`
- Modify: `lib/office_graph/software_proving.ex`

**Interfaces:**
- Consumes: `:read_with_deleted` extension lookup and newer provider reconciliation.
- Produces: any newer provider update that sets `lifecycle_state` to active also sets `deleted_at` to nil, restoring normal product reads.

- [x] **Step 1: Write the failing reactivation regression**

Reconcile a provider resource, soft-delete it with a tombstone timestamp, reconcile a newer snapshot, and assert the same record id is active, has `deleted_at == nil`, and is visible through the normal read action.

- [x] **Step 2: Run the reconciliation test and verify RED**

Expected: lifecycle becomes active but the normal read still returns not found because `deleted_at` remains set.

- [x] **Step 3: Enforce the reactivation invariant**

In the provider update attribute merge, set `deleted_at: nil` alongside `lifecycle_state: "active"`, after caller attributes so a reconciliation cannot reactivate a row while retaining a tombstone.

- [x] **Step 4: Run the reconciliation and software-proving tests and verify GREEN**

Run both affected files and confirm soft-delete filtering and provider reactivation behavior pass.

- [x] **Step 5: Commit**

```bash
git add lib/office_graph/software_proving.ex test/office_graph/github_integration/reconciliation_test.exs
git commit -m "fix: clear provider resource tombstones"
```

### Task 5: Verify, archive, push, and reply from the cached snapshot

**Files:**
- Modify: `docs/superpowers/plans/README.md`
- Move: `docs/superpowers/plans/2026-07-16-github-review-reliability-followthrough.md` to `docs/superpowers/plans/archive/2026-07-16-github-review-reliability-followthrough.md`

- [x] **Step 1: Run focused and affected verification**

Run the three focused test files after each change, then the affected GitHub integration, system-operation, durable-delivery, and software-proving batch.

- [x] **Step 2: Run the repository gate**

```bash
nix --extra-experimental-features 'nix-command flakes' develop -c zsh -lc './bin/verify'
git diff --check
```

Expected: all backend, frontend, static, architecture, security, strict OpenSpec, and production build stages pass, and the diff is whitespace-clean.

- [x] **Step 3: Archive and commit the plan**

Move this plan to `docs/superpowers/plans/archive/`, restore the README so the internal-agent-runtime plan is the only active plan, and commit the documentation closeout.

- [x] **Step 4: Push and reply without refreshing**

Push `codex/github-review-integration` once. Reply to and resolve the five cached current Codex threads plus the older related CodeRabbit conformance thread with exact fixes and verification evidence. Do not perform any GitHub read after the push.
