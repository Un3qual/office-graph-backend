# Task 4 Report: Operator Projection, Pagination, And Command Options

Status: DONE

## Delivered

- Added policy-safe workflow `title`, `sourceSummary`, and proposed-action previews derived from normalized proposal metadata. The operator inbox and detail surfaces lead with those summaries while IDs remain secondary; neither raw intake body nor archived payload is projected.
- Added complete typed observation, evidence-candidate, evidence-acceptance, and waiver command-option bundles. Run forms now consume those bundles directly, including stable IDs and domain defaults, without reconstructing joins or policy values from parallel browser collections.
- Replaced packet `versions` with a forward Relay `versionHistory` connection and added cursor-driven next/previous history reads in the packet UI.
- Added a typed run `activity` connection plus bounded child collections and exact compact `childSummary` counts. The run panel identifies when additional child detail exists.
- Bounded workflow graph link/relationship projections to 20 entries and exposed exact `relationshipSummary` counts and `hasMore` state.
- Preserved forward-pagination edge semantics: `first: 0` returns zero edges with accurate `pageInfo`; negative `first` is rejected through the safe GraphQL validation envelope.
- Removed the unreleased GraphQL `operatorInbox` field and type, migrated API tests to `operatorWorkflowItems`, and regenerated the schema and Relay artifacts.
- Marked only OpenSpec tasks 5.1-5.4 complete.

## RED Evidence

1. Safe proposal projection
   - The API query failed because `title`, `sourceSummary`, and `proposedActionPreviews` did not exist.
   - The route test exposed raw UUID-oriented item labels instead of distinct reviewable proposal content.

2. Typed command options
   - The API query failed because `commandOptions` did not exist.
   - With parallel run collections redacted, the route could not render actionable run/evidence choices; malformed incomplete options were not filtered at the projection boundary.

3. Pagination and retired schema
   - Packet detail failed on the missing `versionHistory` connection and the UI had no incremental version navigation.
   - Inbox `first: 0` returned an edge instead of an empty page, and negative values were not rejected at the connection boundary.
   - The schema still exposed the retired `operatorInbox` entry point.

## GREEN Verification

All commands ran in the pinned project Nix shell.

Focused backend projection/API:

```sh
mix test test/office_graph_web/operator_workflow_api_test.exs \
  test/office_graph/projections/operator_workflow_test.exs
```

Result: 42 passed, 0 failures (seed 317808).

Focused frontend routes:

```sh
pnpm --dir assets exec vitest run \
  app/routes/operator/route.test.tsx \
  app/routes/packets/route.test.tsx --reporter=dot
```

Result: 2 files passed, 58 tests passed.

Generated/static/build/OpenSpec verification:

```sh
mix format --check-formatted
pnpm --dir assets run relay:check
pnpm --dir assets run typecheck
pnpm --dir assets run build
openspec validate harden-project-quality --strict
git diff --check
```

Result: all commands exited 0; Relay compiled 20 reader and 16 normalization documents, TypeScript emitted no errors, the production client/SSR build passed, and OpenSpec reported the change valid.

## Self-review Follow-up

Review found that changing the selected waiver check submitted the selected option's policy but left the visible policy field showing the first option's default.

- RED: the focused waiver route test expected `security_exception` after selecting the second option but received `owner_exception` (1 failed, 34 skipped).
- GREEN: the form now tracks the selected waiver option, resets an explicit policy override when the option changes, and renders/submits the same typed default. The focused test passed (1 passed, 34 skipped), followed by a clean TypeScript check.

## Commits

- `cf8e998` — `feat: project safe operator proposal summaries`
- `dabc437` — `feat: project typed operator command options`
- `6ed1916` — `feat: bound operator workflow collections`
- `49edfa9` — `fix: track selected waiver option defaults`

Nothing was pushed.

## Independent Review Remediation

Status: DONE

### Critical: raw-intake-derived public summaries

Focused RED:

```sh
mix test test/office_graph_web/operator_workflow_api_test.exs:305
```

Result: 0/1 passed. A body beginning with `SECRET_TOKEN=must-not-leak` produced that exact value as the public workflow title.

GREEN changes:

- Public titles are now `Manual intake proposal <short normalized-event ref>`.
- Source summaries contain only proposal count and the server-generated short event reference.
- Proposal previews use a closed change-kind label registry and never read proposal payload titles.
- The regression places secrets in the first sentence, source identity, and body-derived proposal title, then proves none appears in `title`, `sourceSummary`, or `proposedActionPreviews`; rows remain distinguishable by generated reference/count.

### Important: bounded data-layer pagination and stable cursors

