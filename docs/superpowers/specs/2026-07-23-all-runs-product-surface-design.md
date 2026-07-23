# All Runs Product Surface Design

date: 2026-07-23
status: approved
OpenSpec change: `add-all-runs-product-surface`

## Outcome

Ship the first dedicated run workspace at `/runs`. An operator using the
existing bootstrap session can page through authorized work runs, select one,
inspect its packet and verification state, review its bounded activity
timeline, and follow links to the existing packet and operator workspaces.

This is a bootstrap-only product milestone. Human identity and governance
administration remains intentionally deferred, so this change does not claim
the non-bootstrap feature-completion gate.

## Scope

The batch adds:

- an authorization-filtered, keyset-paginated run index projection;
- a Relay connection for run summaries;
- a `/runs` React route with list, selection, detail, empty, loading, paging,
  and safe error states;
- run detail backed by the existing `operatorRunState` projection and activity
  connection;
- links to the owning packet and the existing operator run workspace,
  including packet URL selection for the owning packet;
- an enabled `All Runs` product-navigation destination; and
- focused backend, API, Relay, route, architecture, and query-bound coverage.

The route is read-only. Operator and packet routes remain the only owners of
run, evidence, verification, approval, and conversation commands.

## Non-Goals

This batch does not add:

- browser authentication, logout, OIDC, SCIM, custom-role administration,
  group mappings, temporary grants, or governance settings;
- entity, report, integration-health, credential-health, or settings routes;
- a second run command implementation;
- a complete webhook-to-provider-follow-up acceptance test;
- new run persistence or migrations;
- direct model, provider, or external-write behavior; or
- a claim that Office Graph is feature complete.

## Backend Projection

Add a focused run-index projection under `OfficeGraph.Projections`. It owns
only the bounded list read and does not duplicate the existing detailed
`RunState` projection.

Each summary contains:

- run id, objective, aggregate state, execution state, verification state,
  insertion time, and a stable source watermark suitable for authoritative
  refresh;
- owning packet id, title, and state; and
- packet-version id, version number, lifecycle state, and objective.

The GraphQL layer derives an opaque packet Relay id from the projected packet
id for canonical product deep links. That Relay id is not an additional
projection field.

Rows are limited to the resolved session's organization and workspace. The
projection requires the existing skeleton-read capability and returns only
safe, already-modeled product fields. It uses keyset pagination ordered by
`inserted_at DESC, id DESC`; cursors encode those stable values. Inserts before
the current page do not duplicate or skip rows on forward pagination.

The read count remains constant as the number of runs grows: one
actor-authorized run-page read plus two actor-authorized, scope-filtered,
page-batched enrichment reads for packets and packet versions. Enrichment is
never loaded per row. Invalid cursors and limits return the same safe
validation shape used by existing operator and packet connections. Cross-tenant
ids never appear in the result.

The existing `operatorRunState` projection remains the detail source. Its
activity connection already covers observations, evidence, verification
results, agent executions, approval requests, context expansion requests,
proposals, and conversation messages without adding another timeline model.

## GraphQL Contract

Add an `operatorRuns(first:, after:)` forward Relay connection whose nodes are
`OperatorRunSummary` values. It follows the existing connection validation,
cursor, and error conventions used by `operatorWorkflowItems`.

The route reads:

1. `operatorRuns` for the current page; and
2. `operatorRunState(id:)` for the selected run, including its first bounded
   activity page.

Additional activity and run-list pages load through their existing Relay
connections. The change adds no mutation and no hidden compatibility query.

## Frontend Route

Add a route-owned package at `assets/app/routes/runs/` and register `/runs` in
both React Router and Phoenix's app-shell routes.

The route uses the shared product navigation but keeps all run-specific data,
formatting, and presentation inside the run package. It renders:

- a paginated run list with packet title, objective, and three state labels;
- route-local selected-run state represented by `?runId=<id>`;
- a detail summary for packet, packet version, aggregate state, execution
  state, verification state, required checks, evidence, and missing evidence;
- the bounded activity timeline with explicit load-more behavior;
- a link to `/packets?packetId=<id>` for packet history; and
- a link to `/operator?runId=<id>` for commands, approvals, and the linked
  agent conversation.

The existing packet route gains only the URL-selection behavior needed by that
deep link. It continues to own its current list, detail, paging, and mutation
behavior; this batch does not introduce a second packet projection or command
path.

The first visible run becomes the default only when `runId` is absent.
Selection changes update the URL and clear selection-scoped detail while the
authoritative replacement loads. Every present `runId` remains the requested
selection, including one absent from the current page or one that resolves as
invalid, missing, forbidden, or stale; those unavailable results use the safe
detail error state and do not reveal whether the run exists in another tenant.

`All Runs` becomes a real navigation link. `Entities` and `Reports` remain
disabled.

## Error And Recovery Behavior

- An empty authorized result renders a run-specific empty state and no stale
  detail.
- A list failure preserves the app shell and offers an explicit retry.
- A detail failure keeps the list visible, clears stale run detail, and offers
  a detail retry.
- A paging failure keeps the current page and selection intact.
- Invalid or stale URL selection never enables commands or synthesizes data.
- Relay re-reads authoritative run state after navigation or retry; the route
  does not maintain a second client-side source of truth.
- Public errors remain safe and do not expose SQL, authorization internals,
  raw model output, credentials, or provider payloads.

## File And Ownership Shape

Expected new frontend files remain under `assets/app/routes/runs/`:

- `route.tsx` for Relay loading and route-local selection;
- `data.ts` for GraphQL definitions;
- focused list, detail, timeline, and layout components;
- route tests split by reads, errors, and pagination where size warrants; and
- an architecture test enforcing import and stylesheet boundaries.

Use `assets/src/styles/runs.css` for route styling and import it from the
existing global stylesheet. Do not introduce Tailwind or a route-specific UI
framework.

On the backend, the list projection should be a small unit with one public
purpose. Existing run-detail and activity code stays in `RunState`; do not
create delegates, fallbacks, or wrapper modules without a distinct
responsibility.

## Verification

Backend coverage proves:

- tenant and workspace isolation;
- authorization failure;
- stable newest-first keyset pagination;
- invalid-cursor behavior;
- a constant query bound as list size grows;
- GraphQL connection shape and pagination; and
- unchanged detailed run-state behavior.

Frontend coverage proves:

- `All Runs` navigation is enabled while deferred destinations remain disabled;
- empty, populated, loading, list-error, detail-error, and paging-error states;
- default and URL-selected runs;
- selection and stale-detail clearing;
- list and activity pagination;
- packet and operator deep links;
- packet URL selection without changing packet command ownership;
- safe rendering of aggregate, execution, verification, evidence, and agent
  activity; and
- route/import/style architecture boundaries.

The final gate runs from the project Nix shell and includes strict OpenSpec
validation, backend tests, Relay generation checks, TypeScript typechecking,
Vitest, the production frontend build, `git diff --check`, and `mix verify`.

## Completion Criteria

The batch is complete when:

1. `/runs` is reachable from product navigation;
2. authorized runs page deterministically without tenant leakage or query
   fanout;
3. selecting a run renders current detailed run, verification, and activity
   state;
4. packet and operator deep links preserve the selected product context;
5. no run mutation path is duplicated;
6. deferred identity/governance and other product routes remain outside scope;
7. the OpenSpec change is synchronized and archived; and
8. the complete verification gate passes.
