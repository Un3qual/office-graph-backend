## ADDED Requirements

### Requirement: All Runs Is An Enabled Read-Only Product Route

Office Graph SHALL expose `/runs` as a React, Relay-backed, read-only product
route and SHALL enable `All Runs` as its navigation destination. `Entities` and
`Reports` SHALL remain disabled, and `/runs` SHALL NOT render, submit, or own a
run, evidence, verification, approval, conversation, or packet mutation. The
route SHALL use the existing shared styling and component conventions and SHALL
NOT introduce Tailwind, a Tailwind-dependent UI library, utility-class
conventions, or a route-specific UI framework.

#### Scenario: Operator opens all runs

- **WHEN** an authorized operator opens `/runs` or selects `All Runs` from
  product navigation
- **THEN** the Phoenix app shell MUST mount the route, navigation MUST identify
  `All Runs` as an enabled destination, and the route MUST load its list through
  `operatorRuns` rather than a JSON adapter or competing server-state cache

#### Scenario: Deferred navigation is visible

- **WHEN** product navigation renders beside the all-runs route
- **THEN** `Entities` and `Reports` MUST remain disabled and MUST NOT navigate
  to a synthesized product surface

#### Scenario: Route is inspected for command ownership

- **WHEN** implementation or tests inspect the all-runs route's GraphQL
  documents and interactions
- **THEN** they MUST find no mutation or duplicated command implementation, and
  commands, approvals, and linked conversations MUST remain reachable only via
  the existing operator workspace

#### Scenario: Route architecture is verified

- **WHEN** the all-runs route architecture test runs
- **THEN** it MUST enforce route-owned imports and the global `runs.css` style
  boundary, and MUST reject Tailwind, Tailwind-dependent UI libraries,
  utility-class conventions, and a route-specific UI framework

### Requirement: All Runs Uses The Shared Session And Canonical Route

Office Graph SHALL expose only canonical `/runs` for the all-runs product
surface. Its app shell and GraphQL reads SHALL consume the existing shared
`OfficeGraphWeb.RequestSession` resolution unchanged, including the
intentionally deferred bootstrap posture, and SHALL NOT add a route-specific
actor/session creation path, bootstrap fallback, alias, compatibility route, or
compatibility query.

#### Scenario: Operator requests the canonical route

- **WHEN** an operator requests `/runs`
- **THEN** Phoenix MUST serve the existing React app shell for that canonical
  path and MUST NOT expose an all-runs alias or compatibility route

#### Scenario: Route resolves a session

- **WHEN** the all-runs list or selected detail read resolves its request actor
- **THEN** it MUST use the existing shared `RequestSession` resolution without
  creating a route-local actor, session, bootstrap, or fallback

#### Scenario: Route contract is inspected

- **WHEN** route and GraphQL architecture coverage inspects all-runs entry
  points
- **THEN** it MUST find only the canonical `/runs` route and the documented
  `operatorRuns` and `operatorRunState` reads, with no alias or compatibility
  route/query

### Requirement: All Runs Preserves Authoritative List And Detail State

Office Graph SHALL render an explicit list, selection, detail, and bounded
activity state from route-owned Relay reads. It SHALL obtain selected-run
detail from `operatorRunState(id:)`, including that connection's first bounded
activity page, and SHALL treat the list and selected-detail reads as independent
recoverable boundaries.

#### Scenario: Authorized run list is empty

- **WHEN** `operatorRuns` returns no authorized edges
- **THEN** the route MUST render a run-specific empty state and MUST clear or
  omit selected-run detail

#### Scenario: List read fails

- **WHEN** the list read fails
- **THEN** the route MUST preserve the app shell, render a safe list error with
  an explicit retry, and MUST NOT expose raw GraphQL, authorization, transport,
  credential, provider, or model details

#### Scenario: Detail read fails

- **WHEN** `operatorRunState` is missing, forbidden, invalid, stale, or fails
- **THEN** the list MUST remain visible, stale selected-run detail MUST be
  cleared, and the route MUST render a safe detail error with an explicit
  detail retry that authoritatively re-reads the run

#### Scenario: List page read fails

- **WHEN** a later list-page read fails
- **THEN** the route MUST preserve the currently loaded page and current
  selection, render a safe paging error, and offer a retry without synthesizing
  a new selection

#### Scenario: Activity page is requested

- **WHEN** the selected run's activity connection has another page and the
  operator requests more activity
- **THEN** the route MUST request that Relay page explicitly, preserve existing
  activity while it loads, and render a safe retryable error if that page fails

### Requirement: All Runs Selection Is URL-Owned And Clears Stale Detail

Office Graph SHALL represent route-local run selection as `?runId=<id>`. It
SHALL choose the first visible run only when `runId` is absent. Every present
`runId` value SHALL remain the requested selection, including one absent from
the current page or one that is invalid, missing, forbidden, or stale, and the
route SHALL clear selection-scoped detail before its authoritative replacement
read resolves.

#### Scenario: URL selects a visible run

- **WHEN** `/runs?runId=<id>` names a run in the current authorized list page
- **THEN** the route MUST select that run, render detail from its authoritative
  run-state read, and MUST NOT replace it with the first row

#### Scenario: URL names a run outside the current page

- **WHEN** `/runs?runId=<id>` names an id that is absent from the current list
  page
- **THEN** the route MUST attempt the selected detail through
  `operatorRunState`, retain the URL selection while loading, and use the safe
  detail state if the result is missing or forbidden without revealing whether
  another tenant contains that id

#### Scenario: Present requested selection is unavailable

- **WHEN** `runId` is present but its authoritative detail read is invalid,
  missing, forbidden, or stale
- **THEN** the route MUST retain that requested URL value, preserve the list,
  clear stale detail, and render the safe detail error without falling back to
  the first or another visible run

#### Scenario: Operator changes selection

- **WHEN** an operator selects a different visible run
- **THEN** the route MUST update `runId` in the URL, clear the prior run's
  detail and activity immediately, and render only the replacement run's
  authoritative detail when it resolves

#### Scenario: URL lacks a selection

- **WHEN** a non-empty authorized list loads with no `runId` URL parameter
- **THEN** the route MUST select the first visible run and represent that
  selection in the URL

### Requirement: All Runs Preserves Product Context Through Deep Links

Office Graph SHALL show selected-run packet, packet-version, aggregate,
execution, verification, required-check, evidence, missing-evidence, and
bounded activity summaries, and SHALL link to existing context owners.

#### Scenario: Operator follows a packet link

- **WHEN** an operator follows the selected run's packet-history link
- **THEN** the route MUST navigate to `/packets?packetId=<owning-packet-id>`
  without copying packet reads or packet commands into `/runs`

#### Scenario: Operator follows a command link

- **WHEN** an operator needs run commands, approvals, or the linked agent
  conversation from a selected run
- **THEN** the route MUST navigate to `/operator?runId=<selected-run-id>` and
  MUST NOT enable those actions on `/runs`
