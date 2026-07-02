# Current Product Path Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Office Graph easier to navigate by archiving completed OpenSpec work, deleting old hand-written compatibility routes, replacing inflated wording, and splitting only backend files that are still hard to follow after old paths are gone.

**Architecture:** The current product path is Phoenix `/operator` serving the React app, React reading `/graphql`, and GraphQL delegating to backend commands and reads. AshGraphql and AshJsonApi must be real API providers for resource reads, not libraries mounted beside hand-written duplicates. Generated AshJsonApi remains mounted at `/api/v1`; hand-written demo JSON and `Compatibility` GraphQL mutations are old paths unless a non-test caller proves otherwise during the caller audit below.

**Tech Stack:** Elixir, Phoenix, Absinthe, Ash/AshJsonApi, React, Vite, Vitest, OpenSpec, and the project Nix flake.

---

## Ground Rules

- Do not create a new OpenSpec change for this cleanup.
- Do not preserve an old route, file layout, response shape, or test only because it existed before.
- A current caller means production code, generated API routing, a local development workflow, data-safety logic, or an external contract named in current docs. A test file by itself does not count.
- Keep generated `/api/v1` JSON API behavior unless a task explicitly proves a generated route is dead.
- Treat "we use AshGraphql/AshJsonApi" as false unless tests prove the current API uses generated Ash fields or routes for resource-shaped reads.
- Keep domain behavior: manual intake, proposed change application, packet preparation, run start, observation recording, evidence acceptance, verification outcome reads, idempotency, replay conflict handling, authorization checks, and query-count protections.
- Commit after every task.
- Run project commands through:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command <command>
```

## File Map

Archive:

- `openspec/changes/rebuild-operator-frontend-foundation/`
- `openspec/changes/reduce-operator-query-load/`

Primary docs/specs to simplify:

- `openspec/project.md`
- `openspec/research/product-frontend-platform.md`
- `openspec/specs/unreleased-development-policy/spec.md`
- `openspec/specs/operator-console/spec.md`
- `openspec/specs/operator-workflow/spec.md`
- `openspec/specs/frontend-architecture/spec.md`
- `openspec/specs/ui-projection-contracts/spec.md`
- `openspec/specs/ash-api-surface/spec.md`
- `openspec/specs/backend-architecture/spec.md`
- `openspec/specs/architecture-stabilization/spec.md`
- `openspec/specs/product-concept-simplification/spec.md`
- `openspec/specs/backend-model-ownership/architecture-exceptions.md`

Old route/code candidates:

- `lib/office_graph_web/router.ex`
- `lib/office_graph_web/graphql/schema.ex`
- `lib/office_graph_web/graphql/compatibility/mutations.ex`
- `lib/office_graph_web/graphql/compatibility/types.ex`
- `lib/office_graph_web/json_api/compatibility/controller.ex`
- `lib/office_graph_web/json_api/compatibility/serializer.ex`
- `lib/office_graph_web/json_api/operator_workflow/controller.ex`
- `lib/office_graph_web/json_api/operator_workflow/serializer.ex`
- `lib/office_graph_web/json_api/packet_run_verification/controller.ex`
- `lib/office_graph_web/json_api/packet_run_verification/serializer.ex`
- `lib/office_graph/api_support.ex`

Tests that will change:

- `assets/src/operator/architecture.test.ts`
- `assets/src/operator/workflowQueries.test.ts`
- `test/office_graph_web/operator_workflow_api_test.exs`
- `test/office_graph_web/api_smoke_test.exs` (deleted)
- `test/office_graph_web/packet_run_verification_api_test.exs`
- `test/office_graph_web/generated_api_read_test.exs`
- `test/office_graph/architecture/ash_conformance_test.exs`
- `test/office_graph/integrations/concurrency_test.exs`
- `test/office_graph/projections/operator_workflow_test.exs`
- `test/office_graph/packet_run_verification_test.exs`

Backend files to split only after old routes are gone:

- `lib/office_graph/api_support.ex`
- `lib/office_graph/runs.ex`
- `lib/office_graph/verification.ex`
- `lib/office_graph/work_packets.ex`

## Task 1: Archive Completed OpenSpec Work

**Files:**

- Move: `openspec/changes/rebuild-operator-frontend-foundation/` to `openspec/changes/archive/2026-07-02-rebuild-operator-frontend-foundation/`
- Move: `openspec/changes/reduce-operator-query-load/` to `openspec/changes/archive/2026-07-02-reduce-operator-query-load/`

- [ ] **Step 1: Confirm both changes are complete**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command openspec status --change rebuild-operator-frontend-foundation --json
nix --extra-experimental-features 'nix-command flakes' develop --command openspec status --change reduce-operator-query-load --json
```

