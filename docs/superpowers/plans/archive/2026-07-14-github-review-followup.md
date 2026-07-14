# GitHub Review Follow-Up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct every valid fresh review-bot finding on PR #25, prove the existing reconciliation lock handles the one false-positive race report, and publish evidence-backed replies without refreshing after the final push.

**Architecture:** Preserve the provider reset time while enforcing the workers' original fixed ten-execution budget independently of Oban OSS snooze mutation. Keep reconciliation validation at the adapter boundary, make exhausted inbound outcomes durable before cancellation, and classify an unavailable adapter as configuration. Retain the existing repository-scoped transaction lock because it already serializes every pull request in that repository; strengthen its behavioral concurrency proof instead of adding a redundant PR lock.

**Tech Stack:** Elixir 1.20, Erlang/OTP 29, Phoenix, Ash, Ecto/Postgres advisory locks, Oban OSS, ExUnit, OpenSpec, project Nix flake, GitHub CLI.

## Global Constraints

- Use `nix --extra-experimental-features 'nix-command flakes' develop --command ...` for all project tools.
- OpenSpec remains the source of truth; fixes must conform to `openspec/specs/github-review-integration/spec.md` and `openspec/specs/durable-work-delivery/spec.md`.
- Retryable work must have a bounded attempt budget, rate-limited work must not retry before the bounded reset, and exhausted work must persist terminal state.
- Provider snapshots must be rejected before writes when check state, comment hierarchy, or requested-object identity is malformed.
- Preserve the existing provider-neutral resource model, organization/workspace isolation, and narrow outbound command surface.
- Do not add dependencies, expand into internal-agent-runtime work, use browser tools, or refresh GitHub review state after the final push.
- Add behavior-level regression coverage before production changes and observe each new behavior test fail for the expected reason.
- Commit the completed review-fix batch and push only the existing `codex/github-review-integration` branch for PR #25.

---

### Task 1: Bound Rate-Limit Snoozes and Persist Exhaustion

**Files:**
- Modify: `test/office_graph/github_integration/outbound_commands_test.exs`
- Modify: `test/office_graph/github_integration/webhook_worker_test.exs`
- Modify: `lib/office_graph/github_integration/outbound_worker.ex`
- Modify: `lib/office_graph/github_integration/webhook_worker.ex`
- Modify: `lib/office_graph/github_integration/reconciler.ex`

**Interfaces:**
- Consumes: `%Oban.Job{attempt: integer, max_attempts: integer}`, adapter `{:rate_limited, reset_at}` / transient errors, and the operation-scoped `SyncOutcome`.
- Produces: fixed ten-execution retry accounting, bounded `{:snooze, delay}` before exhaustion, terminal `OutboundAction`/`SyncOutcome` after exhaustion, and unchanged safe failure codes.

- [x] **Step 1: Add failing outbound and inbound exhaustion regressions**

Add an outbound test that simulates Oban OSS after nine snoozes by passing `%{job | attempt: 10, max_attempts: 19}` and expects:

```elixir
assert {:cancel, "attempts_exhausted"} = OutboundWorker.perform(snoozed_job)
assert %{state: "terminal", failure_code: "provider_rate_limited"} =
         Ash.get!(OutboundAction, action.id, authorize?: false)
```

Add webhook-worker tests for rate-limit and network exhaustion that expect the worker to cancel and the current outcome to become terminal:

```elixir
assert {:cancel, "attempts_exhausted"} = WebhookWorker.perform(exhausted_job)
assert %{state: "terminal", failure_class: "terminal", retry_at: nil} = outcome
```

- [x] **Step 2: Run the focused tests and confirm the intended failures**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/github_integration/outbound_commands_test.exs test/office_graph/github_integration/webhook_worker_test.exs
```

Expected: the rate-limit tests receive `{:snooze, _}` because current code compares against Oban's mutated `job.max_attempts`, and the transient exhaustion test leaves `SyncOutcome.state` as `"retryable"`.

- [x] **Step 3: Enforce the fixed worker budget and terminalize inbound outcomes**

Define one module attribute per worker and reuse it in `use Oban.Worker`:

```elixir
@max_attempts 10
use Oban.Worker, queue: :integrations, max_attempts: @max_attempts, ...
```

Before retry classification, normalize the job back to that fixed budget:

```elixir
defp retry_budget(%Oban.Job{} = job), do: %{job | max_attempts: @max_attempts}
```

For inbound failures, pass `operation` and `request` into normalization and call a new reconciler transition before cancellation:

```elixir
with {:ok, _outcome} <- Reconciler.exhaust_retry(operation, request, code) do
  {:cancel, "attempts_exhausted"}
