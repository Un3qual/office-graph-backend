# GitHub Review Validation Follow-Through Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the four current PR #25 bot findings by fixing three verified contract gaps and answering the already-covered concurrency finding with concrete lock and test evidence.

**Architecture:** Keep reconciliation validation, storage normalization, and health aggregation at their existing owning boundaries. Reject cyclic comment-parent graphs before entering persistence, route extension and extension-target reads through `RecordLoader`, retain the transaction-scoped repository advisory lock that already serializes nested provider identities, and count terminal health by non-retryable failure class across both sync outcomes and outbound actions.

**Tech Stack:** Elixir 1.20, Erlang/OTP 29, Ash, AshPostgres, Ecto/PostgreSQL advisory locks, ExUnit, OpenSpec 1.4.1, Nix flakes.

## Global Constraints

- Use the pinned project Nix flake for every project runtime and CLI command.
- Treat `openspec/specs/github-review-integration/spec.md` and `openspec/specs/integration-health/spec.md` as the behavior source of truth; this batch repairs conformance and does not add a new product requirement.
- Preserve tenant scope, provider-neutral ownership, transaction rollback, retry classification, bounded health reads, and the fixed durable-delivery retry budget.
- Do not add redundant nested-resource locks when the existing repository-scoped transaction advisory lock already provides serialization.
- Use behavior tests; do not add source-string assertions.
- Push once after all checks pass, reply to the cached review threads, and do not fetch review state after the push.

---

### Task 1: Reject cyclic review-comment parent graphs before persistence

**Files:**
- Modify: `test/office_graph/github_integration/reconciliation_test.exs`
- Modify: `lib/office_graph/github_integration/reconciler.ex`

**Interfaces:**
- Consumes: `Adapter.ReconciliationSnapshot.review_comments` and `Reconciler.reconcile/2`.
- Produces: `valid_comment_parents?/1` accepts only in-batch parent references that form a directed acyclic graph; malformed cycles reach `record_failure/4` as `:invalid_provider_response` before provider-neutral writes.

- [x] **Step 1: Write the failing regression**

Add a reconciliation test with two otherwise-valid `Adapter.ReviewCommentSnapshot` values whose `parent_comment_node_id` fields point to one another. Assert `Reconciler.reconcile/2` returns `{:error, {:terminal, :invalid_provider_response}}`, writes one terminal `SyncOutcome` with `failure_code == "invalid_provider_response"`, and leaves `Repository` count at zero.

- [x] **Step 2: Run the focused test and verify RED**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop -c zsh -lc 'mix test test/office_graph/github_integration/reconciliation_test.exs'
```

Expected: FAIL because the current direct-parent validation accepts the cycle and persistence rolls back with the raw `:invalid_provider_response` error instead of recording the classified outcome.

- [x] **Step 3: Implement cycle-aware validation**

Build a `node_id => parent_comment_node_id` map after the existing uniqueness check. Keep the current missing-parent and self-parent rejection, then walk each parent chain with `:visiting` and `:visited` states so back-edges fail validation while roots and already-completed chains remain valid.

- [x] **Step 4: Run the focused test and verify GREEN**

Run the same command. Expected: all reconciliation tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/office_graph/github_integration/reconciler.ex test/office_graph/github_integration/reconciliation_test.exs
git commit -m "fix: reject cyclic review comment parents"
```

### Task 2: Normalize reconciliation extension-read outages

**Files:**
- Modify: `test/office_graph/github_integration/reconciliation_test.exs`
- Modify: `lib/office_graph/github_integration/reconciler.ex`

**Interfaces:**
- Consumes: `RecordLoader.read_one/3`, `RecordLoader.get/3`, scoped GitHub extension queries, and the transaction rollback classification consumed by `reconcile_snapshot/5`.
- Produces: extension and extension-target read failures roll back as `:integration_storage_unavailable`, which `Reconciler.reconcile/2` exposes as `{:error, {:retryable, :integration_storage_unavailable}}`.

- [ ] **Step 1: Write the failing regression**

Configure `RecordLoaderTestAdapter` so `RepositoryExtension` returns `{:error, :database_unavailable}` for a valid pull-request snapshot. Assert reconciliation returns the safe retryable storage classification, persists no provider-neutral repository, and can succeed when the adapter response is cleared and the same retryable operation is replayed.

- [ ] **Step 2: Run the focused test and verify RED**

Run the reconciliation test file. Expected: FAIL because `base_by_extension/5` calls `Ash.read_one/2` directly and the raw storage reason escapes the transaction.