Expected: both changes report complete artifacts and all tasks are checked.

- [ ] **Step 2: Confirm current specs already contain the accepted decisions**

Run:

```bash
rg -n "GraphQL.*product|old JSON adapter|current product direction|current caller|unreleased" openspec/project.md openspec/specs openspec/changes/rebuild-operator-frontend-foundation openspec/changes/reduce-operator-query-load
```

Expected: current `openspec/specs/**` already says GraphQL is the operator frontend path and old JSON adapter compatibility is not required.

- [ ] **Step 3: Move the completed change folders**

Run:

```bash
mkdir -p openspec/changes/archive
mv openspec/changes/rebuild-operator-frontend-foundation openspec/changes/archive/2026-07-02-rebuild-operator-frontend-foundation
mv openspec/changes/reduce-operator-query-load openspec/changes/archive/2026-07-02-reduce-operator-query-load
```

Expected: `openspec/changes/` has no active `rebuild-operator-frontend-foundation` or `reduce-operator-query-load` directory.

- [ ] **Step 4: Validate OpenSpec state**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command openspec list --json
nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --specs --strict
nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --changes --strict
```

Expected: no active completed changes remain; strict spec validation passes; strict change validation passes or reports no active changes.

- [ ] **Step 5: Commit**

Run:

```bash
git add openspec/changes
git commit -m "Archive completed operator cleanup changes"
```

## Task 2: Replace Inflated Wording In Current Docs

**Files:**

- Modify: `openspec/project.md`
- Modify: `openspec/research/product-frontend-platform.md`
- Modify: `openspec/specs/unreleased-development-policy/spec.md`
- Modify: `openspec/specs/operator-console/spec.md`
- Modify: `openspec/specs/operator-workflow/spec.md`
- Modify: `openspec/specs/frontend-architecture/spec.md`
- Modify: `openspec/specs/ui-projection-contracts/spec.md`
- Modify: `openspec/specs/ash-api-surface/spec.md`
- Modify: `openspec/specs/backend-architecture/spec.md`
- Modify: `openspec/specs/architecture-stabilization/spec.md`
- Modify: `openspec/specs/product-concept-simplification/spec.md`
- Modify: `openspec/specs/backend-model-ownership/architecture-exceptions.md`

- [ ] **Step 1: Find wording to replace**

Run:

```bash
rg -n "API surface|surface|projection client|projection-capable|affordance|compatibility path|compatibility bridge|migration bridge|adapter seam|transport shape|resource surface|legacy|backwards compatibility|view-model|operator-workflow frontend module" openspec/project.md openspec/research openspec/specs
```

Expected: every match is either a precise technical term that should remain or a phrase to simplify.

- [ ] **Step 2: Apply this replacement table**

Use these replacements unless the sentence is specifically about graph projection reads:

| Old wording | New wording |
| --- | --- |
| API surface | API |
| product surface | page or UI |
| operator surface | operator page |
| projection client | data hook or query helper |
| projection-capable | readable through GraphQL |
| affordance | allowed action, button, or state |
| compatibility path | old path |
| compatibility bridge | old bridge |
| migration bridge | old bridge |
| adapter seam | adapter code |
| transport shape | response shape |
| resource surface | API route or Ash resource |
| legacy | old |
| backwards compatibility | compatibility |
| view-model | UI data |
| operator-workflow frontend module | operator frontend code |

- [ ] **Step 3: Keep these words only where they are exact**

Keep `projection` only when the text means an authorization-filtered graph/workflow read assembled by `OfficeGraph.Projections`.

Keep `Boundary` only when the text means the Elixir Boundary dependency checker.

Keep `compatibility` only for real external protocol or vendor compatibility, such as SAML, SCIM, Okta, Entra, or Keycloak compatibility.

- [ ] **Step 4: Validate docs**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --specs --strict
nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --changes --strict
git diff --check
```

Expected: strict validation passes; whitespace check passes.

