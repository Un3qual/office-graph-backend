## MODIFIED Requirements

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
  the AshGraphql-generated `listWorkRuns` Relay connection rather than a manual
  GraphQL projection, JSON adapter, or competing server-state cache

#### Scenario: Deferred navigation is visible

- **WHEN** product navigation renders beside the all-runs route
- **THEN** `Entities` and `Reports` MUST remain disabled and MUST NOT navigate
  to a synthesized product route

#### Scenario: Route is inspected for command ownership

- **WHEN** implementation or tests inspect the all-runs route's GraphQL
  documents and interactions
- **THEN** they MUST find no mutation or duplicated command implementation, and
  commands, approvals, and linked conversations MUST remain reachable only via
  the existing operator workspace

#### Scenario: Route architecture is verified

- **WHEN** the all-runs route architecture test runs
- **THEN** it MUST inspect the actual route registration, imports, stylesheet,
  generated artifact location, and dependency manifest and MUST reject
  forbidden route ownership, Tailwind, and route-specific UI dependencies

### Requirement: All Runs Uses The Shared Session And Canonical Route

Office Graph SHALL expose only canonical `/runs` for the all-runs product
surface. Its app shell and GraphQL reads SHALL consume the existing shared
authenticated actor context, including the intentionally deferred bootstrap
posture, and SHALL NOT add a route-specific actor/session creation path,
bootstrap fallback, alias, compatibility route, or compatibility query.

#### Scenario: Operator requests the canonical route

- **WHEN** an operator requests `/runs`
- **THEN** Phoenix MUST serve the existing React app shell for that canonical
  path and MUST NOT expose an all-runs alias or compatibility route

#### Scenario: Route resolves a session

- **WHEN** the generated all-runs list or selected mixed-detail read resolves
  its request actor
- **THEN** it MUST consume the actor loaded by the shared GraphQL pipeline
  without creating a route-local actor, session, bootstrap, or fallback

#### Scenario: Route contract is inspected

- **WHEN** route and GraphQL architecture coverage inspects all-runs entry
  points
- **THEN** it MUST find only the canonical `/runs` route and the documented
  generated `listWorkRuns` and mixed-projection `operatorRunState` reads, with
  no alias or compatibility route/query

### Requirement: All Runs Preserves Authoritative List And Detail State

Office Graph SHALL render an explicit list, selection, detail, and bounded
activity state from route-owned Relay reads. It SHALL obtain its list from the
generated `listWorkRuns` connection and selected-run detail from the
`operatorRunState(id:)` mixed projection, including that projection's first
bounded activity page. It SHALL treat the list and selected-detail reads as
independent recoverable boundaries.

#### Scenario: Authorized run list is empty

- **WHEN** `listWorkRuns` returns no authorized edges
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
- **THEN** Relay pagination MUST append that page, preserve existing activity
  while it loads, and expose a safe retry if the page fails