- Packet workspace now fetches current version by ID, reads references/checks only for that current version, obtains an exact count separately, and pages history with a `(version_number, id)` keyset query using `limit + 1`. The nested GraphQL resolver no longer calls `Connection.from_list/2` or receives every version.
- Run projection uses `Runs.get_projection_summary/3`: every projected child detail query is limited to 20, while one scoped aggregate query obtains exact counts. Evidence candidates are also limited at the data layer.
- Run activity is a parameterized scoped SQL union over persisted child sources with deterministic `(inserted_at, kind, UUID)` ordering, an opaque keyset cursor, and `limit + 1`. An insertion after the first-page cursor remains visible without skipping pre-existing records.
- Exact pending-acceptance status counts include only fresh candidates with an accepted trust basis and a pending required-check match. This preserved the existing stale/untrusted-candidate semantics discovered during the final gate.
- Relationship overflow has a dedicated authenticated `(kind, stable_id)` keyset connection and an incremental detail UI.
- The product run fragment requests the activity connection. Run and relationship panels render the current page and expose usable load-more controls.

### Important: backend-owned observation outcomes

- Observation command options now carry `defaultOutcomeKey` and typed outcome choices containing key, label, observed status, and normalized status.
- The form renders and submits the selected projected choice. A nonstandard `degraded` choice proves the browser does not synthesize succeeded/failed mappings.

### Minor: blank and redaction-sentinel options

Focused RED:

```sh
mix test test/office_graph_web/operator_workflow_api_test.exs
```

Result: 15/16 passed. An observation option with label `  [REDACTED]  ` was still projected.

GREEN: the backend recursively rejects trim-blank, `[REDACTED]`, `<redacted>`, `redacted`, and `***` values, including typed outcome members. Both frontend command forms apply the same fail-closed rule. The focused API regression and malformed-option UI regression passed.

### Review and final verification

The first full review gate found one status regression: 42/43 covering backend tests passed because the exact pending-candidate count included stale/untrusted candidates. The aggregate query was narrowed to the domain acceptance predicate; the focused regression then passed 1/1.

Final Nix-shell gate:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test test/office_graph_web/operator_workflow_api_test.exs \
  test/office_graph/projections/operator_workflow_test.exs
pnpm --dir assets run relay:check
pnpm --dir assets run typecheck
pnpm --dir assets exec vitest run app/routes/operator/route.test.tsx \
  app/routes/packets/route.test.tsx --reporter=dot
pnpm --dir assets run build
openspec validate harden-project-quality --strict
git diff --check
```

Results:

- Backend projection/API: 43 passed, 0 failures (seed 181500).
- Frontend operator/packet routes: 60 passed, 0 failures.
- Relay: 21 reader, 17 normalization, and 21 operation documents validated.
- TypeScript, warnings-as-errors compilation, production client/SSR build, strict OpenSpec, formatting, and diff checks passed.

## Second Independent Review Remediation

Status: DONE

### Globally distinct safe labels

The generated workflow title, source summary, and every proposal preview now carry the complete server-generated normalized-event UUID. No 8-character prefix is used as a uniqueness claim. The same-source regression proves two ordinary events produce different complete preview bundles while first-sentence, source-identity, and body-derived secrets remain absent from all three safe fields.

### Reachable bounded command choices and complete outcomes

- Added authenticated `commandOptionPage(kind:, first:, after:)` connections for observation, evidence-candidate, evidence-acceptance, and waiver choices.
- Each kind uses a scoped data-layer query ordered by `(inserted_at, UUID)`, an opaque keyset cursor, `limit + 1`, complete typed nested option nodes, and server-side nonsentinel filtering.
- The compact run projection remains capped at 20. When exact child counts indicate overflow, the UI reads all four bounded choice pages independently, feeds only the current typed page to the existing forms, and exposes explicit previous/next controls.
- A 21-check regression proves the first page contains 20 choices and the 21st valid observation choice remains reachable on page two.
- Verification outcome no longer reuses compact `operatorRunState`; its purpose-specific read loads every required check and verification result. The 21-check regression accepts all 21 results and proves the outcome returns all 21 with no missing evidence.

### Relationship and active-run query boundaries

- Relationship detail no longer calls the full workflow projection. One scoped CTE query derives applied links/relationships directly, applies `(kind, stable_id)` keyset pagination and `LIMIT`, and scopes resource joins by organization/workspace.
- Base workflow rows retain only their bounded link/relationship details and exact counts; the prior private full `relationship_details` list was removed.
- Query telemetry proves the detail path issues one bounded CTE query and no audit-record query.
- Packet active-run lookup filters terminal lifecycle states in SQL and applies `LIMIT 1`; query telemetry asserts that boundary. Historical workflow links remain available because they are not the active-run lookup.

### Activity cursor, missing evidence, and scope hardening

- Activity now includes derived `missing_evidence` nodes for pending required checks.
- Verification-check joins include organization/workspace equality in addition to the check ID.
- Cursors require a valid timestamp, an allowlisted activity kind, and a full valid UUID before any dump/query. A forged UUID cursor returns the stable safe invalid-field message.
- Activity remains insertion-stable under the `(inserted_at, kind, UUID)` keyset.

### Explicit page semantics and option invariants

- Run activity, relationship detail, and each command-choice category now use explicit previous/next page labels rather than claiming accumulation while replacing results.
- Cursor stacks remount by run ID or normalized-event ID, so changing selection starts the new detail at `after: null`. Route coverage advances an overflow choice page, selects another run, and proves the new run query resets its cursor.
- Backend and frontend option validation now require a nonempty outcome list, unique outcome keys, a default key present in the list, and complete nonsentinel values. Duplicate choices or a missing default disable/exclude the option.

### RED and review evidence

- Secret-label RED: 0/1; `SECRET_TOKEN=must-not-leak` was the public title before the first review fix.
- Sentinel RED: 15/16; `  [REDACTED]  ` remained an observation option before the recursive filter.
- First second-review focused relationship boundary run: 4/5; telemetry included authorization reads, so the assertion was corrected to identify the single bounded CTE query specifically.
- First overflow UI run: 4/5; the fixture lacked the observation affordance, correctly preventing the form from rendering. Enabling the affordance made the paging/reset behavior executable.
- First covering run after active-run hardening: 43/44; filtering historical workflow links removed terminal linked-run status. The filter was restored there and retained only on the reviewed packet active-run `LIMIT 1` lookup.

### Final second-review gate

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test test/office_graph_web/operator_workflow_api_test.exs \
  test/office_graph/projections/operator_workflow_test.exs
pnpm --dir assets run relay:check
pnpm --dir assets run typecheck
pnpm --dir assets exec vitest run app/routes/operator/route.test.tsx \
  app/routes/packets/route.test.tsx --reporter=dot
pnpm --dir assets run build
openspec validate harden-project-quality --strict
git diff --check
```