- [ ] **Step 5: Commit**

Run:

```bash
git add openspec/project.md openspec/research openspec/specs
git commit -m "Simplify current project wording"
```

## Task 3: Prove AshGraphql And AshJsonApi Are The Default Resource APIs

**Files:**

- Modify: `lib/office_graph_web/graphql/schema.ex`
- Modify: `lib/office_graph_web/json_api/router.ex`
- Modify: `lib/office_graph_web/router.ex`
- Modify: `test/office_graph_web/generated_api_read_test.exs`
- Modify: `test/office_graph/architecture/ash_conformance_test.exs`
- Modify: `openspec/specs/ash-api-surface/spec.md`
- Check: `lib/office_graph/**/domain.ex`
- Check: `lib/office_graph/**/*.ex` files with `graphql do` and `json_api do`

- [ ] **Step 1: Inventory generated Ash API coverage**

Run:

```bash
rg -n "use AshGraphql|use AshJsonApi|extensions: \\[AshGraphql\\.Resource, AshJsonApi\\.Resource\\]|graphql do|json_api do|AshJsonApi\\.Router|use AshGraphql" lib/office_graph lib/office_graph_web
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph_web/generated_api_read_test.exs
```

Expected: `OfficeGraphWeb.GraphQL.Schema` uses `AshGraphql` with the WorkGraph, WorkPackets, and Runs domains; `OfficeGraphWeb.JsonApi.Router` uses `AshJsonApi.Router`; generated read tests prove selected GraphQL fields and `/api/v1` JSON routes work.

- [ ] **Step 2: Classify every current API as generated, custom command, custom mixed read, or old path**

Use this classification:

| API | Classification | Rule |
| --- | --- | --- |
| `listSignals`, `listWorkPackets`, `listWorkRuns` | generated AshGraphql read | Keep and expand when resource-shaped reads are needed. |
| `/api/v1/signals`, `/api/v1/work-packets`, `/api/v1/work-runs` | generated AshJsonApi read | Keep as customer/integration JSON API. |
| `operator_inbox`, `operator_workflow_item`, `operator_packet_readiness`, `operator_run_state`, `operator_verification_outcome` | custom GraphQL mixed read | Keep only because these assemble current operator UI data across resources and policy checks. Do not keep a manual JSON mirror. |
| `executePacketRunVerification` | custom GraphQL command | Keep only as a thin multi-domain command entrypoint. It must call `OfficeGraph.PacketRunVerification.execute/2`. |
| `/api/operator-workflow/*` | old manual JSON mirror | Delete unless a non-test caller is found. |
| GraphQL `Compatibility` mutations | old walking-skeleton API | Delete unless a non-test caller is found. |
| `/api/manual-intake`, `/api/proposed-changes/apply`, `/api/verification/complete` | old walking-skeleton JSON API | Delete unless a non-test caller is found. |
| `/api/packet-run-verification/execute` | undecided custom JSON command | Decide by caller audit in the packet-run task. |

- [ ] **Step 3: Strengthen generated API tests**

Update `test/office_graph_web/generated_api_read_test.exs` so it proves both libraries are used, not just mounted:

- GraphQL: query at least `listSignals`, `listWorkPackets`, and `listWorkRuns` through `/graphql`.
- JSON API: GET at least `/api/v1/signals`, `/api/v1/work-packets`, and `/api/v1/work-runs`.
- Authorization: with local owner bootstrap disabled, GraphQL returns a structured forbidden error and JSON API returns 403.
- Writes: generated JSON API does not expose lifecycle writes for work runs.

Do not add generated creates for packet/run/verification lifecycle records in this task.

- [ ] **Step 4: Add architecture checks for generated API usage**

Update `test/office_graph/architecture/ash_conformance_test.exs` so it fails when:

- a resource-shaped read is added as a manual Absinthe field or Phoenix JSON route while an AshGraphql/AshJsonApi declaration exists;
- generated `/api/v1` routes disappear for the selected read resources;
- `OfficeGraphWeb.JsonApi.Router` stops using `AshJsonApi.Router`;
- `OfficeGraphWeb.GraphQL.Schema` stops using `AshGraphql`.

Keep custom mixed reads and custom commands allowed only when they are named in the manual API ledger or in the task classification above.

- [ ] **Step 5: Update the API spec language**

