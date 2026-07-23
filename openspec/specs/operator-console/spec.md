# operator-console Specification

## Purpose
Define the first Office Graph product UI for operators working from
manual intake through packet readiness, run state, evidence, and verification.

## Requirements

### Requirement: Operator Console Uses React
Office Graph SHALL expose the first product UI as a React operator console
served by the Phoenix application without using Phoenix LiveView for product
workflow screens.

#### Scenario: Operator opens the console
- **WHEN** an operator opens the console route in a browser
- **THEN** Phoenix MUST return an app shell that mounts the React console,
  loads compiled frontend assets, and does not require a LiveView session for
  product UI behavior

#### Scenario: Frontend assets are unavailable
- **WHEN** the app shell or compiled frontend assets cannot be served in a
  local or release environment
- **THEN** the failure MUST be explicit through the HTTP response, build
  output, or verification check rather than silently serving a blank product UI

### Requirement: Console Presents Workflow Inbox And Item Detail
The operator console SHALL let an operator inspect the actionable workflow inbox
and selected item detail through the product GraphQL data path.

#### Scenario: Inbox rows are available
- **WHEN** the GraphQL operator workflow inbox projection returns one or more
  rows
- **THEN** the console MUST show scannable rows with source summary, workflow
  status, actionability state, reason codes or blockers, allowed next actions,
  source watermark, and a clear selected-row state

#### Scenario: Inbox is empty
- **WHEN** the GraphQL operator workflow inbox projection returns no rows
- **THEN** the console MUST show an empty state that explains there are no
  operator workflow items without presenting fake work or enabled workflow
  commands

#### Scenario: Default transport is GraphQL
- **WHEN** the Phoenix-served `/operator` app shell mounts the React console
  without an injected test client
- **THEN** the console MUST read the operator workflow through the GraphQL
  product data path rather than the old JSON adapter

#### Scenario: Initial selected item reuses inbox detail
- **WHEN** the inbox projection already includes the selected row's item detail
  fields
- **THEN** the console MUST use that row as the initial selected item detail
  without immediately issuing a duplicate item-detail read for the same
  normalized event

#### Scenario: Initial packet readiness reuses selected row links
- **WHEN** the selected inbox row is already ready for packet preparation and
  includes source graph links plus required verification-check links
- **THEN** the console MUST derive the initial packet-readiness panel from the
  loaded row as prepare-packet context, without immediately issuing a duplicate
  packet-readiness read for the same graph and verification-check ids and
  without claiming the packet can already be created

#### Scenario: Item detail is selected
- **WHEN** an operator selects an inbox row whose detail is not already loaded
  or whose source watermark requires refresh
- **THEN** the console MUST fetch or reuse the selected item detail and show its
  typed identity, source context, proposed-change status, affected graph links,
  audit or revision traces, and safe next actions

#### Scenario: Item detail cannot be loaded
- **WHEN** item detail loading fails because the item is missing, unauthorized,
  stale, invalid, or the network request fails
- **THEN** the console MUST preserve the current workflow context and show an
  explicit error or blocker state instead of dropping into an ambiguous blank
  detail pane

### Requirement: Console Guides Packet Readiness And Run State
The operator console SHALL guide an operator from triaged graph work toward a
packet-backed work run without bypassing backend readiness rules.

#### Scenario: Packet is ready
- **WHEN** the packet readiness endpoint reports that a selected item has
  ready packet inputs
- **THEN** the console MUST show the objective, source references, context
  summary, success criteria, autonomy posture, required checks, and enabled
  start-work action for the ready packet state

#### Scenario: Packet is blocked
- **WHEN** the packet readiness endpoint reports missing context, decisions,
  success criteria, checks, authorization, scope, or autonomy posture
- **THEN** the console MUST show the packet as not ready, list the blocking
  reason codes, and keep run-start actions disabled

#### Scenario: Run state is available
- **WHEN** a selected item is linked to a packet-backed work run
- **THEN** the console MUST show the run lifecycle state, required checks,
  observations or evidence candidates, freshness or trust basis, and current
  execution or evidence needs

### Requirement: Console Closes The Verification Loop
The operator console SHALL make verification status explicit before work is
presented as complete.

#### Scenario: Verification passes
- **WHEN** the verification outcome endpoint reports accepted evidence for all
  required checks
- **THEN** the console MUST present the item as verified with links or labels
  for accepted evidence, operation correlation, actor or policy basis, and
  affected graph items

#### Scenario: Verification is incomplete or failed
- **WHEN** evidence is missing, stale, failed, unauthorized, unrelated, or
  rejected by policy
- **THEN** the console MUST present the item as unverified or failed with the
  specific missing-evidence, stale-evidence, failed-check, authorization, or
  policy reason codes

### Requirement: Console Keeps Deferred Surfaces Out
Office Graph SHALL keep the first operator console focused on the manual intake
to verification loop and defer broader platform behavior.

