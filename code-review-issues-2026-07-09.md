# Office Graph Code Review Issues - 2026-07-09

This is a handoff note for a later agent to analyze and plan fixes. It records
the frontend and backend issues found during a broad code review of the current
Office Graph worktree. Treat severities as review priorities, not as a completed
implementation plan.

## Verification Context

- `nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --all --strict`
  passed: 92 items.
- `nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets run test`
  passed: 9 files / 34 tests.
- `nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets run typecheck`
  passed.
- `nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets run relay:check`
  passed after backend deps were installed.
- Focused backend operator workflow tests passed: 26 tests.
- `nix --extra-experimental-features 'nix-command flakes' develop --command mix hex.audit`
  failed with the dependency advisories captured below.
- Full `mix verify` was not run because it includes frontend build/deploy steps
  that write generated asset outputs.

## Issues

### P1: Locked backend dependencies have current high-severity DoS advisories

`mix hex.audit` reports high-severity advisories in the locked HTTP/transport
stack and medium advisories in Phoenix/Ash.

Evidence:

- `mix.lock:29` locks `hpax 1.0.3`, flagged as `EEF-CVE-2026-58226` / `HIGH`
  for unauthenticated denial of service via unbounded HPACK integer decoding.
- `mix.lock:37` locks `phoenix 1.8.8`, flagged as `EEF-CVE-2026-56811` /
  `HIGH` for process-exhaustion DoS through unbounded channel joins, and
  `EEF-CVE-2026-56812` / `MEDIUM` for a Phoenix JS presence crash.
- `mix.lock:41` locks `plug 1.19.2`, flagged as `EEF-CVE-2026-54892` / `HIGH`
  for quadratic-time nested query/body parameter decoding.
- `mix.lock:5` locks `ash 3.29.1`, flagged as `EEF-CVE-2026-55736` /
  `MEDIUM` for private action arguments being set by user input.
- `lib/office_graph_web/endpoint.ex:36` enables `Plug.Parsers`, making the Plug
  advisory directly relevant to request handling.
- `lib/office_graph_web/router.ex:20` forwards `/graphql` through Absinthe, so
  external request parsing and GraphQL payload handling depend on the locked
  Phoenix/Plug stack.

Initial analysis questions:

- Identify the minimum safe dependency updates that clear `mix hex.audit`.
- Re-run `mix hex.audit`, focused backend tests, and any release gates after the
  dependency bump.
- Check whether Phoenix channel/socket support is enabled now or likely to be
  enabled soon; that affects urgency for the Phoenix transport advisory.

### P1: Operator console command affordances are display-only

The operator UI exposes backend command affordances as text, but there is no
frontend execution path for the packet/run verification mutation. The console
can inspect state but cannot drive the manual-intake-to-verification workflow.

Evidence:

- `assets/app/routes/operator/data.ts:209` defines
  `ExecutePacketRunVerificationMutation`.
- `assets/app/routes/operator/OperatorWorkspace.tsx:30` only renders
  `ReadinessPanel`, `RunPanel`, and `VerificationPanel`.
- `assets/app/routes/operator/components/ReadinessPanel.tsx:39` renders
  readiness command affordances through `commandAffordanceListText(...)`.
- `assets/app/routes/operator/components/RunPanel.tsx:36` renders run command
  affordances through `commandAffordanceListText(...)`.
- Search found no `commitMutation` or `useMutation` call site under
  `assets/app` or `assets/src`; the mutation is present in data/tests/generated
  artifacts only.

Initial analysis questions:

- Decide the first executable command surface: packet preparation/start, record
  observation, accept evidence, or a narrower vertical slice.
- Preserve disabled/blocker states from backend affordances rather than enabling
  optimistic UI-only commands.
- Add route-level tests for enabled, disabled, submitting, success, and GraphQL
  error states.

### P2: Initial readiness violates the operator-console contract and adds a duplicate read

