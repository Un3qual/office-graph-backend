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