- [ ] **Step 3: Implement the shared extension-read boundary**

Add a private `extension_by_node!/3` helper that evaluates `extension_by_node_query/3` through `RecordLoader.read_one/3`, returns the record or `nil`, and rolls back as `:integration_storage_unavailable` for any read error. Use it from both `base_by_extension/5` and `ensure_extension!/5`. Load the referenced base record through `RecordLoader.get/3` with `action: :read_with_deleted`, preserve `nil`, and normalize read errors through the same rollback code.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the reconciliation test file. Expected: all tests pass, including outage recovery.

- [ ] **Step 5: Commit**

```bash
git add lib/office_graph/github_integration/reconciler.ex test/office_graph/github_integration/reconciliation_test.exs
git commit -m "fix: normalize reconciliation extension outages"
```

### Task 3: Count all non-retryable integration failures as terminal health

**Files:**
- Modify: `test/office_graph/projections/integration_health_test.exs`
- Modify: `lib/office_graph/github_integration/health.ex`

**Interfaces:**
- Consumes: `SyncOutcome.failure_class`, `OutboundAction.failure_class`, and `RecordLoader.aggregate/4`.
- Produces: `terminal_count` includes `terminal`, `authorization`, and `configuration` failure classes while `retryable_count` includes only `retryable`.

- [ ] **Step 1: Write the failing regression**

Create authorization and configuration sync outcomes for one installation, read the health projection, and assert `terminal_count == 2`, `retryable_count == 0`, and both classified failures remain in `recent_failures`.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop -c zsh -lc 'mix test test/office_graph/projections/integration_health_test.exs'
```

Expected: FAIL with `terminal_count == 0` because the aggregate currently filters only the literal `state == "terminal"`.

- [ ] **Step 3: Aggregate by failure class**

Change the shared failure-count aggregates to count `failure_class == "retryable"` for retryable work and `failure_class in ["terminal", "authorization", "configuration"]` for terminal work. This produces the same semantics for sync outcomes and outbound actions even though they encode lifecycle state differently.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the integration-health test file. Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/office_graph/github_integration/health.ex test/office_graph/projections/integration_health_test.exs
git commit -m "fix: count classified terminal integration failures"
```

### Task 4: Prove existing nested identity serialization and close out the branch

**Files:**
- Verify: `lib/office_graph/github_integration/reconciler.ex`
- Verify: `test/office_graph/github_integration/reconciliation_concurrency_test.exs`
- Modify: `docs/superpowers/plans/README.md`
- Move: `docs/superpowers/plans/2026-07-16-github-review-validation-followthrough.md` to `docs/superpowers/plans/archive/2026-07-16-github-review-validation-followthrough.md`

**Interfaces:**
- Consumes: `Repo.query!("SELECT pg_advisory_xact_lock...")`, repository-scoped lock identity, and the distinct webhook-object concurrency regression.
- Produces: concrete evidence that same-repository pull-request/comment/check snapshots serialize before nested extension reads, without adding a second locking scheme.

- [ ] **Step 1: Run the concurrency proof**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop -c zsh -lc 'mix test test/office_graph/github_integration/reconciliation_concurrency_test.exs'
```

Expected: all tests pass; the distinct-object regression produces one canonical pull request, while source inspection confirms every snapshot transaction reaches the same repository lock before pull-request, thread, comment, or check extension access.

- [ ] **Step 2: Run the affected batch**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop -c zsh -lc 'mix test test/office_graph/github_integration/reconciliation_test.exs test/office_graph/github_integration/reconciliation_concurrency_test.exs test/office_graph/projections/integration_health_test.exs test/office_graph/github_integration/webhook_worker_test.exs'
```

Expected: all tests pass.

- [ ] **Step 3: Run the full repository gate and diff checks**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop -c zsh -lc './bin/verify'
git diff --check
```

Expected: both commands exit zero, including strict OpenSpec validation.

- [ ] **Step 4: Archive the plan and commit**

Move the plan into `docs/superpowers/plans/archive/`, restore the README so the internal-agent-runtime plan remains the only active plan, and commit:

```bash
git add docs/superpowers/plans/README.md docs/superpowers/plans/2026-07-16-github-review-validation-followthrough.md docs/superpowers/plans/archive/2026-07-16-github-review-validation-followthrough.md
git commit -m "docs: archive github review validation plan"
```

- [ ] **Step 5: Push and reply without refreshing**

Push `codex/github-review-integration` once. Reply in each of the four cached threads with the fix or no-change evidence and verification results, resolve those threads, and stop without any GitHub read after the push.
