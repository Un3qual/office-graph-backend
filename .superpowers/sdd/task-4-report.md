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
