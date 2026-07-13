# Office Graph Project Quality Remediation Plan

> Execute from `/Users/admin/.codex/worktrees/8f37/office_graph` on `codex/harden-project-quality`. Enter every project command through `nix --extra-experimental-features 'nix-command flakes' develop --command ...`. Follow `openspec/changes/harden-project-quality/{proposal,design,tasks}.md`; use TDD for every behavior change and commit each task checkpoint.

**Goal:** Repair the confirmed whole-project correctness and quality defects, preserve a permanent audit record, and publish a ready PR stacked on open PR #21.

**Architecture:** Keep transports thin over shared safe command semantics, keep transactional orchestration cohesive while extracting pure policy/reduction seams, make backend projections own valid command choices, and make one non-mutating Nix-backed script the repository gate. Do not implement the three separately designed durable-contract follow-ups listed in the audit.

**Toolchain:** Erlang/OTP 29, Elixir 1.20, Phoenix/Ash/Ecto/PostgreSQL/Oban, React 19/React Router/Relay/TypeScript/Vitest, OpenSpec 1.4.1, Nix flakes, Docker Compose.

## Global Constraints

- Do not introduce Tailwind, shadcn, LiveView, or moving Nix package aliases.
- Preserve GraphQL and JSON envelope ownership while sharing parsing/classification semantics.
- Preserve server-owned request-scoped trusted projection contexts.
- Behavior regressions must be observed failing before production fixes.
- Verification/check commands must not intentionally mutate tracked files.
- Generated Relay artifacts may change only through schema/compiler commands.
- Do not rewrite coherent historical migrations; the targeted unsafe `down/0` is the exception.
- Keep unrelated/user changes intact and do not use destructive Git commands.

## Task 1: Canonical Gate, Isolation, Runtime Safety, And Spec Hygiene

**Files:** `mix.exs`, `bin/verify`, `bin/verify-backend`, `compose.yaml`, `config/test.exs`, `config/runtime.exs`, `.github/workflows/verify.yml`, `README.md`, `mix.lock`, `assets/package.json`, `pnpm-lock.yaml`, `openspec/specs/*/spec.md`, `openspec/project-plan.md`, focused new tests/scripts.

1. Reproduce Mix one-shot alias semantics with a failing test outside `ash_conformance_test.exs` or an isolated alias test; capture the expected false pass before the fix.
2. Make `verify` run one complete test alias, replace mutating unlock with `--check-unused`, add strict OpenSpec/purpose/advisory/build checks, and make precommit delegate to it.
3. Create canonical `bin/verify`: derive stable per-worktree Compose project, port, and `MIX_TEST_PARTITION`, accept explicit overrides, start/wait for Postgres unless skipped, then invoke `mix verify`.
4. Parameterize Compose and test config. Ensure DDL/global-trigger tests remain serial within their isolated database.
5. Add CI invoking the same script inside the Nix flake; update README to document only the canonical gate plus focused developer commands.
6. Add a runtime-config regression for unset/false/0/true/1 and fix `PHX_SERVER` exact parsing.
7. Run Hex/frontend advisory checks, minimally update vulnerable lock entries, and confirm clean results.
8. Replace all generated spec-purpose placeholders with concise requirement-derived purposes; add a deterministic hygiene checker and mark the discovery plan historical.
9. Focused verify, then commit.

## Task 2: Backend Run, Evidence, Authorization, And Migration Correctness

**Files:** `lib/office_graph/runs.ex` plus a focused reducer module, `lib/office_graph/verification.ex` plus a focused result-slot policy module, `lib/office_graph/authorization.ex`, authorization decision resource/migration if needed, the durable capability migration, reference validators, and focused ExUnit tests.

1. Change the current failed-after-verified assertion first; run it and confirm the old verified state is the failure.
2. Extract/implement explicit observation state reduction: later success preserves verified, any later failure produces failed truth. Run focused and surrounding command-loop tests.
3. Add two distinct failed candidates for one run/check; confirm the second currently yields an unstable constraint error. Preflight the locked slot and return an exact stable conflict before any dependent record.
4. Add stale-waiver authorization-decision assertions; confirm missing allow record. Persist reconstructable allow/deny policy decisions independently of domain success and keep product mutation absent.
5. Inject or exercise lookup failure through each reference validator; replace caller-visible infrastructure text with a stable safe reason.
6. Preseed capability/grants, run migration up/down in a regression, observe deletion, then make down non-destructive and rerun.
7. Run focused domain, authorization, migration, and transport-adjacent tests; commit.

## Task 3: Shared Input And Error Semantics

**Files:** both GraphQL/JSON operator input/error modules and callers, a shared `OfficeGraphWeb.OperatorCommands` parser/classifier namespace, transport tests, `assets/app/relay/commandMutation.ts`, frontend tests.

