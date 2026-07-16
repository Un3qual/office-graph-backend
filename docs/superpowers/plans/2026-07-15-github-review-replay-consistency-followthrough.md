# GitHub Review Replay Consistency Follow-through Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve every still-valid finding in the cached PR #25 review snapshot while preserving idempotent command replay, provider ordering, classified storage failures, durable terminal history, and maintainable test infrastructure.

**Architecture:** Treat an existing outbound action as the durable command result after validating the caller, operation action, and input digest, so later provider-state changes cannot invalidate a compatible replay. Keep all GitHub integration reads behind `RecordLoader`, propagate sync-outcome outages as retryable, and carry per-resource reconciliation status through external-reference and signal mapping. Use a non-locking operation read for worker recovery paths, centralize safe terminal-failure metadata staging in DurableDelivery, and consolidate repeated PostgreSQL catalog probes in test support.

**Tech Stack:** Elixir 1.20, Erlang/OTP 29, Ash 3, AshPostgres 2, Ecto/PostgreSQL, Oban, ExUnit, OpenSpec, Nix.

## Global Constraints

- Run project runtime and CLI commands through `nix --extra-experimental-features 'nix-command flakes' develop`.
- Treat `openspec/specs/github-review-integration/spec.md`, `openspec/specs/idempotency-and-replay/spec.md`, and `openspec/specs/durable-work-delivery/spec.md` as the existing behavior contract; no new requirement is needed for these fixes.
- Observe every behavioral regression fail for the expected reason before changing production code.
- Preserve live authorization and exact command-input digest validation before returning an existing outbound action.
- Preserve non-enumerating missing/cross-scope behavior while mapping operational read failures to `:integration_storage_unavailable`.
- Do not change the fixed ten-execution retry budget: Oban Basic increments `attempt` on execution and increments `max_attempts` on snooze, while these workers intentionally clamp `max_attempts` back to ten.
- Commit coherent batches, push `codex/github-review-integration` once, reply from `/tmp/office_graph_pr25_review_snapshot_20260715_6.json`, and do not refresh GitHub after pushing.

---

### Task 1: Make Shared Test Infrastructure Honest

**Files:**
- Create: `test/support/office_graph/postgres_catalog.ex`
- Modify: `test/office_graph/system_operation_migration_test.exs`
- Modify: `test/office_graph/software_proving/migration_test.exs`
- Modify: `test/office_graph/github_integration/installation_migration_test.exs`
- Modify: `test/office_graph/work_graph/relationship_migration_test.exs`
- Modify: `test/office_graph/durable_delivery/runtime_test.exs`
- Modify: `test/office_graph/github_integration/reconciliation_test.exs`
- Modify: `test/office_graph/github_integration/webhook_receipt_test.exs`

**Interfaces:**
- Produces: `OfficeGraph.TestSupport.PostgresCatalog` functions `table_exists?/1`, `column_exists?/2`, `column_nullable?/2`, `constraint_exists?/1`, `index_exists?/1`, `index_columns/1`, `index_definition/1`, and `columns/1`.
- Preserves: migration assertions may match the complete index map `%{columns: list, unique?: boolean, predicate: binary | nil, nulls_not_distinct?: boolean}`.

- [x] **Step 1: Add the shared PostgreSQL catalog support module**

  Implement catalog queries through `OfficeGraph.Repo` using `current_schema()`. `index_definition/1` must select ordered key expressions, uniqueness, predicate, and `indnullsnotdistinct` in one query and return `nil` when absent.

- [x] **Step 2: Replace local catalog helpers with imported shared functions**

  Add `import OfficeGraph.TestSupport.PostgresCatalog` in the five catalog-oriented test modules, replace `domain_event_columns/0` with `columns("domain_events")`, and delete only the now-duplicated private query helpers.

- [x] **Step 3: Avoid repeated mock cleanup registration**

  Call `RecordLoaderTestAdapter.configure!(%{})` once before each resource loop in reconciliation and webhook-receipt tests, then use `RecordLoaderTestAdapter.put(%{resource => {:error, :database_unavailable}})` inside the loop.

