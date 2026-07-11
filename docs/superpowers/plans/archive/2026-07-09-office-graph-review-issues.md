# Office Graph Review Issues Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Analyze each issue in `code-review-issues-2026-07-09.md`, fix the issues that are still valid, and commit in reviewable slices.

**Architecture:** Keep the changes aligned with the current OpenSpec contracts: backend projections own command/readiness/run-state semantics, GraphQL preserves structured domain errors, and the React operator console consumes backend command affordances without reconstructing domain internals. Avoid broad UI redesign and keep the release asset pipeline pointed at the React Router app shell only.

**Tech Stack:** Elixir 1.20, Phoenix, Ash, Absinthe GraphQL, Postgres/Ecto, React 19, React Router, Relay, Vitest, StyleX/plain CSS, project Nix flake.

> **Archive status:** Completed. Checked RED steps record that the intended failing regression was observed before its fix. The dependency advisory baseline was resolved, and no final verification or review-follow-up exceptions remain.

## Global Constraints

- Use `nix --extra-experimental-features 'nix-command flakes' develop --command ...` for project tools.
- OpenSpec is the source of truth; check `openspec/project.md` and relevant specs before behavior changes.
- Tailwind CSS, shadcn, Phoenix LiveView, and Tailwind utility conventions are forbidden.
- Preserve the unreleased-product bias: remove stale demo paths when no current caller or verification need exists.
- Use TDD for behavior changes: add or update focused tests first, watch them fail for the intended reason, then implement.
- Commit after each coherent slice.

---

### Task 1: Branch, Baseline, And Planning Artifacts

**Files:**
- Keep: `code-review-issues-2026-07-09.md`
- Create: `docs/superpowers/plans/2026-07-09-office-graph-review-issues.md`

**Interfaces:**
- Consumes: current detached worktree and untracked review issue file.
- Produces: branch `codex/fix-office-graph-review-issues` and committed review/plan baseline.

- [x] **Step 1: Verify isolated worktree and branch**

Run:

```bash
git rev-parse --git-dir
git rev-parse --git-common-dir
git branch --show-current
git status --short --branch
```

Expected: linked worktree, branch `codex/fix-office-graph-review-issues`, no production edits.

- [x] **Step 2: Run baseline checks**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command openspec list
nix --extra-experimental-features 'nix-command flakes' develop --command mix test
nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets run test
nix --extra-experimental-features 'nix-command flakes' develop --command mix hex.audit
```

Expected: OpenSpec lists current changes; backend/frontend tests pass; `mix hex.audit` fails with the advisory set recorded in the review file.

- [x] **Step 3: Commit baseline artifacts**

Run:

```bash
git add code-review-issues-2026-07-09.md docs/superpowers/plans/2026-07-09-office-graph-review-issues.md
git commit -m "docs: record office graph review issue plan"
```

Expected: first branch commit contains only the review issue handoff and execution plan.

### Task 2: Clear Dependency Advisories And Remove Legacy Release Build Output

**Files:**
- Modify: `mix.exs`
- Modify: `mix.lock`
- Modify: `assets/package.json`
- Modify as needed: `assets/pnpm-lock.yaml`
- Modify/delete as needed: `assets/src/main.tsx`, `assets/src/App.tsx`, `assets/src/App.test.tsx`, `assets/vite.config.ts`

**Interfaces:**
- Consumes: `mix hex.audit`, `mix assets.build`, `pnpm --dir assets run verify`.
- Produces: locked dependencies with no Hex advisories and a release pipeline that emits React Router app-shell assets without stale `operator-console-root` output.

- [x] **Step 1: Update backend dependency locks**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix deps.update ash phoenix plug hpax
```

Expected: `mix.lock` updates the minimum needed dependency versions and transitive packages.

- [x] **Step 2: Verify the audit is clean**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix hex.audit
```

Expected: no advisories. If advisories remain, inspect the affected dependency constraints in `mix.exs`, adjust the narrow constraints, rerun `mix deps.update`, and repeat this step.

- [x] **Step 3: Make `pnpm run build` mean the current React Router build**

Edit `assets/package.json` so `build` invokes `react-router build --config vite.react-router.config.ts`, `router:build` aliases to `pnpm run build`, and `router:deploy` runs `pnpm run build && node scripts/prepare-app-shell-assets.mjs`.

- [x] **Step 4: Remove the duplicate build from the Mix asset alias**

Edit `mix.exs` so `assets.build` runs `assets.setup`, `cmd --cd assets pnpm run router:deploy`, and `cmd --cd assets pnpm run verify:app-shell`.

- [x] **Step 5: Delete or quarantine unused legacy app entrypoints**

Search:

```bash
rg -n "operator-console-root|src/main|<App|from \"./App\"|from './App'" assets lib test
```

If only the legacy Vite entry and its unit test use them, delete `assets/src/main.tsx`, `assets/src/App.tsx`, and `assets/src/App.test.tsx`; otherwise update remaining current callers first.

- [x] **Step 6: Verify asset pipeline**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets run test
nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets run verify:app-shell
nix --extra-experimental-features 'nix-command flakes' develop --command mix assets.build
```

