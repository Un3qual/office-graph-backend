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

## Decisions

### Add a focused run-index projection

`OfficeGraph.Projections` will own a small list read for safe run-summary
fields: run, packet, and packet-version identities and labels; objective;
aggregate, execution, and verification states; insertion time; and a source
watermark. It resolves the existing session scope and skeleton-read capability
before reading, filters by organization and workspace, and joins packet labels
in the bounded query.

The projection orders by `inserted_at DESC, id DESC` and encodes those two
values in opaque cursors. This makes the ordering total and keeps a forward
page stable when newer rows are inserted before the current page. Invalid
cursors and limits use the current safe connection-validation shape.

Alternative considered: derive summaries from `operatorRunState` one run at a
time. Rejected because it creates query fanout and duplicates detail assembly.

### Extend GraphQL with a single forward Relay connection

`operatorRuns(first:, after:)` exposes `OperatorRunSummary` nodes and follows
the established `operatorWorkflowItems` connection validation and error
conventions. It is a read-only addition; no mutation or hidden compatibility
query is introduced.

Alternative considered: have the route combine packet rows with per-run reads.
Rejected because it cannot represent all runs or preserve the fixed query bound.

### Compose the route from the list and existing detail source

The route-owned `assets/app/routes/runs/` package reads `operatorRuns` for its
list and `operatorRunState(id:)` for the selected run, requesting the first
bounded activity page. Additional list and activity pages use their respective
Relay connections. The route owns `?runId=<id>` selection and clears
selection-scoped detail before a changed selection's authoritative read settles.

The first visible run is selected only when the URL does not name a valid
visible run. A URL id outside the current list is read through
`operatorRunState`; missing or forbidden results render the same safe detail
state without revealing cross-scope existence. The route has no mutations;
operator links direct users to `/operator?runId=<id>` for commands and packet
links direct users to `/packets?packetId=<id>`.

Alternative considered: retain detail in a route-level cache after a selection
change. Rejected because a second client-side source can display stale
verification or activity data.

### Limit the packet change to URL-owned selection

The existing packet route recognizes `packetId` from its URL, represents a
user's packet selection in that URL, and loads safe selected-packet detail as
needed. Its existing list, detail, paging, and mutation paths remain the only
packet workspace behavior. A missing, unauthorized, or stale URL selection
must clear stale detail and present a safe state.

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
- [Route reads grow per row] → Join bounded labels in the index query and add a
  query-count regression test at different list sizes.
- [Selection changes render stale verification information] → Reset the
  detail boundary by selected id before Relay resolves the replacement.
- [New UI grows a second command surface] → Keep all-runs GraphQL documents
  read-only and test deep links to existing packet and operator owners.

## Migration Plan

1. Ship the additive projection and GraphQL connection behind the existing
   bootstrap-session authorization path; no data migration is required.
2. Ship `/runs`, app-shell registration, enabled navigation, and the narrow
   packet URL-selection behavior together so deep links have a destination.
3. Roll back by removing the route and connection from the release; no stored
   state or command semantics need reversal.

## Open Questions

None. Identity and governance administration are explicitly deferred rather
than open requirements for this milestone.
