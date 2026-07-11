# Close Completed OpenSpec Changes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Synchronize and archive the three complete OpenSpec changes so feature-completion branches start from current durable specifications.

**Architecture:** Apply each change's delta specs to `openspec/specs/` in dependency order, validate the synchronized capability, then move the complete change under the dated archive. Keep one commit per archived change so the closure history is reviewable and independently reversible.

**Tech Stack:** OpenSpec 1.4.1, Markdown specifications, Git, project Nix flake.

## Global Constraints

- Run OpenSpec through `nix --extra-experimental-features 'nix-command flakes' develop --command`.
- Use OpenSpec as the workflow source of truth.
- Preserve all existing main-spec requirements not named by a delta spec.
- Make spec synchronization idempotent: reapplying a delta must not duplicate a requirement or scenario.
- Archive in this exact order: `add-packets-route`, `adopt-relay-suspense-hooks`, `eliminate-backend-query-fanout`.
- Do not change product code in this PR.

---

### Task 1: Synchronize And Archive The Packet Workspace

**Files:**
- Modify: `openspec/specs/frontend-architecture/spec.md`
- Create: `openspec/specs/packet-workspace/spec.md`
- Move: `openspec/changes/add-packets-route/` to `openspec/changes/archive/2026-07-10-add-packets-route/`

**Interfaces:**
- Consumes: completed `add-packets-route` delta specs and tasks.
- Produces: durable packet-workspace requirements and the baseline required by the Relay Suspense change.

- [x] **Step 1: Confirm the change is complete and repo-local**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command openspec status --change add-packets-route --json
```

Expected: `isComplete` is `true`, all four artifacts are `done`, and `actionContext.mode` is `repo-local`.

- [x] **Step 2: Add the route-navigation requirement to the main frontend specification**

Append the complete `Available Product Navigation Uses Route Links` requirement from `openspec/changes/add-packets-route/specs/frontend-architecture/spec.md` under the main `## Requirements` section. Preserve every existing frontend requirement and add the requirement only once.

- [x] **Step 3: Create the durable packet-workspace specification**

Create `openspec/specs/packet-workspace/spec.md` with this header followed by every requirement and scenario from the delta spec:

```markdown
# packet-workspace Specification

## Purpose

Define the dedicated packet product route, its Relay-owned read states,
route-local selection, pagination, and packet summary behavior.

## Requirements
```

Copy the three delta requirements without the `## ADDED Requirements` wrapper:

- `Packet Workspace Reads Packets Through Relay`
- `Packet Selection Is Route-Local`
- `Packet Workspace Presents Product Summary Fields`

- [x] **Step 4: Validate the synchronized specs**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --specs --strict
nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate add-packets-route --strict
```

Expected: both commands pass with no specification failures.

- [x] **Step 5: Archive the complete change**

Run:

```bash
mkdir -p openspec/changes/archive
mv openspec/changes/add-packets-route openspec/changes/archive/2026-07-10-add-packets-route
```

Expected: `openspec/changes/add-packets-route` no longer exists and the dated archive contains proposal, design, specs, and tasks.

- [x] **Step 6: Commit the packet closure**

```bash
git add -A openspec
git commit -m "docs: archive packet workspace change"
```

### Task 2: Synchronize And Archive Relay Suspense Hooks

**Files:**
- Modify: `openspec/specs/frontend-architecture/spec.md`
- Modify: `openspec/specs/operator-console/spec.md`
- Move: `openspec/changes/adopt-relay-suspense-hooks/` to `openspec/changes/archive/2026-07-10-adopt-relay-suspense-hooks/`

**Interfaces:**
- Consumes: packet-workspace durable spec from Task 1.
- Produces: durable Relay render-time and operator dependent-read requirements.

- [x] **Step 1: Confirm the change is complete and repo-local**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command openspec status --change adopt-relay-suspense-hooks --json
```

Expected: `isComplete` is `true`, all four artifacts are `done`, and `actionContext.mode` is `repo-local`.

- [x] **Step 2: Add the Relay boundary requirements to the main frontend specification**

Append these complete delta requirements once under `openspec/specs/frontend-architecture/spec.md` `## Requirements`:

- `Relay Product Reads Use Render-Time Boundaries`
- `Shared Async Boundaries Stay Product Neutral`

Preserve all existing requirements, including the packet navigation requirement synchronized in Task 1.