Expected: frontend tests pass, app-shell verification passes, and the release asset build does not create stale `assets/operator/*.js` output.

- [x] **Step 7: Commit**

Run:

```bash
git add mix.exs mix.lock assets/package.json assets/pnpm-lock.yaml assets/src assets/vite.config.ts
git commit -m "build: use router asset pipeline"
```

Expected: second commit contains dependency and release-pipeline changes only.

### Task 3: Backend Projection And GraphQL Contract Fixes

**Files:**
- Modify: `lib/office_graph/authorization.ex`
- Modify: `lib/office_graph/projections/command_affordance.ex`
- Modify: `lib/office_graph/projections/operator_workflow.ex`
- Modify: `lib/office_graph/projections/packet_readiness.ex`
- Modify: `lib/office_graph/projections/run_state.ex`
- Modify: `lib/office_graph/runs.ex`
- Modify: `lib/office_graph_web/graphql/common/errors.ex`
- Modify: `lib/office_graph_web/graphql/operator_workflow/types.ex`
- Test: `test/office_graph/projections/operator_workflow_test.exs`
- Test: `test/office_graph_web/operator_workflow_api_test.exs`
- Test: `test/office_graph_web/packet_run_verification_api_test.exs`

**Interfaces:**
- Consumes: `SessionContext.capabilities`, packet readiness input, run summaries, `PacketRunVerification.execute/2` errors.
- Produces: projection authorization from trusted session facts, meaningful source watermarks, failed-check reasons, backend command input defaults, and stable packet-run GraphQL error extensions.

- [x] **Step 1: Add failing authorization query-count test**

Change the test named `trusted session capabilities are revalidated for projection reads` so it asserts projection reads do not hit `capabilities`, `role_capabilities`, `roles`, or `role_assignments` when trusted session capabilities are present.

- [x] **Step 2: Make command affordances use trusted capabilities**

Add a capability-check function that maps the action atom to the required capability and checks `session_context.capabilities` after `Identity.validate_session_context/1`. Keep `Authorization.authorize/3` for command execution and read authorization.

- [x] **Step 3: Add failing failed-check reason test**

Update `operator run state exposes failed evidence without completing the workflow` to expect `%{reason: "failed_check"}` for the accepted failed result.

- [x] **Step 4: Implement failed-check reason calculation**

Change `Runs.missing_evidence/2` so required checks with failed verification results return `failed_check`, and checks with no accepted result continue to return `missing_accepted_evidence`.

- [x] **Step 5: Add failing source-watermark tests**

Add assertions that packet readiness returns a non-nil watermark for source/check input and that run-state `source_watermark` changes after recording an observation or accepting evidence.

- [x] **Step 6: Implement projection source watermarks**

Build packet readiness watermarks from source graph item ids, required check ids, and blocker-relevant state. Build run-state watermarks as a stable digest of run, packet version, required checks, observations, evidence candidates, evidence items, verification results, and missing/failed reason projections.

- [x] **Step 7: Add backend command default input shape**

Extend `operator_command_affordance` with a typed `input_defaults` list of key/value entries or a dedicated object shape. Populate `prepare_packet` defaults in `OperatorWorkflow` from graph links and update GraphQL API tests to request and assert those defaults.

- [x] **Step 8: Add packet-run error mapping tests**

Update `PacketRunVerificationApiTest` so invalid source/check mismatch asserts a stable code such as `source_graph_item_check_mismatch`. Add tests for invalid readiness input and invalid evidence result if the existing fixtures can cover them without broad setup.

- [x] **Step 9: Implement packet-run error mappings**

Add `normalize/1` clauses in `OfficeGraphWeb.GraphQL.Common.Errors` for `:source_graph_item_check_mismatch`, `:invalid_packet_run_input`, `:invalid_evidence_result`, and `:invalid_packet_run_evidence_input`, with safe detail strings and stable extension codes.

