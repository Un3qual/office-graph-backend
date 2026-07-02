## MODIFIED Requirements

### Requirement: Console Presents Workflow Inbox And Item Detail
The operator console SHALL let an operator inspect the actionable workflow inbox
and selected item detail through the GraphQL product frontend path.

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

#### Scenario: Product frontend transport is GraphQL
- **WHEN** the Phoenix-served `/operator` app shell mounts the React console
  without a test-only GraphQL fetcher
- **THEN** the console MUST read the operator workflow through the GraphQL
  product projection path and MUST NOT construct or import a frontend JSON API
  adapter for operator workflow reads

#### Scenario: Item detail is selected
- **WHEN** an operator selects an inbox row
- **THEN** the console MUST fetch or reuse the selected item detail and show its
  typed identity, source context, proposed-change status, affected graph links,
  audit or revision traces, and safe next actions

#### Scenario: Item detail cannot be loaded
- **WHEN** item detail loading fails because the item is missing, unauthorized,
  stale, invalid, or the network request fails
- **THEN** the console MUST preserve the current workflow context and show an
  explicit error or blocker state instead of dropping into an ambiguous blank
  detail pane

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
