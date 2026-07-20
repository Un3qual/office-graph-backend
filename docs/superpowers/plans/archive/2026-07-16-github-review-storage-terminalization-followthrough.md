# GitHub Review Storage Terminalization Follow-Through Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve retry classification for provider-neutral persistence failures and guarantee that an exhausted webhook creates one terminal sync outcome even when no retryable outcome could previously be stored.

**Architecture:** Keep retry semantics at the boundaries that own them. `Reconciler.reconcile_snapshot/5` owns the atomic provider snapshot transaction, so it will translate structured persistence failures into the existing safe storage-unavailable result. `Reconciler.exhaust_retry/3` owns fixed-budget terminalization, so its operation-scoped advisory lock will create the terminal outcome when the canonical outcome is still absent and update it when it already exists.

**Tech Stack:** Elixir 1.20, Erlang/OTP 29, Ash/AshPostgres, Ecto/PostgreSQL, Oban, ExUnit, OpenSpec, Nix flakes.

## Global Constraints

- Use the project Nix flake for every project command.
- Preserve the existing ten-attempt webhook retry budget and terminalization-only phase.
- Keep deterministic domain failures unchanged; only structured persistence failures normalize to `:integration_storage_unavailable`.
- Keep terminal outcome creation and update serialized by `github:sync-outcome:<operation-id>`.
- Add behavior regressions before production changes and observe each test fail for the reported reason.

---

### Task 1: Terminalize an exhausted retry when no outcome exists

**Files:**
- Modify: `test/office_graph/github_integration/webhook_worker_test.exs`
- Modify: `lib/office_graph/github_integration/reconciler.ex`

**Interfaces:**
- Consumes: `WebhookWorker.perform/1`, `Reconciler.exhaust_retry/3`, `ReconciliationRequest`.
- Produces: one terminal `SyncOutcome` with the request installation, object, and delivery identity when the operation has no prior outcome.

- [x] **Step 1: Write the failing worker regression**

Add a test that makes every `SyncOutcome` lookup unavailable on the exhausted normal attempt, proves the worker stages terminal metadata with no outcome, restores storage, and invokes the staged job again.

- [x] **Step 2: Run the regression and verify RED**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop -c mix test test/office_graph/github_integration/webhook_worker_test.exs
```

Expected: the recovered terminalization assertion fails because the call returns `{:snooze, 5}` instead of `{:cancel, "attempts_exhausted"}`; `terminalize_retry!/3` currently rolls back on `{:ok, nil}`.

- [x] **Step 3: Create the missing terminal outcome under the existing lock**

Change `terminalize_retry!` to accept the operation, validate that the request installation matches its GitHub installation authority basis, and persist terminal attributes when `outcome_by_operation/1` returns `nil`. Retain the existing request-identity checks for an existing outcome.

- [x] **Step 4: Run the regression and verify GREEN**

Expected: the staged job cancels, exactly one terminal outcome exists, and its `failure_class` and `failure_code` are both terminal storage-failure values.

- [x] **Step 5: Commit the terminalization fix**

```bash
git add test/office_graph/github_integration/webhook_worker_test.exs lib/office_graph/github_integration/reconciler.ex
git commit -m "fix: terminalize missing github sync outcomes"
```

### Task 2: Normalize provider-neutral persistence failures at the snapshot boundary

**Files:**
- Modify: `test/office_graph/github_integration/reconciliation_test.exs`
- Modify: `lib/office_graph/github_integration/reconciler.ex`

**Interfaces:**
- Consumes: `SoftwareProving.upsert_provider_resource/5` inside `Reconciler.reconcile_snapshot/5`.
- Produces: `{:error, {:retryable, :integration_storage_unavailable}}` for structured create or update failures, with the complete snapshot transaction rolled back.

- [x] **Step 1: Write failing create and update regressions**

Use temporary PostgreSQL check constraints on `repositories` to force a valid provider snapshot's create write and newer update write to fail. Assert the retryable storage result, no partial provider-neutral state for create, unchanged canonical state for update, and successful replay after each constraint is removed.

- [x] **Step 2: Run both regressions and verify RED**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop -c mix test test/office_graph/github_integration/reconciliation_test.exs
```

Expected: each assertion receives a structured Ash persistence error instead of the safe retry tuple.

- [x] **Step 3: Normalize structured snapshot transaction failures**

Extend the `Repo.transaction/1` result handling in `reconcile_snapshot/5`:

```elixir
{:error, error} when is_struct(error) -> retryable_storage_error()
```

Keep atom and tuple domain rollback reasons on their existing paths.

- [x] **Step 4: Run both regressions and the affected integration tests**

Expected: both regressions pass, recovery converges, and the existing reconciliation, product mapping, and worker storage tests stay green.

- [x] **Step 5: Commit the persistence classification fix**

```bash
git add test/office_graph/github_integration/reconciliation_test.exs lib/office_graph/github_integration/reconciler.ex
git commit -m "fix: preserve github storage retry classification"
```

### Task 3: Verify, archive, push, and reply

**Files:**
- Move: `docs/superpowers/plans/2026-07-16-github-review-storage-terminalization-followthrough.md` to `docs/superpowers/plans/archive/2026-07-16-github-review-storage-terminalization-followthrough.md`
- Modify: `docs/superpowers/plans/README.md`

**Interfaces:**
- Consumes: the two cached GitHub review thread IDs from the pre-push snapshot.
- Produces: a verified branch head and evidence-backed replies on both threads, without a post-push review refresh.

- [x] **Step 1: Run the full repository gate and diff hygiene**

```bash
nix --extra-experimental-features 'nix-command flakes' develop -c ./bin/verify
git diff --check
```

Expected: all checks pass and diff hygiene is clean.

- [x] **Step 2: Archive this completed plan and commit**

Move the plan to `archive/`, restore the README so the internal-agent-runtime plan remains the only active plan, and commit the archive state.

- [x] **Step 3: Push once**

```bash
git push origin codex/github-review-integration
```

- [x] **Step 4: Reply and resolve from the cached snapshot**

Reply to the two cached actionable review threads with the root fix and exact verification evidence, then resolve them. Do not refresh PR state after the push.