- [x] **Step 10: Verify backend slice**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/projections/operator_workflow_test.exs test/office_graph_web/operator_workflow_api_test.exs test/office_graph_web/packet_run_verification_api_test.exs
nix --extra-experimental-features 'nix-command flakes' develop --command mix format --check-formatted
```

Expected: focused backend tests pass and formatting is clean.

- [x] **Step 11: Commit**

Run:

```bash
git add lib test
git commit -m "fix: align operator projection contracts"
```

Expected: third commit contains backend projection and GraphQL contract fixes only.

### Task 4: Frontend Operator Workflow Fixes

**Files:**
- Modify: `assets/app/relay/fetchGraphQL.ts`
- Modify: `assets/app/relay/fetchGraphQL.test.ts`
- Modify: `assets/app/routes/operator/data.ts`
- Modify: `assets/app/routes/operator/derived.ts`
- Modify: `assets/app/routes/operator/workflow.ts`
- Modify: `assets/app/routes/operator/types.ts`
- Modify: `assets/app/routes/operator/route.test.tsx`
- Modify: `assets/app/routes/operator/components/ReadinessPanel.tsx`
- Modify: `assets/app/routes/operator/components/RunPanel.tsx`
- Modify: `assets/app/routes/operator/components/VerificationPanel.tsx`
- Modify: `assets/src/styles/global.css`

**Interfaces:**
- Consumes: Relay `GraphQLResponse`, backend command affordances, `ExecutePacketRunVerificationMutation`, backend `inputDefaults`, and CSS layout tokens.
- Produces: structured GraphQL errors preserved in UI state, derived initial readiness with no duplicate read, an executable first command surface, backend-provided command defaults, and mobile topbar layout that sizes to content.

- [x] **Step 1: Add failing GraphQL error preservation tests**

Update `fetchGraphQL.test.ts` so GraphQL errors reject with an error that exposes the original `GraphQLResponse` at `error.source`, including `extensions.code`.

- [x] **Step 2: Preserve structured GraphQL response errors**

Implement an exported `GraphQLResponseError extends Error` in `fetchGraphQL.ts` that carries `source: GraphQLResponse`, `status`, and `requestName`. Throw it for GraphQL errors before returning to Relay.

- [x] **Step 3: Add failing initial-readiness test**

Update `route.test.tsx` so initial selection renders `Prepare packet context` and asserts no `OperatorPacketReadinessQuery` was issued before an explicit validation/command action.

- [x] **Step 4: Derive initial readiness locally**

Change `useOperatorWorkflow` so selected rows produce a derived `PacketReadiness` object from backend-provided command defaults and affordances. Keep network packet-readiness validation behind an explicit action or stale refresh hook, not the initial selection effect.

- [x] **Step 5: Add failing command execution test**

Add a route test where an enabled command button submits `ExecutePacketRunVerificationMutation`, shows a submitting state, and then refreshes or invalidates run/workflow state.

- [x] **Step 6: Implement executable narrow command surface**

Expose a first command action for derived ready packet context. Use Relay `commitMutation` with `ExecutePacketRunVerificationMutation`, `updateOperatorWorkflowAfterVerification`, and a deterministic local input built from backend defaults plus current operator input values. Keep disabled/hidden/redacted affordances non-clickable.

- [x] **Step 7: Consume backend command defaults**

Update Relay fragments/types and `derived.ts` to prefer `commandAffordance.inputDefaults` for packet fields and target ids. Keep `graphLinks` as display context, not as the source of command input truth.

- [x] **Step 8: Fix mobile topbar row sizing**

Add a mobile media rule setting `.console-frame { grid-template-rows: auto minmax(0, 1fr); }`.

- [x] **Step 9: Verify frontend slice**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets run relay
nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets run typecheck
nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets run test
```

Expected: generated Relay artifacts are updated, TypeScript passes, and Vitest passes.

- [x] **Step 10: Commit**

Run:

```bash
git add assets
git commit -m "fix: wire operator command workflow"
```

Expected: fourth commit contains frontend behavior/layout fixes and generated Relay artifacts.

### Task 5: Final Repository Verification

**Files:**
- Inspect: full branch diff.

**Interfaces:**
- Consumes: all branch changes.
- Produces: final verified branch state.

- [x] **Step 1: Run full verification gates**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --all --strict
nix --extra-experimental-features 'nix-command flakes' develop --command mix hex.audit
nix --extra-experimental-features 'nix-command flakes' develop --command mix test
nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets run verify
nix --extra-experimental-features 'nix-command flakes' develop --command git diff --check
```

Expected: all commands exit 0.

- [x] **Step 2: Review issue coverage**

For each issue heading in `code-review-issues-2026-07-09.md`, record whether it was fixed in code, fixed by dependency update, verified as obsolete, or intentionally deferred with a reason.

- [x] **Step 3: Commit final notes if needed**

If the review markdown receives status updates, run:

```bash
git add code-review-issues-2026-07-09.md
git commit -m "docs: record review issue resolutions"
```

Expected: final documentation commit only if status notes were changed.