- [x] **Step 3: Add the operator dependent-read requirement**

Append the complete `Operator Dependent Relay Reads Preserve Workspace Context` requirement from the delta to `openspec/specs/operator-console/spec.md`, including all five scenarios.

- [x] **Step 4: Validate the synchronized specs**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --specs --strict
nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate adopt-relay-suspense-hooks --strict
```

Expected: both commands pass with no specification failures.

- [x] **Step 5: Archive the complete change**

Run:

```bash
mv openspec/changes/adopt-relay-suspense-hooks openspec/changes/archive/2026-07-10-adopt-relay-suspense-hooks
```

Expected: only the dated archive contains this change.

- [x] **Step 6: Commit the Relay closure**

```bash
git add -A openspec
git commit -m "docs: archive Relay Suspense change"
```

### Task 3: Synchronize And Archive Backend Query Efficiency

**Files:**
- Create: `openspec/specs/backend-query-efficiency/spec.md`
- Move: `openspec/changes/eliminate-backend-query-fanout/` to `openspec/changes/archive/2026-07-10-eliminate-backend-query-fanout/`

**Interfaces:**
- Consumes: completed backend query-fanout change.
- Produces: durable bounded-query and bulk-write requirements for every later program PR.

- [x] **Step 1: Confirm the change is complete and repo-local**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command openspec status --change eliminate-backend-query-fanout --json
```

Expected: `isComplete` is `true`, all four artifacts are `done`, and `actionContext.mode` is `repo-local`.

- [x] **Step 2: Create the durable backend-query-efficiency specification**

Create `openspec/specs/backend-query-efficiency/spec.md` with this header followed by every requirement and scenario from the delta spec:

```markdown
# backend-query-efficiency Specification

## Purpose

Define bounded database query shapes, Ash-native collection writes,
batch-equivalent validation, stable collection ordering, and focused query
regression coverage for cardinality-sensitive backend paths.

## Requirements
```

Copy the delta requirements without the `## ADDED Requirements` wrapper:

- `Cardinality-Sensitive Reads Have Bounded Query Shape`
- `Collection Writes Use Ash-Native Bulk Actions`
- `Bulk Validation Is Batched And Equivalent`
- `Query Efficiency Has Focused Regression Coverage`

- [x] **Step 3: Validate the synchronized specs**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --specs --strict
nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate eliminate-backend-query-fanout --strict
```

Expected: both commands pass with no specification failures.

- [x] **Step 4: Archive the complete change**

Run:

```bash
mv openspec/changes/eliminate-backend-query-fanout openspec/changes/archive/2026-07-10-eliminate-backend-query-fanout
```

Expected: only the dated archive contains this change.

- [x] **Step 5: Commit the query-efficiency closure**

```bash
git add -A openspec
git commit -m "docs: archive backend query efficiency change"
```

### Task 4: Verify The Clean OpenSpec Baseline

**Files:**
- Modify: `docs/superpowers/plans/2026-07-10-close-completed-changes.md`
- Modify: `docs/superpowers/plans/README.md`

**Interfaces:**
- Consumes: all three archived changes and synchronized main specs.
- Produces: a clean baseline from which PRs 2 through 7 branch.

- [x] **Step 1: Confirm no active OpenSpec changes remain**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command openspec list --json
```

Expected: the returned `changes` array is empty.

- [x] **Step 2: Run strict repo-wide OpenSpec validation**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --specs --strict
nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --changes --strict
```

Expected: durable specs pass; change validation reports no active changes rather than a failure.

- [x] **Step 3: Check repository integrity**

Run:

```bash
git diff --check
git status --short
```

Expected: no whitespace errors and only the plan completion/README files remain uncommitted.

- [x] **Step 4: Record plan completion**

Change every task checkbox in this plan from `[ ]` to `[x]`. Update `docs/superpowers/plans/README.md` so it names no active plan and move this plan to `docs/superpowers/plans/archive/2026-07-10-close-completed-changes.md`.

- [x] **Step 5: Commit the completed plan**

```bash
git add -A docs/superpowers/plans
git commit -m "docs: complete OpenSpec closure plan"
```

- [x] **Step 6: Review the branch**

Run:

```bash
git log --oneline origin/main..HEAD
git diff --check origin/main...HEAD
git status --short --branch
```

Expected: the branch contains the program design, closure plan, three archive commits, and plan-completion commit; the worktree is clean.
