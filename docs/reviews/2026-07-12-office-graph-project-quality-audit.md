# Office Graph Project Quality Audit

Date: 2026-07-12  
Reviewed base: `e7d005b` (open PR #21, `codex/archive-operator-command-loop`)  
Remediation change: `openspec/changes/harden-project-quality`

## Scope And Method

The review covered the full tracked project: canonical OpenSpec contracts and archived changes, Elixir domain and transport code, Ecto migrations, ExUnit support and integration tests, React/Relay routes and generated boundaries, frontend styles/tooling, Nix/Compose configuration, Mix aliases, local scripts, dependency locks, and the open PR's current review threads.

The baseline contains roughly 42,000 lines of application and test code, 95 canonical specifications, 185 Credo-scanned source files, and 399 statically declared ExUnit tests across 27 modules. Review methods included contract-to-code tracing, call-site and ownership searches, duplicate and dead-code searches, file-size/cohesion analysis, transport-parity comparison, migration reversibility review, static-gate execution, and focused reproduction of Mix alias semantics. Findings from the earlier 2026-07-09 audit were checked and not recycled after their fixes.

Severity means:

- **P1:** can produce materially wrong product state, unsafe operator action, or a false merge signal now.
- **P2:** current correctness, safety, accessibility, performance-growth, or maintainability defect that should be fixed before the next feature layer.
- **P3:** localized hygiene or developer-experience defect with a clear low-risk correction.
- **Structural follow-up:** accepted contract work requiring its own data/compatibility design; a partial audit patch would be riskier than leaving the explicit gap visible.

## Confirmed Findings And Disposition

### QG-001 — P1: The canonical gate silently omits most backend behavior tests

`mix.exs` runs `architecture.conformance`, which invokes Mix's `test` task, before the later full `test` entry in both `verify` and `precommit`. Mix tasks run once per VM, so only the 70 architecture tests are reached; roughly 329 declared tests in the other 26 modules are skipped. The gate can therefore report success without exercising command loops, authorization, persistence, concurrency, durable delivery, or public APIs.

**Disposition:** fix in this change. Invoke the full test alias once, keep the focused architecture command developer-only, and add a gate regression outside that file.

### QG-002 — P1: Shared local infrastructure corrupts concurrent worktree evidence

`compose.yaml` fixes one container name and host port; `config/test.exs` fixes one database base name; `bin/verify-backend` assigns no Compose project or test partition. The concurrency suite also creates and drops global database trigger/function names. Two worktrees can collide, remove each other's barriers, or corrupt `_build`/database evidence.

**Disposition:** fix in this change. Derive stable per-worktree Compose, port, and test partition identities with explicit overrides and an external-Postgres opt-out.

### QG-003 — P2: No single enforced all-layer verification contract

`mix verify` includes frontend work but omits strict OpenSpec validation and is affected by QG-001. `bin/verify-backend` includes OpenSpec but omits frontend. The README documents the partial backend sequence, there is no tracked CI workflow, and neither path proves production release construction.

**Disposition:** fix in this change. One Nix-backed script becomes the documented local and CI entry point.

### QG-004 — P2: Dependency advisories are manual and a current Postgrex advisory is present

Neither backend nor frontend verification includes an advisory check. The current lock selects Postgrex 0.22.2, which local Hex metadata reports under EEF-CVE-2026-58225 / GHSA-4mw9-4qgj-m97w.

**Disposition:** update the dependency and make advisory checks part of the canonical gate.

### QG-005 — P3: Precommit mutates the lockfile

`precommit` runs `mix deps.unlock --unused`, turning a check into a rewrite and making a clean-tree result depend on invocation order.

**Disposition:** replace it with `deps.unlock --check-unused` and make precommit delegate to the canonical check sequence.

### QG-006 — P3: `PHX_SERVER=false` enables the server

`config/runtime.exs` treats every nonempty `PHX_SERVER` value as true. Values such as `false`, `0`, or a typo unexpectedly enable the endpoint.

**Disposition:** fix exact boolean parsing with runtime-config regression coverage.

### QG-007 — P2: Durable specs retain generated AI-placeholder purposes

Sixty-three canonical specs still contain the exact generated line `TBD - created by archiving change ...`. Strict OpenSpec validation accepts it, so the archive workflow has accumulated content-free headings that make discovery and review look complete while conveying no purpose. `openspec/project-plan.md` also still presents the project as discovery-era work.

**Disposition:** replace every placeholder with a concise requirement-grounded purpose, mark the old plan historical, and add a gate check.

### BE-001 — P1: A late failed observation can leave a run verified

`lib/office_graph/runs.ex` short-circuits on `run_verified?/1` before handling a non-success observation. The failed observation is persisted, but aggregate, execution, and verification state remain verified. An existing command-loop test currently codifies this contradiction. `work-runs` preserves verified state only for later successful observations without a failure/staleness signal.

**Disposition:** fix regression-first. Later success remains idempotent; later failure moves the run to failed truth.

### BE-002 — P2: A second failed result leaks a persistence constraint instead of a stable conflict

Evidence acceptance rejects verified runs and applies failure-specific checks only to passed results. A second distinct failed candidate for the same locked run/check reaches the unique database index after dependent evidence work begins. The transaction rolls back, but callers receive an Ash/database-shaped error rather than a public command conflict.

**Disposition:** preflight the result slot under the existing lock before creating documents/evidence and map one stable conflict through both transports.

### BE-003 — P2: Authorized-but-rejected waivers lose the authorization decision

`Authorization.authorize_operation/4` persists denials only. A principal can be authorized to waive a check, then fail stale/check/domain validation, leaving no durable allow decision even though policy evaluation occurred. That prevents reconstruction of policy-sensitive attempts.

**Disposition:** persist allow and deny policy decisions independently from command outcome; prove a stale waiver records allow, mutates no product state, and returns the stable stale result.

### BE-004 — P2: Capability migration rollback can delete pre-existing authorization data

The durable-delivery capability migration uses conflict-safe inserts in `up/0`, but `down/0` deletes every matching grant and the capability row. It cannot distinguish migration-owned rows from pre-existing or later grants.

**Disposition:** make rollback explicitly non-destructive and test preseeded capability/non-owner grants across up/down.

### BE-005 — P3: Reference validation can expose internal exception text

The same-scope and run-required-check validators interpolate lookup failures into Ash validation messages. Adapter, SQL, or exception details can cross a public error boundary.

**Disposition:** return a stable safe validation reason and retain detailed failures only in internal logging.

### API-001 — P2: GraphQL and JSON duplicate 150-line input parsers

`OfficeGraphWeb.GraphQL.OperatorCommands.Input` and `OfficeGraphWeb.JsonApi.OperatorCommands.Input` carry the same command field registry and casting algorithm. The static duplicate detector misses them because its configured scope excludes web code.

**Disposition:** replace both with one transport-neutral parser; transports retain only envelope/controller responsibilities.

### API-002 — P2: Command error registries have already drifted

GraphQL maps invalid proposal replay and invalid evidence result outcomes that JSON falls through to generic validation. Expected concurrency outcomes such as already-accepted evidence also fall through, so the frontend does not refresh authoritative state. JSON nested reason formatting is less defensive than GraphQL.

**Disposition:** one safe classifier supplies code, category, safe detail, fields, and recursively sanitized metadata; table-drive both transport adapters over every public command outcome.

### UI-001 — P1: Pending work must be applied without a meaningful preview

The operator inbox title is a normalized-event UUID. Detail shows identities, counts, and traces but no policy-safe source summary or proposed-action preview. Multiple rows from the same source are practically indistinguishable after reload, and the operator cannot understand what Apply will create.

**Disposition:** project safe summaries/previews and render them as primary row/detail content, with identifiers and traces secondary.

### UI-002 — P2: Growing projection collections are unbounded

Packet versions, graph links/relationships, required checks, observations, evidence, results, and missing-evidence rows are exposed as raw arrays. Packet queries fetch complete historical contract bodies even where the UI uses four summary fields. Payload and Relay-store cost grows without a bound.

**Disposition:** use Relay connections or compact summaries, fetch current detail separately, and cover page boundaries plus incremental reads.

### UI-003 — P2: Forms reconstruct domain relationships in the browser

Run and evidence forms join independent projection arrays and hard-code source/trust/sensitivity/policy defaults to construct commands. Missing, redacted, or reordered projection data can enable a command with an empty or mismatched identity.

**Disposition:** backend projections supply typed option bundles containing every stable ID and approved default for a valid choice; malformed bundles disable the command.

### UI-004 — P2: Field errors are discarded and inaccessible

The Relay layer preserves multiple field errors, but form support keeps only the first. Feedback stores the field name in a `data-field` attribute without associating any control, visible inline message, invalid state, description, or focus.

**Disposition:** retain all errors, map server fields to control IDs, render summary and inline messages, set `aria-invalid`/`aria-describedby`, and focus the first invalid control.

### UI-005 — P2: Relay disposal does not cancel HTTP

The network layer returns a Promise and owns only a timeout abort controller. Relay disposal detaches its subscription but leaves the request running and able to resolve late.

**Disposition:** provide an Observable/cancelable network layer whose cleanup aborts the underlying fetch and ignores late payloads.

### UI-006 — P3: Pagination, navigation, scalar, and copy edge defects

Negative/zero `first` values are clamped to one; an internal run link uses a raw anchor and reloads the document; DateTime Relay fields become `any` and are blindly cast; product UI exposes internal “Evidence candidate” nouns; the packet route calls a writable queue read-only.

**Disposition:** correct each localized contract and cover it in route/API tests.

### UI-007 — P3: Retired and unused frontend paths remain compiled

The retired unreleased `operatorInbox` field remains exposed. An operator start-run hook/config has no production caller, as do several UI exports and styles. StyleX runtime and Babel transforms are installed and executed despite no production StyleX usage.

**Disposition:** remove evidence-backed dead paths/tooling and regenerate artifacts. Accepted extension points with active spec ownership remain.

### TEST-001 — P2: High-risk architecture rules rely on source strings

The architecture suite contains dozens of `File.read!` substring assertions for lock order and module shape. Frontend route tests forbid literal token/function names, while the import parser misses dynamic imports and re-exports. Comments and renames can cause false signals without proving runtime behavior.

**Disposition:** replace executable contracts with behavior/Ash introspection/TypeScript AST checks. Retained heuristics must be named as such.

### TEST-002 — P2: A concurrency proof relies on a timed sleep

One integration test sleeps 100 ms after observing a blocked insert before counting contenders. Scheduler delay can let the second contender arrive after the count, allowing a false pass.

**Disposition:** use an explicit both-contenders-started barrier and deterministic lock-state assertion.

### TEST-003 — P2: Test organization blocks focus and safe parallelism

Twenty-three of 27 ExUnit modules are `async: false`; the default bootstrap fixture is called directly 159 times; several modules combine unrelated behaviors and thousands of lines without `describe` boundaries. This increases shared-state pressure and makes failures hard to localize.

**Disposition:** extract unique factories and DDL/global-state support, split the clearest behavior domains, and mark cases async only after repeated varied-seed proof.

### CODE-001 — P3: Test-only worker is compiled into production

`lib/office_graph/durable_delivery/test_worker.ex` has no production caller and exists solely for `worker_test.exs`.

**Disposition:** move it under `test/support`.

### CODE-002 — P2: Multiple top-level validators share one 531-line source file

`proposed_graph_change.ex` combines the resource with several validator modules. This obscures ownership and inflates rebuild/review scope without preserving a transactional boundary.

**Disposition:** one cohesive module per file; no behavior change.

### CODE-003 — P2: Core service modules have mixed responsibilities

`verification.ex` (1,039 lines), `operator_workflow.ex` (1,002), `runs.ex` (877), `proposed_changes.ex` (646), and `work_packets.ex` (598) combine command entry points, replay, state reduction, persistence helpers, and reads. Line count alone is not the issue; independent policies and reductions are buried inside transaction orchestration.

**Disposition:** extract the run reducer and evidence result-slot policy as independently testable seams during their bug fixes. Do not fragment transactions or perform a wholesale file-count refactor in this PR.

### CODE-004 — P2: Several test/style files are too large to review reliably

The command-loop test is 4,528 lines, concurrency 3,670, Ash conformance 2,756, authorization 1,828, operator projection 1,591, operator route test 1,848, packet route test 1,174, and global CSS 860. Helpers and unrelated behaviors are interleaved.

**Disposition:** split the highest-value files around stable behavior/route ownership and shared fixtures after regressions land; preserve generated artifacts and cohesive historical migrations.

## Structural Follow-Ups Requiring Separate OpenSpec Changes

These are confirmed mismatches, not dismissed findings. They are not partially implemented in this remediation because each changes durable data contracts and compatibility behavior.

1. **Organization-scoped durable delivery and system operations.** Canonical specs allow optional workspace/subject version and organization-scoped/system-job operations, while current requests/resources/migrations require workspace, principal, session, and version (defaulting missing version to 1). A follow-up must define topics, idempotency scope, authorization, job payloads, and nullability together.
2. **Append-only verification decision history.** Current unique result slots cannot preserve partial-to-verified snapshots or supersession/re-verification history. A follow-up must add decision snapshots/lifecycle and a current-decision constraint with data migration.
3. **Typed graph relationship storage.** Current relationships store endpoints and a free-form type but lack the accepted registry, endpoint compatibility, explicit scope/lifecycle/provenance, and historical preservation model. A follow-up must design the registry and migrate existing edge vocabulary.

## Reviewed And Intentionally Retained

- Request-scoped trusted projection contexts are server-created and explicitly permitted; no external transport currently accepts a forged session context.
- Duplicate realtime delivery is permitted, so broadcast-before-dispatch marking is not treated as a defect.
- Empty future bounded-context modules contain no placeholder behavior and are explicitly allowed by the architecture contract.
- Large generated Relay artifacts, declarative GraphQL schema modules, and coherent immutable migrations are not refactored merely for line count.
- Direct repeat-completion rejection remains covered intentional behavior.

## Completion Standard

The remediation is complete only when each in-scope finding above has a red/green or structural verification, strict OpenSpec validation passes, dependency advisories are clear, the canonical Nix-backed gate runs the actual full suite and all frontend/build checks, an independent reviewer finds no material issue, the worktree is clean, and the ready PR targets the current open PR branch.