In `openspec/specs/ash-api-surface/spec.md`, add a requirement that mounting AshGraphql/AshJsonApi is not enough. Current resource-shaped reads must have tests proving generated fields or routes are exercised. Custom GraphQL/Phoenix code must be limited to mixed reads or commands that generated Ash APIs cannot express safely.

- [ ] **Step 6: Verify**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph_web/generated_api_read_test.exs test/office_graph/architecture/ash_conformance_test.exs
nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --specs --strict
git diff --check
```

Expected: tests prove real generated AshGraphql/AshJsonApi usage and still allow named custom GraphQL reads/commands.

- [ ] **Step 7: Commit**

Run:

```bash
git add lib/office_graph_web/graphql/schema.ex lib/office_graph_web/json_api/router.ex lib/office_graph_web/router.ex test/office_graph_web/generated_api_read_test.exs test/office_graph/architecture/ash_conformance_test.exs openspec/specs/ash-api-surface/spec.md
git commit -m "Prove generated Ash API usage"
```

## Task 4: Lock The Frontend To GraphQL

**Files:**

- Modify: `assets/src/operator/architecture.test.ts`
- Modify if needed: `assets/src/operator/workflowQueries.test.ts`
- Modify if needed: `assets/src/operator/workflowQueries.ts`

- [ ] **Step 1: Add a failing frontend architecture test**

Extend `assets/src/operator/architecture.test.ts` so production files under `assets/src/App.tsx`, `assets/src/main.tsx`, and `assets/src/operator/**` fail when they contain:

```text
/api/operator-workflow
operator-workflow/api
./operator-workflow/api
```

Expected failure before cleanup only if an old import or hard-coded route is present.

- [ ] **Step 2: Keep the GraphQL query tests focused on GraphQL**

In `assets/src/operator/workflowQueries.test.ts`, make sure tests exercise the `GraphQLFetcher` contract and do not mention `/api/operator-workflow`.

- [ ] **Step 3: Run frontend verification**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command npm run verify
```

Expected: Vitest and TypeScript checks pass.

- [ ] **Step 4: Commit**

Run:

```bash
git add assets/src/operator/architecture.test.ts assets/src/operator/workflowQueries.test.ts assets/src/operator/workflowQueries.ts
git commit -m "Lock operator frontend to GraphQL"
```

## Task 5: Remove Manual Operator Workflow JSON Routes

**Files:**

- Modify: `lib/office_graph_web/router.ex`
- Delete: `lib/office_graph_web/json_api/operator_workflow/controller.ex`
- Delete: `lib/office_graph_web/json_api/operator_workflow/serializer.ex`
- Modify: `test/office_graph_web/operator_workflow_api_test.exs`
- Modify: `test/office_graph/architecture/ash_conformance_test.exs`
- Keep: `lib/office_graph_web/graphql/operator_workflow/queries.ex`
- Keep: `lib/office_graph_web/graphql/operator_workflow/types.ex`
- Keep: `test/office_graph/projections/operator_workflow_test.exs`

- [ ] **Step 1: Prove the old JSON routes have no production caller**

Run:

```bash
rg -n "/api/operator-workflow|JsonApi\\.OperatorWorkflow|operator_workflow_api_test" lib assets test openspec --glob '!openspec/changes/archive/**'
```

Expected: production callers are limited to `router.ex` and `lib/office_graph_web/json_api/operator_workflow/**`; tests and docs may mention old routes.

- [ ] **Step 2: Rewrite route tests around current behavior**

Replace `test/office_graph_web/operator_workflow_api_test.exs` with GraphQL or domain-read coverage:

- Use GraphQL tests when checking `/operator` page data contract.
- Use `test/office_graph/projections/operator_workflow_test.exs` when checking backend read behavior, authorization filtering, readiness, run state, verification outcome, and query count.
- Do not keep tests that only assert old JSON response envelopes.

- [ ] **Step 3: Delete the old route code**

Remove these routes from `lib/office_graph_web/router.ex`:

```elixir
get "/operator-workflow/inbox", JsonApi.OperatorWorkflow.Controller, :inbox
get "/operator-workflow/items/:id", JsonApi.OperatorWorkflow.Controller, :item
post "/operator-workflow/packet-readiness", JsonApi.OperatorWorkflow.Controller, :packet_readiness
get "/operator-workflow/runs/:id", JsonApi.OperatorWorkflow.Controller, :run_state
get "/operator-workflow/runs/:id/verification-outcome", JsonApi.OperatorWorkflow.Controller, :verification_outcome
```

Delete:

```text
lib/office_graph_web/json_api/operator_workflow/controller.ex
lib/office_graph_web/json_api/operator_workflow/serializer.ex
```

- [ ] **Step 4: Update architecture tests**

In `test/office_graph/architecture/ash_conformance_test.exs`, remove `lib/office_graph_web/json_api/operator_workflow/controller.ex` and `lib/office_graph_web/json_api/operator_workflow/serializer.ex` from any required-file list.

Add or keep an assertion that production frontend code does not call `/api/operator-workflow`.

- [ ] **Step 5: Verify**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/projections/operator_workflow_test.exs test/office_graph/architecture/ash_conformance_test.exs
nix --extra-experimental-features 'nix-command flakes' develop --command npm run verify
git diff --check
```

Expected: operator backend reads and frontend checks pass; no stale old-route references remain outside archived docs.

- [ ] **Step 6: Commit**

Run:

```bash
git add lib/office_graph_web/router.ex lib/office_graph_web/json_api/operator_workflow test/office_graph_web/operator_workflow_api_test.exs test/office_graph/architecture/ash_conformance_test.exs assets/src/operator
git commit -m "Remove old operator JSON routes"
```

## Task 6: Remove Compatibility Mutations And Manual Walking-Skeleton JSON

**Files:**

- Modify: `lib/office_graph_web/router.ex`
- Modify: `lib/office_graph_web/graphql/schema.ex`
- Delete: `lib/office_graph_web/graphql/compatibility/mutations.ex`
- Delete: `lib/office_graph_web/graphql/compatibility/types.ex`
- Delete: `lib/office_graph_web/json_api/compatibility/controller.ex`
- Delete: `lib/office_graph_web/json_api/compatibility/serializer.ex`
- Delete: `test/office_graph_web/api_smoke_test.exs`
- Modify: `test/office_graph/architecture/ash_conformance_test.exs`
- Keep or create focused domain tests under `test/office_graph/**`

- [ ] **Step 1: Prove compatibility endpoints have no production caller**

Run:

```bash
rg -n "submit_manual_intake|apply_proposed_changes|complete_verification|/api/manual-intake|/api/proposed-changes/apply|/api/verification/complete|GraphQL\\.Compatibility|JsonApi\\.Compatibility" lib assets test openspec --glob '!openspec/changes/archive/**'
```

Expected: route/module references are limited to schema/router/controller files, tests, specs, and architecture checks.

- [ ] **Step 2: Preserve behavior in domain tests**

Before deleting routes, make sure these behaviors are covered outside old route tests:

- `Integrations.submit_manual_intake/3` creates a normalized event and proposed changes.
- `ProposedChanges.apply_all/3` applies proposed changes and rejects invalid id sets.
- `Verification.complete_with_evidence/4` creates evidence and verification results.
- Authorization and idempotency behavior remain covered by existing domain tests.

Use existing tests when they already cover the behavior. Delete `test/office_graph_web/api_smoke_test.exs` after confirming domain behavior is covered by focused domain tests rather than the old HTTP envelope.

- [ ] **Step 3: Delete compatibility GraphQL imports**

Remove these imports from `lib/office_graph_web/graphql/schema.ex`:

```elixir
import_types(OfficeGraphWeb.GraphQL.Compatibility.Types)
import_types(OfficeGraphWeb.GraphQL.Compatibility.Mutations)
```

Remove this mutation import:

```elixir
import_fields(:compatibility_mutations)
```

Delete:

```text
lib/office_graph_web/graphql/compatibility/mutations.ex
lib/office_graph_web/graphql/compatibility/types.ex
```

- [ ] **Step 4: Delete compatibility JSON routes**

Remove these routes from `lib/office_graph_web/router.ex`:

```elixir
post "/manual-intake", JsonApi.Compatibility.Controller, :manual_intake
post "/proposed-changes/apply", JsonApi.Compatibility.Controller, :apply_proposed_changes
post "/verification/complete", JsonApi.Compatibility.Controller, :complete_verification
```

Delete:

```text
lib/office_graph_web/json_api/compatibility/controller.ex
lib/office_graph_web/json_api/compatibility/serializer.ex
```

- [ ] **Step 5: Update architecture tests**

In `test/office_graph/architecture/ash_conformance_test.exs`:

- Remove `lib/office_graph_web/graphql/compatibility/types.ex` from required GraphQL files.
- Remove `lib/office_graph_web/graphql/compatibility/mutations.ex` from required GraphQL files.
- Remove `lib/office_graph_web/json_api/compatibility/controller.ex` from required JSON files.
- Remove `lib/office_graph_web/json_api/compatibility/serializer.ex` from required JSON files.
- Replace wording that says those modules are required with wording that says old compatibility modules must not exist.

- [ ] **Step 6: Verify**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/architecture/ash_conformance_test.exs test/office_graph/integrations test/office_graph/proposed_changes test/office_graph/work_graph test/office_graph/verification
nix --extra-experimental-features 'nix-command flakes' develop --command mix compile --warnings-as-errors
git diff --check
```

Expected: domain tests pass without old compatibility HTTP or GraphQL mutation modules.

- [ ] **Step 7: Commit**

Run:

```bash
git add lib/office_graph_web/router.ex lib/office_graph_web/graphql lib/office_graph_web/json_api test/office_graph/architecture/ash_conformance_test.exs test/office_graph
git add -u test/office_graph_web/api_smoke_test.exs
git commit -m "Remove old compatibility routes"
```

## Task 7: Decide And Then Remove Or Keep The Packet-Run JSON Command

**Files:**

- Modify if removing: `lib/office_graph_web/router.ex`
- Delete if removing: `lib/office_graph_web/json_api/packet_run_verification/controller.ex`
- Delete if removing: `lib/office_graph_web/json_api/packet_run_verification/serializer.ex`
- Modify if removing: `test/office_graph_web/packet_run_verification_api_test.exs`
- Modify if keeping: `openspec/specs/ash-api-surface/spec.md`
- Modify: `test/office_graph/architecture/ash_conformance_test.exs`
- Keep: `lib/office_graph_web/graphql/packet_run_verification/mutations.ex`
- Keep: `lib/office_graph/packet_run_verification.ex`
- Keep: `test/office_graph/packet_run_verification_test.exs`

- [ ] **Step 1: Run the caller audit**

Run:

```bash
rg -n "packet-run-verification/execute|JsonApi\\.PacketRunVerification|execute_packet_run_verification|packet_run_verification_api_test" lib assets test openspec --glob '!openspec/changes/archive/**'
```

Expected: this shows whether `/api/packet-run-verification/execute` has any non-test caller.

- [ ] **Step 2: Remove the JSON command when only tests/docs call it**

If the caller audit finds only tests/docs plus router/controller/serializer files, remove:

```elixir
post "/packet-run-verification/execute", JsonApi.PacketRunVerification.Controller, :execute
```

Delete:

```text
lib/office_graph_web/json_api/packet_run_verification/controller.ex
lib/office_graph_web/json_api/packet_run_verification/serializer.ex
```

Move behavior assertions from `test/office_graph_web/packet_run_verification_api_test.exs` into:

```text
test/office_graph/packet_run_verification_test.exs
test/office_graph/integrations/concurrency_test.exs
```

Keep one GraphQL test for `executePacketRunVerification` if the GraphQL mutation currently has HTTP-level coverage.

- [ ] **Step 3: Keep the JSON command only with a named reason**

If the caller audit finds a current non-test caller or current integration contract, keep the JSON command and update `openspec/specs/ash-api-surface/spec.md` with the named reason and retirement rule:

```text
`/api/packet-run-verification/execute` remains a current JSON command because <caller or contract>. It is not a frontend fallback and must not be used by `/operator`.
```

- [ ] **Step 4: Verify**

Run the relevant command set.

If removed:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/packet_run_verification_test.exs test/office_graph/integrations/concurrency_test.exs test/office_graph/architecture/ash_conformance_test.exs
```

If kept:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph_web/packet_run_verification_api_test.exs test/office_graph/packet_run_verification_test.exs test/office_graph/architecture/ash_conformance_test.exs
```

Always run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix compile --warnings-as-errors
git diff --check
```

- [ ] **Step 5: Commit**

Run:

```bash
git add lib/office_graph_web/router.ex lib/office_graph_web/json_api/packet_run_verification test/office_graph_web/packet_run_verification_api_test.exs test/office_graph/packet_run_verification_test.exs test/office_graph/integrations/concurrency_test.exs test/office_graph/architecture/ash_conformance_test.exs openspec/specs/ash-api-surface/spec.md
git commit -m "Set packet-run JSON command status"
```

## Task 8: Shrink Or Remove `OfficeGraph.ApiSupport`

**Files:**

- Modify: `lib/office_graph/api_support.ex`
- Modify: `lib/office_graph_web/local_api_owner_plug.ex`
- Modify: `lib/office_graph_web/graphql/operator_workflow/queries.ex`
- Modify: `lib/office_graph_web/graphql/packet_run_verification/mutations.ex`
- Modify: `test/office_graph/boundary_layout_test.exs`
- Modify: `test/office_graph/architecture/ash_conformance_test.exs`

- [ ] **Step 1: Recheck remaining callers**

Run:

```bash
rg -n "ApiSupport\\.|alias OfficeGraph\\.ApiSupport|OfficeGraph\\.ApiSupport" lib test
```

Expected after Tasks 4-6: remaining callers are GraphQL operator reads, GraphQL packet-run command if kept through `ApiSupport`, `LocalApiOwnerPlug`, architecture tests, and maybe concurrency tests.

- [ ] **Step 2: Move request-session helper to the web layer**

Create or update a web helper only if it removes `ApiSupport.with_request_session_context/2` cleanly:

```text
lib/office_graph_web/request_session.ex
```

Move the actor/session-context wrapping logic there. GraphQL query modules should call the web helper, then call backend reads directly.

- [ ] **Step 3: Move packet-run input parsing out of `ApiSupport`**

If `ApiSupport.execute_packet_run_verification/1` is still used only to parse GraphQL or JSON input, move the parsing into the GraphQL packet-run module or a small web input module:

```text
lib/office_graph_web/graphql/packet_run_verification/input.ex
```

Then call:

```elixir
OfficeGraph.PacketRunVerification.execute(session_context, input)
```

- [ ] **Step 4: Delete dead `ApiSupport` functions**

Delete these functions if Tasks 4-6 removed their routes:

```elixir
submit_manual_intake/1
apply_proposed_changes/1
complete_verification/1
read_operator_inbox/1
read_operator_workflow_item/1
read_operator_packet_readiness/1
read_operator_run_state/1
read_operator_verification_outcome/1
execute_packet_run_verification/1
with_request_session_context/2
```

Keep only `bootstrap_local_api_owner/0` if `LocalApiOwnerPlug` still needs it. If that is the only remaining function, rename the module in a follow-up task to a clearer owner such as `OfficeGraph.LocalOwnerBootstrap`.

- [ ] **Step 5: Verify**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/architecture/ash_conformance_test.exs test/office_graph/boundary_layout_test.exs test/office_graph/projections/operator_workflow_test.exs test/office_graph/packet_run_verification_test.exs
nix --extra-experimental-features 'nix-command flakes' develop --command mix compile --warnings-as-errors
git diff --check
```

Expected: API support no longer owns workflow behavior or old route parsing.

- [ ] **Step 6: Commit**

Run:

```bash
git add lib/office_graph/api_support.ex lib/office_graph_web test/office_graph
git commit -m "Shrink API support to current callers"
```

## Task 9: Split Large Backend Files Only Where The Split Is Obvious

**Files:**

- Modify or split: `lib/office_graph/runs.ex`
- Modify or split: `lib/office_graph/verification.ex`
- Modify or split: `lib/office_graph/work_packets.ex`
- Modify tests under matching directories.

- [ ] **Step 1: Measure what is still hard to navigate**

Run:

```bash
wc -l lib/office_graph/runs.ex lib/office_graph/verification.ex lib/office_graph/work_packets.ex
rg -n "^  def |^  defp " lib/office_graph/runs.ex lib/office_graph/verification.ex lib/office_graph/work_packets.ex
```

Expected: each file's remaining public and private groups are visible.

- [ ] **Step 2: Split by current workflow, not architecture theme**

Use these split targets only if the functions already group this way:

For `lib/office_graph/runs.ex`:

```text
lib/office_graph/runs/start_run.ex
lib/office_graph/runs/record_observation.ex
lib/office_graph/runs/apply_verification_result.ex
```

For `lib/office_graph/verification.ex`:

```text
lib/office_graph/verification/evidence_candidates.ex
lib/office_graph/verification/accept_evidence.ex
lib/office_graph/verification/read_results.ex
```

For `lib/office_graph/work_packets.ex`:

```text
lib/office_graph/work_packets/create_packet.ex
lib/office_graph/work_packets/read_packet.ex
```

Do not add a new generic service layer, facade, coordinator, or adapter.

- [ ] **Step 3: Keep public calls stable inside the repo**

The public call sites should still read plainly:

```elixir
OfficeGraph.Runs.start_run(...)
OfficeGraph.Runs.record_observation(...)
OfficeGraph.Verification.create_evidence_candidate(...)
OfficeGraph.Verification.accept_evidence_candidate(...)
OfficeGraph.WorkPackets.create_packet(...)
```

Internal helper modules can be private implementation details called by those public modules.

- [ ] **Step 4: Verify after each file split**

After splitting `runs.ex`, run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/runs test/office_graph/packet_run_verification_test.exs
```

After splitting `verification.ex`, run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/verification test/office_graph/packet_run_verification_test.exs
```

After splitting `work_packets.ex`, run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/work_packets test/office_graph/packet_run_verification_test.exs
```

Always run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix compile --warnings-as-errors
git diff --check
```

- [ ] **Step 5: Commit after each split**

Run one commit per split:

```bash
git add lib/office_graph/runs.ex lib/office_graph/runs test/office_graph/runs test/office_graph/packet_run_verification_test.exs
git commit -m "Split run workflow helpers"

git add lib/office_graph/verification.ex lib/office_graph/verification test/office_graph/verification test/office_graph/packet_run_verification_test.exs
git commit -m "Split verification workflow helpers"

git add lib/office_graph/work_packets.ex lib/office_graph/work_packets test/office_graph/work_packets test/office_graph/packet_run_verification_test.exs
git commit -m "Split work packet helpers"
```

## Task 10: Final Repo-Wide Check

**Files:**

- Check all changed files.

- [ ] **Step 1: Search for old-path leftovers**

Run:

```bash
rg -n "/api/operator-workflow|JsonApi\\.OperatorWorkflow|GraphQL\\.Compatibility|JsonApi\\.Compatibility|operator-workflow/api|compatibility bridge|compatibility path|adapter seam|backwards compatibility|API surface|projection client" lib assets test openspec/project.md openspec/research openspec/specs --glob '!openspec/changes/archive/**'
```

Expected: no old operator JSON route or compatibility module references remain outside archived docs; any remaining `compatibility` match is for vendor/protocol compatibility or a named current caller.

- [ ] **Step 2: Run full verification set**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --specs --strict
nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --changes --strict
nix --extra-experimental-features 'nix-command flakes' develop --command npm run verify
nix --extra-experimental-features 'nix-command flakes' develop --command mix test
nix --extra-experimental-features 'nix-command flakes' develop --command mix compile --warnings-as-errors
git diff --check
```

Expected: all commands pass.

- [ ] **Step 3: Commit final cleanup if needed**

Run only if Task 10 produced additional cleanup edits:

```bash
git add .
git commit -m "Finish current path cleanup"
```

## Execution Order

1. Task 1 first, because stale completed changes are confusing every later search.
2. Task 2 second, because docs should stop telling workers to preserve old shapes.
3. Task 3 third, because it proves AshGraphql/AshJsonApi are real generated API paths before deleting manual duplicates.
4. Task 4 next, because it protects the current frontend path before backend route deletion.
5. Tasks 5-7 next, because old routes should be removed before backend file splitting.
6. Task 8 next, because `ApiSupport` shrinks naturally after old routes disappear.
7. Task 9 last, because splitting large backend files is safer after dead code is gone.
8. Task 10 at the end.

## Self-Review

- Spec coverage: the plan covers completed OpenSpec cleanup, current product path, real AshGraphql/AshJsonApi usage, old demo compatibility removal, wording cleanup, backend navigation, and verification.
- Placeholder scan: there are no placeholder markers or unspecified test steps.
- Type consistency: the plan uses the current module names from the repo and separates generated `/api/v1` from old hand-written `/api/*` routes.
