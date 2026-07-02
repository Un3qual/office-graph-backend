# frontend-architecture Specification

## Purpose
Define the React frontend structure, data-loading, shared UI, and verification
rules for Office Graph product screens.
## Requirements
### Requirement: Frontend Foundation Before Additional Product Routes

Office Graph SHALL establish a React frontend architecture foundation before
adding additional product routes beyond the first operator console.

#### Scenario: New product route is proposed

- **WHEN** a change proposes a new product route, screen family, or navigation
  area
- **THEN** the change MUST use accepted route ownership, feature module,
  data hook, component primitive, styling token, and verification conventions

#### Scenario: Navigation item has no implemented route

- **WHEN** the UI displays navigation for a product area
- **THEN** the area MUST either route to implemented behavior or be rendered as
  a non-interactive unavailable item backed by an accepted product decision

### Requirement: Shared UI Primitives And Tokens

Office Graph SHALL keep shared visual primitives separate from workflow-specific
status and domain mapping logic.

#### Scenario: Frontend tooling is configured

- **WHEN** JavaScript package, build, typecheck, or test tooling is configured
- **THEN** package metadata, lockfiles, Vite config, TypeScript config, Vitest
  setup, and frontend scripts MUST live under `assets` and MUST use pnpm

#### Scenario: Shared component is added

- **WHEN** a shared UI component such as a badge, button, panel, pane header,
  nav rail, text field, empty state, or layout primitive is added
- **THEN** the component MUST accept generic presentation props and MUST NOT
  embed operator-workflow status, graph type, run state, verification, or
  domain-specific mapping logic

#### Scenario: Design token is used

- **WHEN** colors, spacing, typography, radii, borders, or layout dimensions are
  reused across product UI
- **THEN** the values MUST come from a shared token source that can be consumed
  by CSS and TypeScript without duplicating magic values in feature components

### Requirement: Feature Data Hooks

Office Graph SHALL route frontend data access through feature-owned data hooks
or clients rather than direct ad hoc fetch calls inside components.

#### Scenario: Feature reads backend data

- **WHEN** a feature route or panel reads Office Graph backend data
- **THEN** the feature MUST call a typed hook or client that returns a frontend
  typed UI data independent of raw GraphQL response shape or future socket/live
  invalidation payloads

#### Scenario: Old adapter has no current caller

- **WHEN** a feature moves to the current product API path and an old adapter no
  longer has a current caller
- **THEN** the implementation MUST delete the old adapter and rewrite tests
  around the current data path instead of keeping old adapter behavior

### Requirement: Product Frontend Uses Current API Path
Office Graph SHALL keep product frontend code on the current accepted API path.

#### Scenario: Product UI reads operator workflow data
- **WHEN** the React product UI reads operator workflow data
- **THEN** it MUST use the current GraphQL product path unless an accepted
  OpenSpec change names a current reason for another path

#### Scenario: Demo compatibility code remains
- **WHEN** demo-era frontend code remains after a product path replaces it
- **THEN** the implementation MUST delete it or document the current workflow
  that still uses it

### Requirement: Server State Is Managed Deliberately

Office Graph SHALL separate server state, URL state, and local interaction
state in the React app.

#### Scenario: Multiple views share backend data

- **WHEN** backend projection data is read by multiple routes, panels, or
  realtime invalidation paths
- **THEN** the frontend MUST use an explicit query/cache layer such as TanStack
  Query for loading, deduplication, cancellation, stale markers, refetching,
  and error state

#### Scenario: Local UI selection is needed

- **WHEN** UI state represents selection, tabs, filters, or transient control
  state
- **THEN** the state MUST live in React local state or URL parameters unless an
  accepted design identifies cross-route client-only workflow state

### Requirement: App Shell And Frontend Verification

Office Graph SHALL verify that the Phoenix-served React app shell references
build artifacts that exist and can execute.

#### Scenario: Frontend verification runs

- **WHEN** frontend verification runs locally or in CI
- **THEN** it MUST use project-local pnpm dependencies under `assets`, run
  typecheck, run unit or component tests, build the app, and verify that the app
  shell references generated asset files present under the Phoenix static path

#### Scenario: App shell route is tested

- **WHEN** the `/operator` app shell route is tested
- **THEN** the test MUST fail if the referenced JavaScript or CSS asset path
  cannot be produced by the frontend build

### Requirement: Feature Components Stay Decomposed

Office Graph SHALL keep feature route containers, data hooks, layout
components, panels, and pure presentation helpers in separate modules once a
feature grows beyond a narrow screen.

#### Scenario: Operator workflow UI is refactored

- **WHEN** the operator workflow UI is touched for non-trivial behavior
- **THEN** the implementation MUST split route/container state, projection
  hooks, workbench layout, inbox list, item detail, readiness panel, run panel,
  and verification panel into focused modules before adding more screen
  behavior