- [x] **Step 4: Verify the test-infrastructure batch**

  Run:

  ```bash
  mix test test/office_graph/system_operation_migration_test.exs \
    test/office_graph/software_proving/migration_test.exs \
    test/office_graph/github_integration/installation_migration_test.exs \
    test/office_graph/work_graph/relationship_migration_test.exs \
    test/office_graph/durable_delivery/runtime_test.exs \
    test/office_graph/github_integration/reconciliation_test.exs \
    test/office_graph/github_integration/webhook_receipt_test.exs
  ```

  Expected: every selected test passes with no duplicated cleanup registration.

- [x] **Step 5: Commit the test-support cleanup**

  Commit as `test: consolidate postgres catalog probes`.

### Task 2: Replay Existing Outbound Actions Before Mutable State Checks

**Files:**
- Modify: `test/office_graph/github_integration/outbound_commands_test.exs`
- Modify: `lib/office_graph/github_integration/outbound_commands.ex`

**Interfaces:**
- Consumes: validated operation context/action, exact `Operations.validate_command_replay/2`, current authorization, normalized command attributes, and `RecordLoader.read_one/3`.
- Produces: the existing scoped `OutboundAction` for a compatible replay even after the target version/state changes, and `:integration_storage_unavailable` when the action-result read fails.

- [x] **Step 1: Write replay and action-read outage regressions**

  Extend the outbound command test so it creates a review-reply action, changes the target to a newer non-actionable provider state, replays the exact operation/input, and asserts the same action ID plus one job. Add a separate case configuring `OutboundAction => {:error, :database_unavailable}` before first action creation and assert the safe storage-unavailable result with zero actions/jobs.

- [x] **Step 2: Run the outbound regressions and verify RED**

  Run the two new tests. Confirm the replay currently fails on mutable target state and the action-read mock is bypassed.

- [x] **Step 3: Split immutable replay validation from first-execution validation**

  After operation context/action, input digest, live authorization, and input normalization, call a shared replay helper. It must read the action by operation through `RecordLoader`, validate action kind/principal/organization/workspace against the current command, return `{:ok, action}` when present, and execute installation/permission/target/version/provenance validation only when absent. Keep the transactional operation lock and second action lookup for the creation race.

- [x] **Step 4: Verify outbound commands and commit**

  Run `mix test test/office_graph/github_integration/outbound_commands_test.exs`, then commit as `fix: preserve outbound command replay`.

### Task 3: Preserve Nested Provider Ordering And Sync-Outcome Availability

**Files:**
- Modify: `test/office_graph/github_integration/reconciliation_test.exs`
- Modify: `test/office_graph/github_integration/webhook_worker_test.exs`
- Modify: `lib/office_graph/github_integration/reconciler.ex`

**Interfaces:**
- Consumes: `SoftwareProving.upsert_provider_resource/5` status and `RecordLoader.read_one/3`.
- Produces: no external-reference or product-signal refresh for `:stale` comment/check results; retryable `integration_storage_unavailable` for failed sync-outcome reads.

- [x] **Step 1: Write stale nested-reference regression**

  Reconcile a snapshot with comment/check references, advance the nested records and references to a higher sequence/URL, then reconcile an intermediate root snapshot. Assert both nested URLs and product mapping remain unchanged and reconciliation does not crash.

- [x] **Step 2: Write sync-outcome read outage regression**

  Configure `SyncOutcome => {:error, :database_unavailable}` for an otherwise valid webhook job. Assert the worker returns `{:error, "integration_storage_unavailable"}`, does not stage terminal metadata, and succeeds after the loader is restored.

- [x] **Step 3: Run both regressions and verify RED**

  Confirm stale nested URLs are overwritten or signal mapping receives an invalid reference, and confirm a sync-outcome read outage is currently cancelled as an invalid worker result.

- [x] **Step 4: Carry resource status through reconciliation**

  Pass `result.status` to comment/check `maybe_reference!/7`, return no reference for `:stale`, retain the status on each mapped item, and skip stale items before `WorkGraph.sync_integration_signal/4`.

- [x] **Step 5: Normalize sync-outcome reads and transaction exits**

  Route `outcome_by_operation/1` through `RecordLoader.read_one/3`, map read failures to `:integration_storage_unavailable`, and normalize that internal error to `{:error, {:retryable, :integration_storage_unavailable}}` on public reconciliation paths that cannot durably record an outcome during the outage.