Results: backend projection/API 44 passed (seed 43197); frontend operator/packet routes 62 passed; Relay validated 22 reader, 18 normalization, and 22 operation documents; all static, production-build, OpenSpec, formatting, and diff gates passed.

## Third Independent Review Remediation

Status: DONE

### Complete, tenant-safe relationship detail

- The relationship-detail CTE now derives linked packet versions from scoped applied graph resources, adds the latest linked packet plus its run history, and preserves `(kind, stable_id)` keyset pagination with `LIMIT`.
- Both graph-relationship endpoints are joined through organization/workspace-scoped `graph_items`; an unrelated tenant's packet, run, and graph resources cannot enter the result.
- Window aggregates provide exact base relationship counts without materializing every detail row. The base workflow projection caps linked run history at 21 and the detail path remains the bounded source of overflow rows.
- A regression with 21 same-version runs proves the first and second relationship pages cover every in-scope workflow link, exclude a foreign tenant's run, and report the exact 26 links and 3 relationships.

### Exact affordance availability and bounded root option reads

- Run-command availability is now derived from the same scoped, nonsentinel SQL predicates as each option page. Compact first-20 projection arrays no longer decide whether an affordance exists.
- The option page moved from nested `operatorRunState` resolution to the authenticated root `operatorRunCommandOptionPage`. Schema introspection proves the root field exists and the nested field does not.
- The operator UI issues one combined root operation and conditionally includes only option kinds whose bounded availability summary exceeds 20. Non-overflow kinds retain their compact typed options.
- A 21-check regression invalidates the first 20 labels and proves the sole valid row 21 still enables `record_execution_observation` and remains selectable from the root option page. Route coverage proves overflow paging and run-selection cursor reset.

### Result-aware activity and waiver completeness

- Derived missing-evidence activity now reports `failed_check` when a scoped failed verification result exists for that check; otherwise it reports `missing_accepted_evidence`.
- Waiver SQL rejects blank or redaction-sentinel execution and verification states before ordering and `LIMIT`, in addition to rejecting unusable check titles.
- The waiver regression places invalid rows before the valid row, proves only the valid choice is returned, then redacts the run execution state and proves the page is empty.

### Focused and final evidence

- Initial third-review focused gate: relationship overflow 1/1; row-21 availability, activity reason, and waiver filtering 2/2; operator route 39/39.
- The first complete projection run found one legacy presentation-state regression (27/28): exact option availability had accidentally changed a partially completed run from `awaiting_evidence` to `awaiting_execution`. Restoring the established child-count status transition while retaining exact SQL affordance gating produced 28/28.

Final Nix-shell gate:

```sh
mix format
mix compile --warnings-as-errors
mix test test/office_graph_web/operator_workflow_api_test.exs \
  test/office_graph/projections/operator_workflow_test.exs
pnpm --dir assets run relay:check
pnpm --dir assets run typecheck
pnpm --dir assets exec vitest run app/routes/operator/route.test.tsx \
  app/routes/packets/route.test.tsx --reporter=dot
pnpm --dir assets run build
openspec validate harden-project-quality --strict
mix format --check-formatted
git diff --check
```

Results: backend projection/API 45 passed (seed 493226); frontend operator/packet routes 62 passed; Relay validated 23 reader, 18 normalization, and 23 operation documents; TypeScript, warnings-as-errors compilation, production client/SSR build, strict OpenSpec, formatting, and diff checks passed.