The current route derives packet-readiness input from the selected inbox row and
then immediately issues a network-only packet-readiness query. The spec requires
the initial panel to be derived from the loaded row as prepare-packet context,
without a duplicate backend readiness read and without claiming the packet can
already be created.

Evidence:

- `openspec/specs/operator-console/spec.md:56` requires initial packet readiness
  to reuse selected row links.
- `assets/app/routes/operator/workflow.ts:133` derives `readinessInput` from the
  selected item.
- `assets/app/routes/operator/workflow.ts:137` immediately calls
  `usePacketReadinessRelayQuery(readinessInput)`.
- `assets/app/routes/operator/workflow.ts:179` issues
  `OperatorPacketReadinessQuery` with `fetchPolicy: "network-only"`.
- `assets/app/routes/operator/components/ReadinessPanel.tsx:36` renders either
  `Prepare packet context` or `Backend readiness`, but current route flow does
  not appear to populate the derived mode.
- `assets/app/routes/operator/route.test.tsx:41` asserts `Backend readiness`
  appears and then inspects the duplicate readiness query variables.

Initial analysis questions:

- Model the selected-row-derived readiness state explicitly, including
  `isDerived`.
- Defer backend readiness fetch until the operator requests validation, the row
  is stale, or a missing detail requires a refresh.
- Update tests so they fail on the duplicate initial readiness query.

### P2: Release build still emits stale legacy Vite assets

The release asset pipeline still runs both the old plain Vite build and the
React Router deploy path. The served app shell is React Router-only and rejects
the old mount target, so the old build creates stale production artifacts and a
misleading dev/build path.

Evidence:

- `mix.exs:97` defines `assets.build` as `assets.setup`,
  `pnpm run build`, `pnpm run router:deploy`, and `pnpm run verify:app-shell`.
- `assets/package.json:8` maps `build` to plain `vite build`.
- `assets/vite.config.ts:16` writes to `../priv/static`, and
  `assets/vite.config.ts:24` emits under `assets/operator/[name].js`.
- `assets/vite.config.ts:21` uses `src/main.tsx` as the Vite entry.
- `assets/src/main.tsx:6` mounts `operator-console-root`.
- `lib/office_graph_web/controllers/operator_console_controller.ex:4` serves
  React Router assets under `/assets/react-router/`.
- `lib/office_graph_web/controllers/operator_console_controller.ex:91` only maps
  React Router asset paths.
- `test/office_graph_web/operator_console_controller_test.exs:49` explicitly
  refutes the legacy `operator-console-root` mount in the served shell.

Initial analysis questions:

- Remove or quarantine the legacy Vite entry/build path if there is no current
  caller.
- Make `pnpm run build` mean the current React Router app, or rename legacy
  scripts so `mix assets.build` cannot emit stale assets.
- Re-run app-shell verification and a production-style asset build after the
  cleanup.

### P2: Packet-run GraphQL errors drop actionable domain failure details

`PacketRunVerification.execute/2` returns distinct domain errors, but GraphQL
normalization collapses many of them into a generic validation error. Clients
cannot distinguish bad source IDs, readiness failures, unsupported evidence
results, replay conflicts, and related lifecycle failures.

Evidence:

- `openspec/specs/ash-api-surface/spec.md:209` requires invalid GraphQL commands
  to return a structured error with a stable code and safe explanatory detail.
- `lib/office_graph_web/graphql/common/errors.ex:127` falls back to
  `%{detail: "Validation failed.", extensions: %{code: "validation_failed"}}`.
- `lib/office_graph/packet_run_verification.ex:54` runs source, readiness,
  evidence-result, and passed-evidence validation before the transaction.
- `lib/office_graph/packet_run_verification.ex:199` returns a distinct
  `{:source_graph_item_check_mismatch, ...}` error when a source graph item does
  not match the verification check.
- `test/office_graph_web/packet_run_verification_api_test.exs:151` currently
  locks in the generic `validation_failed` response for an invalid source/check
  reference.

Initial analysis questions:

- Define the stable public error codes and safe details for each current
  `PacketRunVerification` error tuple.