#### Scenario: Deferred behavior appears during console implementation
- **WHEN** implementation encounters full graph canvas editing, workflow
  builder behavior, collaborative rich text, provider webhook ingestion, full
  agent runtime execution, generic ordered placement, mobile-specific UI, or
  broad dashboard polish
- **THEN** the behavior MUST be deferred to a later accepted OpenSpec change
  unless it is strictly required for the operator console to complete the
  manual intake to verification workflow

### Requirement: Frontend Verification Is Reproducible
Office Graph SHALL provide reproducible frontend build and test verification
for the operator console.

#### Scenario: Developer verifies the frontend
- **WHEN** a developer runs the documented frontend verification command from
  inside the project Nix shell
- **THEN** the command MUST build the React assets or type-check them as
  appropriate, run focused frontend tests, and fail on broken app-shell
  loading, GraphQL projection loading, server-state handling, or core console
  rendering regressions

#### Scenario: Phoenix serves the app shell
- **WHEN** backend tests exercise the console route
- **THEN** the tests MUST verify that Phoenix returns the React app shell and
  required asset references without replacing the product UI with a LiveView
  page

### Requirement: Operator Dependent Relay Reads Preserve Workspace Context
Office Graph SHALL isolate dependent operator Relay reads so readiness or run
state loading and failure do not discard still-valid inbox and item context.

#### Scenario: Readiness validation is requested
- **WHEN** an operator explicitly validates readiness derived from the selected
  inbox item
- **THEN** the validation read MUST run through Relay under a readiness-panel
  loading boundary while the selected inbox row and item detail remain visible

#### Scenario: Readiness validation fails
- **WHEN** the readiness validation Relay read fails
- **THEN** the readiness panel MUST show a safe validation error without
  exposing raw backend details or replacing the surrounding operator workspace

#### Scenario: Selected item has a linked run
- **WHEN** the selected operator item resolves to a run id
- **THEN** run and verification data MUST render from a Relay query child under
  a panel-scoped loading and error boundary

#### Scenario: Run state read fails
- **WHEN** the linked run Relay read fails
- **THEN** the run and verification area MUST show safe unavailable state while
  the inbox, selected item detail, and readiness context remain visible

#### Scenario: Operator selection changes
- **WHEN** an operator selects a different inbox item
- **THEN** dependent readiness-validation and run-state boundaries MUST reset
  to the new selected identity and MUST NOT render results or errors retained
  from the prior item

### Requirement: Operator Console Executes Allowed Workflow Commands

The operator console SHALL render and execute enabled command affordances for
manual intake, proposal application, packet preparation, run progress,
evidence, and verification.

#### Scenario: Operator submits or advances work

- **WHEN** the current projection exposes an enabled command affordance
- **THEN** the console MUST render its route-owned form or action, submit the
  matching Relay mutation, disable duplicate submission while pending, and
  refresh the affected authoritative reads after success

#### Scenario: Command is disabled or hidden

- **WHEN** an affordance is disabled, hidden, or redacted
- **THEN** the console MUST NOT synthesize an enabled action and MUST preserve
  safe blocker or policy copy without revealing hidden targets

### Requirement: Operator Command Feedback Preserves Context

The operator console SHALL keep still-valid workflow context visible while a
command is pending or fails.

#### Scenario: Command validation fails

- **WHEN** a Relay mutation returns field errors
- **THEN** the owning form MUST show safe field feedback while preserving the
  inbox, selection, packet, and run context

#### Scenario: Command conflicts with durable state

- **WHEN** a command returns an idempotency or stale-state conflict
- **THEN** the console MUST show a safe conflict message, refresh the affected
  authoritative query, and require an explicit retry

### Requirement: Operator Console Provides A Focused Run Agent Surface
Office Graph SHALL add one run-aware conversation and agent-control surface to
the existing operator workflow.

#### Scenario: Operator views agent execution
- **WHEN** an authorized operator selects a run with agent activity
- **THEN** the UI MUST show bounded execution status, conversation messages,
  safe context rationale, pending approvals/expansions, failures, retries, and
  proposal/evidence outputs

#### Scenario: Operator invokes or cancels agent
- **WHEN** an allowed invocation or cancellation affordance is active
- **THEN** the UI MUST submit the narrow Relay command, disable only its owning
  action while pending, and authoritatively refresh execution and run state

#### Scenario: Operator resolves request
- **WHEN** an allowed approval or context-expansion request is selected
- **THEN** the UI MUST display the exact bounded request, collect required
  reason/scope data, submit a versioned resolution, and handle stale conflicts by
  refetching

### Requirement: Agent Surface Is Not General Chat Or Administration
Office Graph SHALL keep the first surface scoped to the selected run and graph
item and SHALL expose no generic agent-definition, credential, role, or
cross-workspace chat administration.

#### Scenario: Operator navigates outside selected run
- **WHEN** the selected run or graph item changes
- **THEN** drafts and subscriptions MUST bind to the new authorized context and
  MUST NOT carry prior restricted conversation or approval state across it

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