1. Add table-driven parity cases for every existing public command error plus invalid proposal replay, invalid evidence result, duplicate evidence acceptance/result-slot conflict, and nested unsafe reasons; confirm current divergence.
2. Move the field registry/casting behavior into one transport-neutral parser and update both transports to call it.
3. Implement one classifier returning stable category/code/detail/fields/safe metadata; keep HTTP and GraphQL envelope mapping in their adapters.
4. Recursively sanitize nested reason data and ensure no exception/SQL/adapter text crosses transports.
5. Expand frontend concurrency refresh codes and prove an already-accepted/slot-taken result refreshes authoritative state.
6. Run focused GraphQL, JSON, and frontend mutation tests; commit.

## Task 4: Operator Projection, Pagination, And Command Options

**Files:** `lib/office_graph/projections/operator_workflow.ex` and satellite modules, GraphQL workflow queries/types, packet projection/API code, operator/packet Relay queries and components, generated schema/artifacts, backend and frontend route tests.

1. Seed two pending events from one source with different bodies; add failing API/UI assertions for distinct policy-safe summaries and proposal previews before apply.
2. Project/render safe title/source summary/proposed-action preview, keeping raw IDs/traces secondary and secrets/raw archive absent.
3. Add failing multi-check/redacted-data tests for run/evidence forms; project complete typed command option bundles and consume them without browser-side joins or hard-coded policy defaults.
4. Add more-than-one-page fixtures for packet versions and run child collections; convert naturally growing arrays to Relay connections or compact summary/detail reads with correct pageInfo/incremental UI.
5. Reject negative `first`, return zero edges for zero, and cover both semantics.
6. Remove retired unreleased `operatorInbox`, regenerate GraphQL/Relay artifacts, and run backend projection/API plus route tests; commit.

## Task 5: Relay Cancellation, Accessible Errors, And Frontend Cleanup

**Files:** `assets/app/relay/{environment,fetchGraphQL,commandMutation}.ts`, form support/primitives and route forms, Relay config/model mappings, packet/run navigation, UI copy, dead hooks/exports/styles, Babel/Vite/package configuration, AST boundary/lint tests.

1. Add a subscription-dispose test that observes `AbortSignal.aborted` and no late payload; implement an Observable/cancelable Relay network path for reads and mutations.
2. Add two-field server-error tests; preserve all errors, map snake-case fields to controls, render summary/inline feedback, set ARIA state/descriptions, and focus the first invalid control.
3. Replace internal anchors with client navigation, map DateTime scalars to `string`, remove blind casts, and update product-safe evidence/queue copy.
4. Prove dead caller status, then remove the unused start-run hook/exports, unused style aliases, and unused StyleX runtime/plugin/transform.
5. Replace source-token import checks with TypeScript AST rules that cover static/dynamic imports and re-exports; add frontend lint/format checks using existing or minimally added pinned tooling.
6. Run Relay generation/check, typecheck, focused/full Vitest, and production build; commit.

## Task 6: Cohesion And Test Organization

**Files:** `lib/office_graph/durable_delivery/test_worker.ex`, `test/support`, `lib/office_graph/work_graph/proposed_changes/proposed_graph_change.ex` and new module files, the largest backend/frontend test files, `assets/app/styles/global.css` and route style files.

1. Move the test worker to test support and confirm production compilation no longer contains it while the worker test passes.
2. Split each top-level proposed-change module into its own file without code changes; compile/format/focused tests.
3. After behavior fixes are green, split command-loop, concurrency, conformance, authorization, and operator-projection tests around coherent behavior domains and shared support. Preserve assertions and make async changes only with varied-seed proof.
4. Split operator/packet route tests around reads, commands, errors/security, and fixtures. Split global styles into shared/operator/packet ownership and central tokens; remove only caller-proven dead selectors.
5. Replace remaining high-risk source-string checks where behavior/introspection/AST equivalents exist; clearly name any retained heuristic.
6. Run affected groups and full backend/frontend suites; commit.

## Task 7: Full Verification, Independent Review, Archive, And Ready PR

**Files:** OpenSpec task state/archive, audit/plan docs, any review fixes.

1. Update all completed OpenSpec checkboxes and run `openspec validate harden-project-quality --strict` plus `openspec validate --all --strict`.
2. Run `./bin/verify` twice with varied ExUnit/Vitest seeds and confirm `git status --short` is clean after each.
3. Generate a full branch review package from `e7d005b` to HEAD. Dispatch an independent whole-branch reviewer; fix and re-review every critical/important issue.
4. Use OpenSpec verification against proposal/spec/design/tasks, archive the complete change, and rerun strict validation plus canonical verification.
5. Commit remaining artifacts, push `codex/harden-project-quality`, and create a non-draft PR with base `codex/archive-operator-command-loop`. Include audit scope, fixed findings, test evidence, stacking dependency, and the three structural follow-ups.