end
```

`Reconciler.exhaust_retry/3` must only update the matching operation/request outcome while it is retryable, setting `state` and `failure_class` to `"terminal"`, preserving the safe provider failure code, and clearing `retry_at`.

- [x] **Step 4: Run the focused tests and confirm they pass**

Run the command from Step 2. Expected: all outbound and webhook-worker tests pass.

### Task 2: Preserve Configuration Classification for an Unavailable Adapter

**Files:**
- Modify: `test/office_graph/github_integration/outbound_commands_test.exs`
- Modify: `lib/office_graph/github_integration/outbound_worker.ex`

**Interfaces:**
- Consumes: adapter result `{:error, :adapter_unavailable}`.
- Produces: terminal action state with `failure_class: "configuration"`, `failure_code: "adapter_unavailable"`, and the existing configure-adapter remediation path.

- [x] **Step 1: Add the failing unavailable-adapter regression**

Temporarily configure `OfficeGraph.GitHubIntegration.Adapter.Unavailable`, perform an enqueued reply action, and assert:

```elixir
assert {:cancel, "adapter_unavailable"} = OutboundWorker.perform(job_for(action.id))
assert %{state: "terminal", failure_class: "configuration", failure_code: "adapter_unavailable"} =
         Ash.get!(OutboundAction, action.id, authorize?: false)
```

- [x] **Step 2: Run the focused test and confirm it fails**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/github_integration/outbound_commands_test.exs
```

Expected: current catch-all returns and persists `invalid_provider_response`.

- [x] **Step 3: Separate durable state from failure classification**

Add an explicit classification:

```elixir
defp classify(:adapter_unavailable, _job),
  do: {:configuration, :adapter_unavailable, {:cancel, "adapter_unavailable"}}
```

Persist `state: "terminal"` for cancel results while retaining `failure_class: "configuration"`; only exhausted retryable results should replace their failure class with `"terminal"`.

- [x] **Step 4: Run the focused test and confirm it passes**

Run the command from Step 2. Expected: the outbound suite passes.

### Task 3: Reject Invalid Snapshot State Before Writes

**Files:**
- Modify: `test/office_graph/github_integration/reconciliation_test.exs`
- Modify: `lib/office_graph/github_integration/reconciler.ex`

**Interfaces:**
- Consumes: `Adapter.CheckRunSnapshot` status/conclusion pairs and `Adapter.ReviewCommentSnapshot.review_thread_node_id` references.
- Produces: `{:error, {:terminal, :invalid_provider_response}}` and zero persistence for invalid snapshots.

- [x] **Step 1: Add failing check-invariant and dangling-thread regressions**

Add table-driven invalid snapshots for:

```elixir
%Adapter.CheckRunSnapshot{status: "completed", conclusion: nil}
%Adapter.CheckRunSnapshot{status: "in_progress", conclusion: "failure"}
%Adapter.ReviewCommentSnapshot{review_thread_node_id: "PRRT_missing"}
```

Each must be rejected by `Reconciler.reconcile/2` before repository/resource writes.

- [x] **Step 2: Run the focused reconciliation tests and confirm the intended failures**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/github_integration/reconciliation_test.exs
```

Expected: the malformed snapshots reconcile successfully under the current permissive checks.

- [x] **Step 3: Add closed-state validation helpers**

Require these exact state relationships:

```elixir
defp valid_check_state?(%{status: "completed", conclusion: conclusion}),
  do: conclusion in @check_conclusions

defp valid_check_state?(%{status: status, conclusion: nil})
     when status in ~w(queued in_progress),
     do: true

