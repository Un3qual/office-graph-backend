# GitHub Review Storage Boundary Follow-through Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve the three fresh PR #25 review findings by making every outbound validation read preserve integration storage outages through the public API, and repair the concurrent-index migration that currently deadlocks fresh CI databases.

**Architecture:** Route GitHub extension and reconciliation-provenance reads through the existing `RecordLoader` seam so a missing row remains non-enumerating while a failed read becomes `:integration_storage_unavailable`. Give that safe atom one explicit transport classification with HTTP 503 JSON semantics and the same stable GraphQL extension code. Keep the existing online index migration, but disable Ecto's migration lock as required for concurrent PostgreSQL DDL.

**Tech Stack:** Elixir 1.20, Erlang/OTP 29, Ash 3, AshPostgres 2, Ecto/PostgreSQL, ExUnit, OpenSpec, Nix.

## Global Constraints

- Run all project commands through `nix --extra-experimental-features 'nix-command flakes' develop`.
- Treat canonical `openspec/specs/` and the archived GitHub change specs as the behavior contract.
- Observe each regression fail for the expected reason before changing production code.
- Preserve non-enumerating `:forbidden` behavior for genuinely missing or cross-scope records.
- Do not broaden into deferred identity/governance or unrelated integration refactors.
- Commit coherent batches, push `codex/github-review-integration` once at the end, reply from the cached pre-push snapshot, and do not refresh GitHub after pushing.

---

### Task 1: Preserve Secondary Outbound Read Failures

**Files:**
- Modify: `test/office_graph/github_integration/outbound_commands_test.exs`
- Modify: `lib/office_graph/github_integration/outbound_commands.ex`

**Interfaces:**
- Consumes: `RecordLoader.read_one/3`, `ReviewCommentExtension`, `CheckRunExtension`, and `SyncOutcome`.
- Produces: `{:error, :integration_storage_unavailable}` for failed extension or provenance reads; `{:error, :forbidden}` only for missing extension or missing provenance.

- [x] **Step 1: Add failing extension-read regressions**

  Add one table-driven test that configures `RecordLoaderTestAdapter` to fail `ReviewCommentExtension` during `reply_to_review/3` and `CheckRunExtension` during `update_check/3`, then asserts `{:error, :integration_storage_unavailable}`, zero `OutboundAction` rows, and zero outbound jobs.

- [x] **Step 2: Run the extension regressions and verify RED**

  Run `mix test test/office_graph/github_integration/outbound_commands_test.exs` in Nix and confirm both extension cases return raw storage errors rather than the safe atom.

- [x] **Step 3: Add a failing provenance-read regression**

  Configure `SyncOutcome => {:error, :database_unavailable}` for an otherwise valid reconciled reply target and assert the command returns `{:error, :integration_storage_unavailable}` without creating an action or job.

- [x] **Step 4: Run the provenance regression and verify RED**

  Run the same focused test module and confirm the command currently returns `{:error, :forbidden}`.

- [x] **Step 5: Route all three reads through `RecordLoader`**

  Replace direct extension `Ash.read_one/2` calls with `RecordLoader.read_one/3`, mapping `{:ok, nil}` to forbidden and `{:error, _}` to storage unavailable. Replace `Ash.exists?/2` provenance probing with a bounded `RecordLoader.read_one/3` query and the same three-way result handling.

- [x] **Step 6: Run the outbound command module and verify GREEN**

  Run `mix test test/office_graph/github_integration/outbound_commands_test.exs` and confirm every test passes.

- [x] **Step 7: Commit the outbound storage-boundary fix**

  Stage the outbound command module and test, then commit `fix: preserve outbound storage outages`.

### Task 2: Expose A Safe Public Availability Classification

**Files:**
- Modify: `test/office_graph_web/operator_command_semantics_test.exs`
- Modify: `lib/office_graph_web/operator_commands/errors.ex`
- Modify: `lib/office_graph_web/json_api/common/errors.ex`
- Modify: `openspec/specs/github-review-integration/spec.md`
- Modify: `openspec/changes/archive/2026-07-14-add-github-review-integration/specs/github-review-integration/spec.md`

**Interfaces:**
- Consumes: `Errors.classify/1`, GraphQL `extensions.code`, and JSON command error rendering.
- Produces: category `:availability`, code `integration_storage_unavailable`, detail `Integration storage is temporarily unavailable.`, empty metadata, and HTTP 503 for JSON.

