## Context

The existing packet and operator surfaces can show a detailed run after an
operator has already found its packet or workflow item. They do not provide a
dedicated, bounded way to discover authorized runs. `operatorRunState` already
owns detailed run, verification, and bounded activity reads; this change adds
only the missing list projection and a read-only route that composes that
existing detail source.

The initial milestone uses the existing bootstrap session. Identity and
governance administration remain deferred and are not a prerequisite or an
outcome of this change.

The server already resolves product-read actors through the shared
`OfficeGraphWeb.RequestSession` boundary. This change consumes that resolution
unchanged, including its intentionally deferred bootstrap posture; neither the
`/runs` route nor its GraphQL reads create an actor, session, or fallback of
their own.

## Goals / Non-Goals

**Goals:**

- Provide an authorized, organization- and workspace-scoped, newest-first
  keyset index of safe run summaries with a stable forward-pagination contract
  and constant query bound.
- Make `/runs` a route-owned, Relay-backed, read-only workspace with explicit
  loading, empty, error, retry, selection, pagination, and stale-detail
  behavior.
- Preserve product context with packet and operator deep links, including
  packet selection through `?packetId=<id>`.
- Keep commands in their current packet and operator owners.

**Non-Goals:**

- Authentication, logout, OIDC, SCIM, custom roles, group mappings, temporary
  grants, governance settings, or a feature-completeness claim.
- New run persistence, migrations, model/provider/external-write behavior, a
  second timeline model, a compatibility query, or any run mutation.
- New entity, report, integration-health, credential-health, or settings
  routes; `Entities` and `Reports` remain disabled.
- Tailwind, Tailwind-dependent component libraries, utility-class conventions,
  or a route-specific UI framework. The route uses the existing shared UI and
  stylesheet conventions, with architecture-test coverage.
- A `/runs` alias or compatibility route, or a route-specific actor/session
  resolver or bootstrap fallback.

## Decisions

### Add a focused run-index projection

`OfficeGraph.Projections` will own a small list read whose safe output is:
run id, objective, aggregate state, execution state, verification state,
insertion time, and source watermark; packet id, title, and state; and
packet-version id, version number, lifecycle state, and objective. The GraphQL
layer derives an opaque packet Relay id from the projected packet id for
canonical product deep links; that Relay id is not an additional projection
field. The projection resolves the existing session scope and skeleton-read
capability before reading, filters every read by organization and workspace,
and uses one actor-authorized run-page read plus two actor-authorized,
page-batched enrichment reads for packets and packet versions.

The projection orders by `inserted_at DESC, id DESC` and encodes those two
values in opaque cursors. This makes the ordering total and keeps a forward
page stable when newer rows are inserted before the current page. Invalid
cursors and limits use the current safe connection-validation shape.

Alternative considered: derive summaries from `operatorRunState` one run at a
time. Rejected because it creates query fanout and duplicates detail assembly.

### Extend GraphQL with a single forward Relay connection

`operatorRuns(first:, after:)` exposes `OperatorRunSummary` nodes and follows
the established `operatorWorkflowItems` connection validation and error
conventions. Its resolver uses the existing shared `RequestSession` resolution
unchanged. It is a read-only addition; no mutation, hidden compatibility query,
or route-specific session fallback is introduced.

Alternative considered: have the route combine packet rows with per-run reads.
Rejected because it cannot represent all runs or preserve the fixed query bound.

### Compose the route from the list and existing detail source

The route-owned `assets/app/routes/runs/` package reads `operatorRuns` for its
list and `operatorRunState(id:)` for the selected run, requesting the first
bounded activity page. Additional list and activity pages use their respective
Relay connections. The route owns `?runId=<id>` selection and clears
selection-scoped detail before a changed selection's authoritative read settles.

The first visible run is selected only when `runId` is absent. Every present
`runId`, including one outside the current list or one that resolves as
invalid, missing, forbidden, or stale, remains the requested selection and is
read through `operatorRunState`; an unavailable result renders the safe detail
state without revealing cross-scope existence or falling back to another row.
The route has no mutations;
operator links direct users to `/operator?runId=<id>` for commands and packet
links direct users to `/packets?packetId=<id>`.

The canonical route is `/runs`; it has no alias or compatibility route/query.
The route uses the existing shared UI conventions and global `runs.css` import,
not Tailwind or a route-specific UI framework. An architecture test enforces
the route/import/style boundary.

Alternative considered: retain detail in a route-level cache after a selection
change. Rejected because a second client-side source can display stale
verification or activity data.

### Limit the packet change to URL-owned selection

The existing packet route recognizes `packetId` from its URL, represents a
user's packet selection in that URL, and loads safe selected-packet detail as
needed. Its existing list, detail, paging, and mutation paths remain the only
packet workspace behavior. A missing, unauthorized, or stale URL selection
must clear stale detail and present a safe state. The first visible packet is
the default only when `packetId` is absent; every present value remains the
requested selection and is authoritatively resolved, never silently replaced
by a list row. This narrow URL behavior uses the existing shared session
resolution unchanged.

Alternative considered: copy packet detail or commands into `/runs`. Rejected
because the all-runs route is a reader and the packet workspace already owns
those responsibilities.

## Risks / Trade-offs

- [A cross-scope or unauthorized id reveals existence] → Resolve session scope
  and authorization before the list and detail reads, and map forbidden and
  missing detail results to one safe route state.
- [Cursor implementation skips or duplicates rows during inserts] → Use the
  total `(inserted_at DESC, id DESC)` keyset and cover forward-pagination
  stability with tests.
- [Route reads grow per row] → Keep one actor-authorized run-page read plus two
  actor-authorized, scope-filtered, page-batched enrichment reads, prohibit
  per-row enrichment loading, and add a query-count regression test at
  different list sizes.
- [Selection changes render stale verification information] → Reset the
  detail boundary by selected id before Relay resolves the replacement.
- [New UI grows a second command surface] → Keep all-runs GraphQL documents
  read-only and test deep links to existing packet and operator owners.
- [A present URL selection silently changes context] → Default only for an
  absent parameter; retain every present `runId` or `packetId` until its
  authoritative detail read resolves to loaded or safe unavailable.
- [A route creates a divergent authorization posture] → Route all new reads
  through the existing shared `RequestSession` boundary and cover that no
  route-specific actor, session, or fallback is introduced.

## Migration Plan

1. Ship the additive projection and GraphQL connection behind the existing
   bootstrap-session authorization path; no data migration is required.
2. Ship `/runs`, app-shell registration, enabled navigation, and the narrow
   packet URL-selection behavior together so deep links have a destination.
3. Roll back by removing the route and connection from the release; no stored
   state or command semantics need reversal.

Every final verification command, including strict OpenSpec validation,
backend tests, Relay generation checks, TypeScript typechecking, Vitest, the
production frontend build, `git diff --check`, and `mix verify`, runs through
the project Nix flake.

## Open Questions

None. Identity and governance administration are explicitly deferred rather
than open requirements for this milestone.
