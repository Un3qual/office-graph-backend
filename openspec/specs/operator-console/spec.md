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