- Keep sensitive internal IDs out of public details unless already scoped and
  safe for the caller.
- Update GraphQL API tests to assert the distinct code/detail contract.

### P2: Operator projections re-query authorization tables instead of using trusted session facts

Projection command affordance checks re-run authorization database lookups even
when the request already has a trusted session context with current
capabilities. This conflicts with the operator workflow spec and adds avoidable
queries to projection reads.

Evidence:

- `openspec/specs/operator-workflow/spec.md:177` requires projection
  authorization to evaluate trusted session facts without re-querying
  capability, role-capability, role, and role-assignment rows for every
  projection subread.
- `lib/office_graph/projections/command_affordance.ex:80` calls
  `Authorization.authorize/3` for command affordance checks.
- `lib/office_graph/authorization.ex:149` validates the session and action.
- `lib/office_graph/authorization.ex:205` re-reads `Capability`.
- `lib/office_graph/authorization.ex:216` re-reads `RoleCapability` and `Role`.
- `lib/office_graph/authorization.ex:235` re-reads `RoleAssignment`.
- `lib/office_graph/projections/operator_workflow.ex:213` checks command
  authorization during inbox projection assembly.
- `lib/office_graph/projections/run_state.ex:154` checks command authorization
  during run-state projection assembly.
- `test/office_graph/projections/operator_workflow_test.exs:219` currently
  asserts that trusted session capabilities are revalidated for projection reads,
  which is the opposite of the accepted spec text.

Initial analysis questions:

- Confirm the intended shape of trusted capability facts on the session context.
- Add a projection test that fails if command affordance subreads query
  capability/role/assignment tables when trusted facts are present.
- Keep a separate path for request-scoped bootstrap or stale/untrusted sessions
  if that behavior is still needed.

## Additional Issues From Inline Review Pass

This section was appended during a second frontend/backend review pass performed
inline, without dispatching subagents.

### P2: Projection source watermarks are placeholders, so clients cannot detect stale readiness or run state

Operator projections expose `sourceWatermark` fields, and the frontend reads
them, but two projection surfaces do not return meaningful freshness markers.
Packet readiness always returns `nil`, and run state uses the immutable run id
instead of a value that changes when observations, evidence candidates, evidence
items, verification results, or required-check states change.

Evidence:

- `openspec/specs/operator-workflow/spec.md:120` requires GraphQL product reads
  for workflow state, packet readiness, run state, evidence state, and
  verification outcome to share source-watermark semantics.
- `openspec/specs/operator-console/spec.md:64` requires item detail refresh when
  the source watermark requires refresh.
- `lib/office_graph/projections/packet_readiness.ex:29` builds the readiness
  projection, but `lib/office_graph/projections/packet_readiness.ex:39` sets
  `source_watermark: nil` for every response.
- `lib/office_graph/projections/run_state.ex:48` builds the run-state
  projection, but `lib/office_graph/projections/run_state.ex:53` sets
  `source_watermark: summary.run.id`, which does not change as child state
  changes.
- `assets/app/routes/operator/data.ts:108` and
  `assets/app/routes/operator/data.ts:133` query `sourceWatermark` for readiness
  and run-state projections.
- `assets/app/routes/operator/derived.ts:43` carries the run-state watermark
  into the derived verification outcome, so the placeholder run id also affects
  the verification panel.

Initial analysis questions:

- Define a projection watermark contract that changes when any record visible in
  the projection changes.
- Consider operation ids, max `updated_at`, revision/audit operation watermarks,
  or a composite stable digest depending on the projection.
- Add backend projection tests that mutate child run/evidence state and assert
  the run-state and verification watermarks change.
- Add frontend tests for stale-watermark transitions instead of relying only on
  fetch error states.

### P2: Failed accepted evidence is reported as missing accepted evidence instead of a failed-check reason

When an operator accepts failed evidence, the run-state projection sets the
overall status to `failed` but still reports the check under
`missingEvidence` with `missing_accepted_evidence`. That gives the UI the wrong
reason category for a completed negative verification decision.

