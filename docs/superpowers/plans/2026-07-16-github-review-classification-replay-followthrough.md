# GitHub Review Classification And Replay Follow-Through Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve retryable storage classification across provider-source, archive, external-reference, and system-principal reads, while reconciling ambiguously successful review replies before a later target-version change can terminalize them incorrectly.

**Architecture:** Add a tagged non-bang wrapper around the existing conflict-safe repository insert primitive and use it only at integration public boundaries that already promise tagged results. Preserve a tagged failure channel through system-principal and capability reads instead of collapsing storage errors to `false`. Split review-reply lookup from creation so durable-action reconciliation may happen before the stale-version guard, while every new reply and check update still requires the current target version.

**Tech Stack:** Elixir 1.20, Erlang/OTP 29, Ash/AshPostgres, Ecto/PostgreSQL, Oban, ExUnit, OpenSpec, Nix flakes.

## Global Constraints

- Use the project Nix flake for every project command.
- Keep all public storage errors provider-neutral and expose only `:integration_storage_unavailable`.
- Preserve deterministic identity, scope, and stale-version failures; do not normalize them as storage outages.
- Preserve the ten-attempt durable-worker budget and existing terminalization phases.
- Never create a review reply or update a check after the target version changes.
- Add behavior regressions before production changes and observe each test fail for the reported reason.
- Use the cached pre-push thread IDs for replies and do not refresh after the final push.

---

### Task 1: Preserve tagged integration persistence failures

**Files:**
- Modify: `lib/office_graph/repo.ex`
- Modify: `lib/office_graph/integrations.ex`
- Modify: `lib/office_graph/external_refs.ex`
- Modify: `test/office_graph/github_integration/webhook_receipt_test.exs`
- Modify: `test/office_graph/github_integration/reconciliation_test.exs`

**Interfaces:**
- Consumes: `Repo.get_or_insert!/5`, `Integrations.ensure_provider_source/2`, `Integrations.archive_system_delivery/3`, and `ExternalRefs.upsert_provider_reference/3`.
- Produces: `Repo.get_or_insert/5 :: {:ok, struct()} | {:error, term()}` and safe `:integration_storage_unavailable` results from the three integration call paths.

- [x] **Step 1: Write failing receipt regressions**

Use temporary PostgreSQL check constraints on `external_sources` and `raw_archives` to make otherwise valid source and archive inserts fail. Assert `WebhookReceipt.accept/2 == {:error, :receipt_unavailable}` and assert that the receipt transaction leaves no archive, operation, event, or Oban job.

- [x] **Step 2: Write failing reconciliation regressions**

Use temporary PostgreSQL check constraints to reject the `github` provider source and the first matching `external_references.external_id`. Assert `Reconciler.reconcile/2 == {:error, {:retryable, :integration_storage_unavailable}}`, assert snapshot atomicity, remove each constraint, and assert replay converges.

- [x] **Step 3: Run the regressions and verify RED**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command zsh -lc 'mix test test/office_graph/github_integration/webhook_receipt_test.exs test/office_graph/github_integration/reconciliation_test.exs'
```

Expected: the constrained `Repo.get_or_insert!/5` calls raise `Postgrex.Error` instead of returning the safe receipt or retry result.

- [x] **Step 4: Add the tagged repository wrapper and use it at integration boundaries**

Add the wrapper without changing existing bang callers. Rescue the concrete
Ash, Ecto, PostgreSQL, DBConnection, and runtime exception classes that the
storage path can raise, and preserve caught exits or throws as tagged errors.

Change source, archive, and external-reference creation to consume this tagged result and map its error branch to `{:error, :integration_storage_unavailable}`. Keep existing identity-conflict checks after a successful insert or lookup.

- [x] **Step 5: Run the regressions and verify GREEN**

Expected: both receipt failures are safe and effect-free; both reconciliation failures are retryable and recover atomically.

### Task 2: Preserve system-principal authorization outages

**Files:**
- Modify: `lib/office_graph/identity.ex`
- Modify: `lib/office_graph/authorization.ex`
- Modify: `test/office_graph/system_operations_test.exs`

**Interfaces:**
- Consumes: system-principal status, capability, role-capability, role, and role-assignment reads.
- Produces: `Identity.active_system_principal/1 :: {:ok, boolean()} | {:error, :integration_storage_unavailable}` and tagged capability authorization that `Operations.start_system_operation/1` can propagate.

- [x] **Step 1: Write the failing operation regression**

Create a valid system operation request, temporarily set the sandbox transaction search path to `pg_catalog` so the principal table read fails, and assert `Operations.start_system_operation/1 == {:error, :integration_storage_unavailable}`. Restore `public` in an `after` block.

- [x] **Step 2: Run the regression and verify RED**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command zsh -lc 'mix test test/office_graph/system_operations_test.exs'
```

