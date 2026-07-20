# GitHub Review Thread And Scope Follow-Through Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the three current PR #25 bot findings by preserving reply-thread actionability, exact organization health authority, and canonical signal ownership of provider references.

**Architecture:** Treat persisted relationships as the source of truth. Review replies inherit their parent comment's persisted thread and compute actionability from that persisted thread id; integration health uses live scope-aware authorization because trusted capability sets are not scope-indexed; signal synchronization selects only a `references_external` edge whose source graph item is a signal, leaving other legitimate product links untouched.

**Tech Stack:** Elixir 1.20, Erlang/OTP 29, Ash, AshPostgres, Ecto/PostgreSQL, ExUnit, OpenSpec 1.4.1, Nix flakes.

## Global Constraints

- Use the pinned project Nix flake for every project runtime and CLI command.
- Treat `openspec/specs/github-review-integration/spec.md`, `openspec/specs/integration-health/spec.md`, and `openspec/specs/graph-relationships/spec.md` as the behavior source of truth; this batch repairs existing contracts and adds no new capability.
- Preserve provider ordering, tenant scope, transactional rollback, fixed query bounds, and the non-enumerating forbidden health response.
- Keep `references_external` available to every endpoint kind registered by the relationship vocabulary; identify the integration-owned signal edge without deleting or forbidding other product edges.
- Use behavior tests with explicit red/green runs; do not add source-string assertions.
- Push once after all checks pass, reply to cached review threads, and do not fetch review state after the push.

---

### Task 1: Inherit canonical thread state for review replies

**Files:**
- Modify: `test/office_graph/github_integration/product_mapping_test.exs`
- Modify: `lib/office_graph/github_integration/reconciler.ex`

**Interfaces:**
- Consumes: parent-before-child review-comment reconciliation, persisted `ReviewComment.review_thread_id`, and the node-id map of persisted `ReviewThread` records.
- Produces: a reply with no direct `review_thread_node_id` inherits its parent's persisted thread id; comment signal actionability reads that persisted id and therefore follows resolved or outdated thread truth.

- [x] **Step 1: Write the failing reply regression**

Extend the parent-relationship product-mapping test with a resolved thread and a published reply whose `parent_comment_node_id` points to a parent in that thread while `review_thread_node_id` is nil. Assert the reply persists the parent's `review_thread_id`, no signal is opened for either comment, and the reconciliation outcome has no signal ids.

- [x] **Step 2: Run the product-mapping test and verify RED**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop -c mix test test/office_graph/github_integration/product_mapping_test.exs
```

Expected: the reply has a nil thread id and reconciliation creates an open reply signal.

- [x] **Step 3: Carry parent records and use persisted thread ids**

Change the comment batch accumulator from node id to persisted comment record. For every ready comment, derive `parent_comment_id` from the parent record and derive the effective thread id from the explicit reconciled thread or, when omitted, the parent record. Persist that effective id. Build actionability state by persisted `ReviewThread.id` and look up `item.record.review_thread_id`; only a nil persisted thread remains independently actionable.

- [x] **Step 4: Run the product-mapping test and verify GREEN**

Confirm the new reply regression and the existing open, resolved, stale-thread, and parent-link behaviors pass.

### Task 2: Enforce exact health authority for trusted sessions

**Files:**
- Modify: `test/office_graph/projections/integration_health_test.exs`
- Modify: `lib/office_graph/github_integration/health.ex`

**Interfaces:**
- Consumes: `Authorization.authorize/3` with the installation's exact `organization_id` and nullable `workspace_id`.
- Produces: both ordinary and trusted workspace-only sessions receive `{:error, :forbidden}` for organization-scoped installation health, while principals with an organization-scoped role assignment remain authorized.

- [x] **Step 1: Write the failing trusted-session regression**

In the existing organization-health scope test, create a second workspace-only reader with `trusted?: true` and the cached `skeleton.read` capability. Assert the same non-enumerating forbidden result as the ordinary workspace reader.

- [x] **Step 2: Run the health test and verify RED**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop -c mix test test/office_graph/projections/integration_health_test.exs
```

Expected: the trusted workspace reader currently receives the organization health view.

- [x] **Step 3: Authorize the exact installation scope from live assignments**

At the health boundary, call `Authorization.authorize/3` rather than the trusted projection shortcut, passing the installation's exact organization and workspace scope. This projection is selected by an arbitrary installation id, so a capability cache without scope provenance cannot safely authorize it.

- [x] **Step 4: Run the health test and verify GREEN**

Confirm both workspace-only readers are forbidden and all bounded, safe health tests still pass.

### Task 3: Select only the integration-owned signal relationship

**Files:**
- Modify: `test/office_graph/github_integration/product_mapping_test.exs`
- Modify: `lib/office_graph/work_graph/system_commands.ex`

**Interfaces:**
- Consumes: the typed `references_external` relationship definition, its `source_item` relationship, and `Signal.graph_item_id`.
- Produces: signal refresh and close operations ignore unrelated active task, finding, check, artifact, and evidence links to the same external-reference graph item.

- [x] **Step 1: Write the failing relationship-ownership regression**

Reconcile a failing check to create one signal and its provider reference. Create a valid task graph item and a second active `references_external` relationship to the same reference. Reconcile the healthy check and assert the canonical signal closes while the unrelated relationship remains active.

- [x] **Step 2: Run the product-mapping test and verify RED**

Expected: the unscoped `Ash.read_one/2` reports multiple active relationships and reconciliation returns a retryable storage classification instead of closing the signal.

- [x] **Step 3: Filter the relationship lookup by signal source kind**

Add a source-item relationship predicate to `active_reference_relationship/2` so only an active `references_external` edge whose source graph item has `resource_type == "signal"` can identify the integration signal. Keep the existing definition, target, and lifecycle filters.

- [x] **Step 4: Run the product-mapping test and verify GREEN**

Confirm the canonical signal closes and reopens normally even while another valid product edge references the same provider object.

### Task 4: Verify, archive, push, and reply from the cached snapshot

**Files:**
- Modify: `docs/superpowers/plans/README.md`
- Move: `docs/superpowers/plans/2026-07-16-github-review-thread-scope-followthrough.md` to `docs/superpowers/plans/archive/2026-07-16-github-review-thread-scope-followthrough.md`

- [x] **Step 1: Run focused and affected verification**

Run the two affected test files, then the full GitHub integration, integration-health, and WorkGraph system-command coverage needed by the changed boundaries.

- [x] **Step 2: Run the repository gate**

```bash
nix --extra-experimental-features 'nix-command flakes' develop -c ./bin/verify
git diff --check
```

Expected: all backend, frontend, static, architecture, security, strict OpenSpec, and production build stages pass, and the diff is whitespace-clean.

- [x] **Step 3: Archive and commit the plan**

Move this plan to `docs/superpowers/plans/archive/`, restore the README so the internal-agent-runtime plan remains the only active plan, and commit the documentation closeout.

- [x] **Step 4: Push and reply without refreshing**

Push `codex/github-review-integration` once. Reply to and resolve cached threads `PRRT_kwDOS7ymi86Ri6hp`, `PRRT_kwDOS7ymi86Ri6hw`, and `PRRT_kwDOS7ymi86Ri6h2` with the exact fix and verification evidence. Do not perform any GitHub read after the push.