Evidence:

- `openspec/specs/operator-workflow/spec.md:106` requires evidence that is
  missing, stale, failed, unauthorized, unrelated, or rejected by policy to
  surface explicit reason codes including `failed-check`.
- `openspec/specs/operator-console/spec.md:112` requires the console to present
  incomplete or failed verification with the specific missing-evidence,
  stale-evidence, failed-check, authorization, or policy reason codes.
- `lib/office_graph/runs.ex:707` computes `missing_evidence/2` from only
  passed verification results.
- `lib/office_graph/runs.ex:713` maps every required check without a passed
  result to `%{reason: "missing_accepted_evidence"}`, including checks with a
  failed accepted result.
- `lib/office_graph/projections/run_state.ex:121` maps failed run state to
  `status: "failed"`, but keeps `summary.missing_evidence` unchanged in
  `lib/office_graph/projections/run_state.ex:117`.
- `test/office_graph/projections/operator_workflow_test.exs:749` currently
  locks in this behavior, asserting a failed run reports
  `missing_accepted_evidence` at
  `test/office_graph/projections/operator_workflow_test.exs:782`.

Initial analysis questions:

- Decide whether failed checks belong in `missingEvidence`, a new
  `failedEvidence`/`failedChecks` projection field, or a generalized
  verification-reason collection.
- Preserve the failed verification result link so the UI can show the failed
  evidence item, actor, operation, policy basis, and affected graph item.
- Update backend projection/API tests so accepted failed evidence yields a
  failed-check reason instead of a missing-evidence reason.
- Update `VerificationPanel` rendering once the backend exposes the distinct
  failed-check reason.

### P2: The GraphQL fetch layer discards structured error extensions before the UI can act on them

The Relay network layer parses a GraphQL response and immediately throws a plain
`Error` with only the first error message. That discards `extensions.code`,
field metadata, conflict ids, and any partial response data. Even after backend
error mapping is improved, the frontend will still be unable to branch on stable
domain codes or show targeted remediation.

Evidence:

- `openspec/specs/ash-api-surface/spec.md:209` requires invalid GraphQL
  commands to return stable public error codes and safe explanatory detail.
- `assets/app/relay/fetchGraphQL.ts:31` parses the full GraphQL response.
- `assets/app/relay/fetchGraphQL.ts:33` selects only the first error.
- `assets/app/relay/fetchGraphQL.ts:35` throws `new Error(firstError.message)`,
  dropping `extensions` and remaining errors.
- `assets/app/relay/fetchGraphQL.ts:39` checks HTTP status after the GraphQL
  error throw, so a structured 400 GraphQL response is also reduced to a plain
  message.
- `assets/app/relay/fetchGraphQL.test.ts:75` and
  `assets/app/relay/fetchGraphQL.test.ts:93` assert that GraphQL errors reject
  with only the message string.
- `assets/app/routes/operator/workflow.ts:385` has fallback logic for a Relay
  error carrying `source.errors`, but the current fetch layer throws a plain
  `Error`, so that structured branch is bypassed.

Initial analysis questions:

- Preserve the full `GraphQLResponse` on a typed frontend error object or return
  the GraphQL response to Relay and let route state derive structured errors.
- Keep tests that distinguish unauthorized, validation, idempotency conflict,
  stale, and lifecycle errors by `extensions.code`.
- Decide whether partial data with errors should be rendered as stale/partial
  projection state or treated as a hard route error per surface.

### P2: Command input defaults are reconstructed in the frontend from raw graph links

The projection contract says backend reads must provide command input shape,
defaults, validation hints, and target identities so the frontend does not
reconstruct domain relationships from raw projection internals. The current
backend affordance type exposes required field names and target ids, but not
default input values or a stable input object. The frontend fills that gap by
deriving packet readiness input from `graphLinks`.

Evidence:

- `openspec/specs/ui-projection-contracts/spec.md:117` requires allowed commands
  to come from backend reads.