Expected: the principal read error is collapsed to `{:error, :forbidden}`.

- [x] **Step 3: Replace boolean-only system authorization reads with tagged reads**

Add `Identity.active_system_principal/1` that distinguishes active, inactive/missing, and storage-error results. Refactor the shared capability lookup to return `{:ok, boolean()}` or `{:error, :integration_storage_unavailable}` using non-bang Ash reads. Keep human-session authorization fail-closed by converting its tagged result back to a boolean, while `authorize_system_principal/4` propagates the storage error.

- [x] **Step 4: Run the operation and webhook-worker suites**

Expected: system operations preserve the storage classification and the worker's existing pre-operation storage branch remains green.

### Task 3: Reconcile existing review replies before stale-version rejection

**Files:**
- Modify: `openspec/specs/github-review-integration/spec.md`
- Modify: `lib/office_graph/github_integration/outbound_worker.ex`
- Modify: `test/office_graph/github_integration/outbound_commands_test.exs`

**Interfaces:**
- Consumes: `Adapter.find_review_reply/2`, `Adapter.reply_to_review/2`, `OutboundAction.expected_provider_version`.
- Produces: an existing provider reply matched by the durable action ID may complete the action after target advancement; a missing reply still reaches the stale-version guard before creation.

- [x] **Step 1: Clarify the OpenSpec interaction**

Add a scenario stating that an ambiguously successful reply is reconciled by durable action identity before stale-version rejection, and that the worker must not create a duplicate reply.

- [x] **Step 2: Write the failing replay regression**

Queue a review reply, advance the target comment version, configure `find_review_reply/2` to return the provider-side reply for the durable action ID, and assert the worker records success without calling `reply_to_review/2`.

- [x] **Step 3: Run the regression and verify RED**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command zsh -lc 'mix test test/office_graph/github_integration/outbound_commands_test.exs'
```

Expected: the worker returns `{:cancel, "stale_provider_version"}` before the durable-action lookup.

- [x] **Step 4: Split review-reply reconciliation from creation**

Normalize the durable input, call `find_review_reply/2`, and record a returned reply immediately. Only when the lookup returns `nil` should the worker call `require_current_target_version/1` and then `reply_to_review/2`. Keep check updates behind the unchanged version guard.

- [x] **Step 5: Verify both sides of the ordering invariant**

Expected: the new ambiguous-success regression passes; the existing delayed-stale regression performs the lookup but never creates a reply and remains terminal with `stale_provider_version`.

### Task 4: Verify, archive, push, and reply

**Files:**
- Move: `docs/superpowers/plans/2026-07-16-github-review-classification-replay-followthrough.md` to `docs/superpowers/plans/archive/2026-07-16-github-review-classification-replay-followthrough.md`
- Modify: `docs/superpowers/plans/README.md`

**Interfaces:**
- Consumes: cached thread IDs `PRRT_kwDOS7ymi86RkyPi`, `PRRT_kwDOS7ymi86RkyPl`, `PRRT_kwDOS7ymi86RkyPm`, `PRRT_kwDOS7ymi86RkyPp`, and `PRRT_kwDOS7ymi86RkyPt`.
- Produces: one verified branch head plus evidence-backed replies and resolved current threads, without a post-push query.

- [x] **Step 1: Run focused verification**

Run the four affected test files in the Nix shell and run strict OpenSpec validation for the canonical specs.

- [x] **Step 2: Run the full repository gate and diff hygiene**

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command zsh -lc './bin/verify'
git diff --check
```

Expected: every gate passes and the diff is clean.

- [ ] **Step 3: Commit the implementation**

```bash
git add lib test openspec/specs/github-review-integration/spec.md
git commit -m "fix: preserve github retry and reply replay semantics"
```

- [ ] **Step 4: Archive the completed plan and commit**

Move this file under `docs/superpowers/plans/archive/`, update the plan index so internal-agent-runtime is again the only active plan, and commit the archive state.

- [ ] **Step 5: Push once, then reply and resolve cached threads**

```bash
git push origin codex/github-review-integration
```

Reply with the root fix and exact verification evidence, resolve the five cached threads, and stop. Do not refresh PR state after the push.