- [x] **Step 1: Add a failing transport parity case**

  Extend the table-driven public error semantics test with `:integration_storage_unavailable`, expected category `:availability`, stable code and detail, empty metadata, and JSON status 503.

- [x] **Step 2: Run the semantics test and verify RED**

  Run `mix test test/office_graph_web/operator_command_semantics_test.exs` in Nix and confirm the current fallback reports `validation_failed` with HTTP 422.

- [x] **Step 3: Implement the explicit sanitized classification**

  Add `:availability` to the classification type, add an exact `classify(:integration_storage_unavailable)` clause before the catch-all, and map `:availability` to `:service_unavailable` in the JSON renderer.

- [x] **Step 4: Tighten canonical and archived OpenSpec text**

  Extend the existing integration-record outage scenario so public JSON commands and health reads return HTTP 503 while GraphQL returns the same safe `integration_storage_unavailable` code, without internal storage details.

- [x] **Step 5: Run transport tests and strict OpenSpec validation**

  Run `mix test test/office_graph_web/operator_command_semantics_test.exs test/office_graph_web/github_actions_api_test.exs` and `openspec validate --all --strict` in Nix and confirm both pass.

- [x] **Step 6: Commit the public availability contract**

  Stage the classifier, renderer, tests, and synchronized specs, then commit `fix: classify integration storage outages`.

### Task 3: Repair Fresh-Database Concurrent Migration Execution

**Files:**
- Modify: `test/office_graph/software_proving/migration_test.exs`
- Modify: `priv/repo/migrations/20260714111000_scope_external_source_identities.exs`

**Interfaces:**
- Consumes: Ecto migration metadata and PostgreSQL concurrent index creation.
- Produces: `disable_ddl_transaction: true` and `disable_migration_lock: true` for the online external-source identity migration.

- [x] **Step 1: Add a failing migration metadata assertion**

  Extend `external source identity indexes migrate concurrently and remain irreversible` to assert `migration.__migration__()[:disable_migration_lock]`.

- [x] **Step 2: Run the migration test and verify RED**

  Run `mix test test/office_graph/software_proving/migration_test.exs` and confirm the new assertion fails because the lock flag is absent.

- [x] **Step 3: Disable the migration lock**

  Add `@disable_migration_lock true` next to the existing `@disable_ddl_transaction true`; do not change the already-reviewed index identity or irreversible down path.

- [x] **Step 4: Verify the migration on tests and a fresh isolated database**

  Run the focused migration test, then create and migrate a uniquely suffixed test database with `MIX_TEST_PARTITION=_review_storage_boundary`; confirm migration completes without the concurrent-index lock warning or timeout, then drop only that isolated database.

- [x] **Step 5: Commit the migration execution fix**

  Stage the migration and regression, then commit `fix: disable lock for concurrent migration`.

### Task 4: Verify, Archive, Push, And Reply

**Files:**
- Modify: `docs/superpowers/plans/README.md`
- Move: this plan to `docs/superpowers/plans/archive/2026-07-15-github-review-storage-boundary-followthrough.md`

**Interfaces:**
- Consumes: the cached PR snapshot `/tmp/office_graph_pr25_review_snapshot_20260715_5.json` and its three fresh thread IDs.
- Produces: a clean repository gate, one pushed branch head, and evidence-backed replies/resolution for `PRRT_kwDOS7ymi86RRYvi`, `PRRT_kwDOS7ymi86RRYvo`, and `PRRT_kwDOS7ymi86RRYvt`.

- [ ] **Step 1: Run focused and complete verification**

  Run the combined affected modules, `mix format --check-formatted`, `openspec validate --all --strict`, `mix verify`, and `git diff --check` in Nix; inspect every exit code and test count.

- [ ] **Step 2: Archive the completed plan**

  Mark every checkbox complete, move this file under `docs/superpowers/plans/archive/`, restore the README to list only the internal-agent-runtime plan as active, and commit `docs: archive github storage review plan`.

- [ ] **Step 3: Push once**

  Push `codex/github-review-integration` and record the pushed head SHA.

- [ ] **Step 4: Reply to and resolve the cached review threads**

  Reply in each cached thread with the root-cause fix, pushed commit evidence, and exact verification results, resolve each thread, and stop without fetching PR state again.