- `openspec/specs/ui-projection-contracts/spec.md:122` requires the backend read
  to provide the required command, stable input shape, allowed action, and
  blocker reasons.
- `openspec/specs/ui-projection-contracts/spec.md:130` requires backend reads to
  provide required fields, defaults, validation hints, and target identities
  when operator-authored fields or local form state are needed.
- `lib/office_graph_web/graphql/operator_workflow/types.ex:44` defines
  `operator_command_affordance` with `identity`, `state`, reasons, explanation,
  `required_fields`, `target_ids`, `trace_links`, and `decision_links`, but no
  typed default input or validation-hint object.
- `lib/office_graph/projections/operator_workflow.ex:803` enables
  `prepare_packet` by emitting target ids from graph links, but does not project
  packet input defaults.
- `assets/app/routes/operator/derived.ts:8` derives
  `PacketReadinessInput` in the frontend.
- `assets/app/routes/operator/derived.ts:19` fills title, objective, context,
  requirements, success criteria, autonomy posture, source ids, and check ids
  from selected row links.
- `assets/app/routes/operator/components/ReadinessPanel.tsx:46` renders packet
  readiness fields from the frontend-derived `readinessInput`.

Initial analysis questions:

- Add a command-input/default projection shape to command affordances, or add a
  dedicated prepare-packet context projection.
- Keep operator-authored fields local, but have the backend provide stable
  defaults and validation hints for each command identity.
- Update frontend tests so readiness and future command execution do not depend
  on manually reconstructing source/check relationships from raw `graphLinks`.

### P3: Mobile topbar layout can overlap the workbench

The desktop layout uses a fixed topbar grid row. The mobile media query changes
the topbar itself into a multi-row column with padding and a search input, but
it does not change the parent grid row from the fixed token height. On small
screens, the header content can exceed the fixed row and visually overlap the
workbench.

Evidence:

- `assets/src/design/concept.ts:31` defines `topbarHeight` as `56px`.
- `assets/src/styles/global.css:85` defines `.console-frame` as a grid.
- `assets/src/styles/global.css:87` sets the first row to
  `var(--og-layout-topbar-height)`.
- `assets/src/styles/global.css:442` starts the mobile media query.
- `assets/src/styles/global.css:452` changes `.topbar` to mobile layout,
  including `flex-direction: column` at
  `assets/src/styles/global.css:455` and vertical padding at
  `assets/src/styles/global.css:456`.
- `assets/src/styles/global.css:459` makes the search box full width, and the
  input still has a 36px height from `assets/src/styles/global.css:127`.
- No mobile rule updates `.console-frame` to use `auto minmax(0, 1fr)` or an
  equivalent row definition.

Initial analysis questions:

- Change the mobile `.console-frame` row definition to let the topbar size to
  content.
- Add a responsive layout test or browser screenshot check around the `980px`
  breakpoint and a narrow mobile width.
- Check long localized labels and disabled search placeholder text against the
  same mobile layout.

## Resolution Analysis - 2026-07-09

This section records the inline follow-up analysis and fixes performed on branch
`codex/fix-office-graph-review-issues`.

### P1: Locked backend dependencies have current high-severity DoS advisories

Status: Fixed in `9e96e4a`.

Resolution:

- Updated the locked backend packages that carried active `mix hex.audit`
  advisories: `ash`, `hpax`, `phoenix`, and `plug`.
- Re-ran `mix hex.audit`; it completed with no advisories.
- Re-ran frontend build/deploy/app-shell verification and focused backend
  operator tests after the lockfile update.

### P1: Operator console command affordances are display-only

Status: Fixed in `ddc5ba9`, building on the backend command contract from
`caf84d2`.

Resolution:

- Added a readiness-panel execution control for the derived `prepare_packet`
  command context.
- Wired the operator route to commit `ExecutePacketRunVerificationMutation`.
- Preserved disabled state by deriving executability from backend command
  affordance state and complete backend-provided defaults.