- [ ] **Step 6: Verify reconciliation/worker modules and commit**

  Run both affected modules and commit as `fix: preserve reconciliation ordering outages`.

### Task 4: Use Read Semantics For Recovery And Persist Generic Terminal Reasons

**Files:**
- Modify: `test/office_graph/system_operations_test.exs`
- Modify: `lib/office_graph/operations.ex`
- Modify: `lib/office_graph/durable_delivery.ex`
- Modify: `lib/office_graph/durable_delivery/dispatch_event_worker.ex`
- Modify: `lib/office_graph/durable_delivery/system_conformance_worker.ex`
- Modify: `lib/office_graph/github_integration/webhook_worker.ex`

**Interfaces:**
- Produces: `Operations.read_operation/1` without `FOR UPDATE`; `DurableDelivery.stage_terminal_failure/2` as the shared safe metadata boundary.
- Preserves: transaction-scoped callers continue to use `Operations.lock_operation/1` and GitHub terminalization continues to acquire its advisory transaction lock in `Reconciler`.

- [ ] **Step 1: Write operation-read and conformance-history regressions**

  Add tests for `Operations.read_operation/1` returning an existing operation/not-found result. Insert a SystemConformanceWorker job for an ungranted service principal, run it, mark it cancelled as Oban would, and assert `DurableDelivery.list_terminal_jobs/2` exposes `system_conformance_forbidden` from job metadata.

- [ ] **Step 2: Run the regressions and verify RED**

  Confirm the read API is absent and the cancelled conformance job has no terminal reason.

- [ ] **Step 3: Add the non-locking read API and use it in webhook recovery**

  Implement the same scoped operation lookup result shape as `lock_operation/1` without `Ash.Query.lock(:for_update)`. Replace the two WebhookWorker recovery reads with `read_operation/1`; do not change transactional command paths.

- [ ] **Step 4: Centralize terminal metadata staging**

  Move the existing safe `Oban.update_job` metadata persistence/rescue logic behind `DurableDelivery.stage_terminal_failure/2`, use it in DispatchEventWorker, and have SystemConformanceWorker stage the safe code before cancelling or snooze for five seconds if staging fails.

- [ ] **Step 5: Verify durable worker behavior and commit**

  Run `mix test test/office_graph/system_operations_test.exs test/office_graph/durable_delivery/terminal_jobs_test.exs test/office_graph/durable_delivery/projection_invalidation_test.exs test/office_graph/github_integration/webhook_worker_test.exs`, then commit as `fix: persist recovery terminal reasons`.

### Task 5: Verify, Archive, Push, And Reply

**Files:**
- Modify: `docs/superpowers/plans/README.md`
- Move: this plan to `docs/superpowers/plans/archive/2026-07-15-github-review-replay-consistency-followthrough.md`

**Interfaces:**
- Consumes: cached PR snapshot `/tmp/office_graph_pr25_review_snapshot_20260715_6.json` and all six bot-last thread IDs plus CodeRabbit's cached outside-diff review body.
- Produces: a verified pushed head and evidence-backed replies/resolution without a post-push GitHub refresh.

- [ ] **Step 1: Run focused and repository-wide verification**

  Run the combined affected modules, `mix format --check-formatted`, `openspec validate --all --strict`, `./bin/verify`, and `git diff --check` inside Nix. Record exact test/spec counts and inspect every exit code.

- [ ] **Step 2: Record the Oban false-positive evidence**

  Cite the pinned Oban worker documentation and Basic engine implementation: execution increments `attempt`, snooze increments `max_attempts`, and `retry_budget/1` clamps the effective maximum back to ten. Make no retry-counter code change.

- [ ] **Step 3: Archive the plan and commit**

  Mark every checkbox complete, move this file under `archive/`, restore README to the internal-agent-runtime plan as the only active plan, and commit `docs: archive github replay review plan`.

- [ ] **Step 4: Push once**

  Push `codex/github-review-integration` and record the pushed SHA.

- [ ] **Step 5: Reply and resolve from the cached snapshot**

  Reply to the six bot-last threads with the root fix or no-change evidence, reply once to CodeRabbit's top-level review for the outside-diff-only findings, resolve warranted cached threads, and stop without fetching PR state again.