defp valid_check_state?(_check), do: false
```

Build a set from `snapshot.review_threads` and require every non-nil `review_thread_node_id` to be present before persistence.

- [x] **Step 4: Run the focused reconciliation tests and confirm they pass**

Run the command from Step 2. Expected: the reconciliation suite passes.

### Task 4: Match Webhook Database-ID Fallbacks

**Files:**
- Modify: `test/office_graph/github_integration/webhook_worker_test.exs`
- Modify: `lib/office_graph/github_integration/reconciler.ex`

**Interfaces:**
- Consumes: a numeric webhook `id` normalized to a decimal string and snapshot `node_id` / optional positive `database_id`.
- Produces: authoritative requested-object matching by either provider node ID or exact decimal database ID within the requested object type.

- [x] **Step 1: Add the failing end-to-end fallback regression**

Accept a pull-request webhook containing only `%{"id" => 602}`, configure the adapter under `{"pull_request", "602"}`, return a snapshot whose PR has `node_id: "PR_worker"` and `database_id: 602`, then assert `WebhookWorker.perform/1` succeeds and records an outcome with `object_id: "602"`.

- [x] **Step 2: Run the focused worker test and confirm it fails**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/github_integration/webhook_worker_test.exs
```

Expected: current matching compares only `node_id` and returns `invalid_provider_response`.

- [x] **Step 3: Centralize requested-object identity matching**

Use a helper for pull requests, comments, and checks:

```elixir
defp provider_object_matches?(object, object_id) do
  object.node_id == object_id or
    (is_integer(object.database_id) and Integer.to_string(object.database_id) == object_id)
end
```

- [x] **Step 4: Run the focused worker and reconciliation suites**

Run both worker and reconciliation test files. Expected: all tests pass.

### Task 5: Prove Distinct-Object Reconciliation Is Already Serialized

**Files:**
- Modify: `test/office_graph/github_integration/reconciliation_concurrency_test.exs`
- No production locking change.

**Interfaces:**
- Consumes: distinct review-comment and check-run requests that return the same repository and pull request snapshot.
- Produces: one canonical pull request under the existing repository-scoped transaction advisory lock.

- [x] **Step 1: Strengthen the concurrency scenario**

Replace the same-object request pair with one review-comment request and one check-run request, return the same snapshot containing both requested objects, run both operations concurrently, and keep:

```elixir
assert Enum.all?(results, &match?({:ok, _outcome}, &1))
assert Repo.aggregate(PullRequest, :count) == 1
```

- [x] **Step 2: Run the concurrency test as evidence**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/github_integration/reconciliation_concurrency_test.exs
```

Expected: PASS without a production lock change because `reconcile_repository!/3` acquires a transaction-scoped advisory lock before the pull-request lookup/create path.

### Task 6: Verify and Archive

**Files:**
- Modify: `docs/superpowers/plans/README.md`
- Move: `docs/superpowers/plans/2026-07-14-github-review-followup.md` to `docs/superpowers/plans/archive/2026-07-14-github-review-followup.md`

**Interfaces:**
- Consumes: completed fixes and cached fresh thread IDs.
- Produces: a verified change set ready for the single final push, plus cached reply instructions for each of the eight fresh threads.

- [x] **Step 1: Run focused verification and formatting checks**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix format --check-formatted
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/github_integration/outbound_commands_test.exs test/office_graph/github_integration/webhook_worker_test.exs test/office_graph/github_integration/reconciliation_test.exs test/office_graph/github_integration/reconciliation_concurrency_test.exs
git diff --check
```

- [x] **Step 2: Run the repository gate**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix verify
```

Expected: OpenSpec, backend, frontend, static analysis, Dialyzer, security/dependency checks, and builds all pass.

- [x] **Step 3: Archive this completed plan and update the plan index**

Move the plan under `docs/superpowers/plans/archive/` and list it under completed foundations in `docs/superpowers/plans/README.md`.

#### Post-archive publication instructions

Commit and push the verified change set:

Run:

```bash
git add docs/superpowers/plans lib/office_graph/github_integration test/office_graph/github_integration
git commit -m "fix: harden GitHub integration retries"
git push origin codex/github-review-integration
```

Reply directly to the cached fresh review threads:

Use GraphQL `addPullRequestReviewThreadReply` after the successful push. For the seven valid findings, state the root fix and verification. For `PRRT_kwDOS7ymi86Q4-7c`, explain that the existing repository advisory lock spans the transaction and include the distinct-object concurrency test evidence.

Then stop without another PR query. Do not refresh, poll, or wait for additional review state after the push and replies.