- Added route tests for executing the enabled command and for avoiding the
  previous display-only path.

### P2: Initial readiness violates the operator-console contract and adds a duplicate read

Status: Fixed in `ddc5ba9`.

Resolution:

- Removed the eager `OperatorPacketReadinessQuery` from initial row selection.
- Derived the initial readiness panel from the selected workflow row and
  backend-provided command defaults.
- Updated route tests to assert `Prepare packet context` mode and fail if the
  duplicate readiness query is issued on initial selection.

### P2: Release build still emits stale legacy Vite assets

Status: Fixed in `9e96e4a`.

Resolution:

- Made `pnpm run build` target the React Router build.
- Kept `vite.config.ts` as a Vitest/test config instead of a production asset
  emitter.
- Removed the unused legacy Vite app entry files.
- Verified `pnpm --dir assets run router:deploy`, `mix assets.build`, and the
  app-shell verifier after the cleanup.

### P2: Packet-run GraphQL errors drop actionable domain failure details

Status: Fixed in `caf84d2`.

Resolution:

- Mapped packet-run verification domain tuples to stable GraphQL
  `extensions.code` values.
- Covered source/check mismatch, readiness failure, unsupported evidence
  results, and invalid evidence input cases.
- Updated GraphQL API tests so invalid source/check input no longer locks in the
  generic `validation_failed` response.

### P2: Operator projections re-query authorization tables instead of using trusted session facts

Status: Fixed in `caf84d2`.

Resolution:

- Added a trusted projection authorization path for projection command
  affordance checks.
- Updated command affordance authorization to use trusted session capabilities
  instead of re-querying role/capability tables during projection reads.
- Updated projection tests to reflect the accepted operator workflow contract.

### P2: Projection source watermarks are placeholders, so clients cannot detect stale readiness or run state

Status: Fixed in `caf84d2` for backend projection semantics, with frontend
readiness behavior aligned in `ddc5ba9`.

Resolution:

- Packet readiness now produces a deterministic digest watermark from visible
  readiness inputs, blockers, source links, and required checks.
- Run-state projection watermarks now reflect visible child state instead of the
  immutable run id.
- Frontend derived readiness carries the selected row watermark forward instead
  of forcing a duplicate backend readiness read.

### P2: Failed accepted evidence is reported as missing accepted evidence instead of a failed-check reason

Status: Fixed in `caf84d2`.

Resolution:

- Updated run missing-evidence analysis so failed accepted evidence reports the
  distinct `failed_check` reason.
- Updated backend projection tests for the failed-run case.
- Kept the existing `missingEvidence` projection shape, but corrected the reason
  category so the current UI can render the specific failure reason.

### P2: The GraphQL fetch layer discards structured error extensions before the UI can act on them

Status: Fixed in `ddc5ba9`.

Resolution:

- Added `GraphQLResponseError`, preserving the full GraphQL response payload,
  HTTP status, and request name.
- Kept plain HTTP failure handling for non-GraphQL error bodies.
- Added tests for structured error extensions and partial-data responses with
  GraphQL errors.

### P2: Command input defaults are reconstructed in the frontend from raw graph links

Status: Fixed in `caf84d2` and `ddc5ba9`.

Resolution:

- Added `inputDefaults` to backend command affordances and the GraphQL
  `OperatorCommandAffordance` type.
- Projected prepare-packet defaults for title, objective, context, requirements,
  success criteria, autonomy posture, source ids, verification check ids, and
  primary source/check ids.
- Updated frontend derivation to consume command defaults instead of
  reconstructing packet command input from raw graph links.
- Regenerated Relay artifacts and schema.

### P3: Mobile topbar layout can overlap the workbench

Status: Fixed in `ddc5ba9`.

Resolution:

- Added a mobile `.console-frame` rule that uses `auto minmax(0, 1fr)` so the
  topbar row can expand after it switches to stacked mobile layout.
- Covered the change through the existing frontend full test run and app-shell
  verification path.
