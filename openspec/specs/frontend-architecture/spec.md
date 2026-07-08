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

### Requirement: Operator Frontend Can Be Rebuilt From The Demo
Office Graph SHALL treat the first operator console implementation as a
replaceable vertical slice rather than a compatibility boundary for future
frontend architecture.

#### Scenario: Operator frontend foundation is reset

- **WHEN** a change rebuilds the operator frontend foundation before additional
  operator behavior is added
- **THEN** the implementation MAY replace the demo operator-workflow module,
  demo-only props, JSON frontend adapter, and JSON parity frontend tests,
  provided the `/operator` route still mounts a React product workbench over the
  accepted backend read contract

#### Scenario: Demo code conflicts with frontend architecture

- **WHEN** preserving demo-era file names, adapter split points, or component
  structure would keep transport, query, view-model, or layout responsibilities
  tangled
- **THEN** the implementation MUST prefer the accepted frontend architecture over
  demo compatibility

### Requirement: Operator Server State Uses Relay
Office Graph SHALL use Relay for operator workflow server state.

#### Scenario: Operator route reads workflow data

- **WHEN** the operator React route reads inbox, selected item detail, packet
  readiness, run state, or verification state
- **THEN** those reads MUST go through route-owned Relay data code with stable
  operation ownership, generated Relay types, and explicit loading, empty,
  error, and loaded states

#### Scenario: Operator UI needs local interaction state

- **WHEN** the operator UI tracks selected row, selected tab, expanded panel, or
  transient control state
- **THEN** the state MUST remain local React state or an accepted URL parameter
  and MUST NOT be hidden in the server-state cache as durable product state

### Requirement: Feature Data Access

Office Graph SHALL route product GraphQL data access through route-owned Relay
data and Relay fragments. Typed feature clients are reserved for non-GraphQL
integrations or other accepted non-product-GraphQL data paths, and components
MUST NOT issue direct ad hoc fetch calls.

#### Scenario: Feature reads backend data

- **WHEN** a feature route or panel reads Office Graph backend data
- **THEN** product GraphQL data MUST flow through Relay route data or Relay
  fragment data, independent of raw transport response shape or future
  socket/live invalidation payloads

#### Scenario: Old adapter has no current caller

- **WHEN** a feature moves to the current product API path and an old adapter no
  longer has a current caller
- **THEN** the implementation MUST delete the old adapter and rewrite tests
  around the current data path instead of preserving adapter compatibility

#### Scenario: Product frontend has GraphQL coverage

- **WHEN** the React product frontend has a GraphQL read for a feature route
- **THEN** the product UI MUST use the GraphQL path directly through Relay and
  MUST NOT keep a frontend JSON adapter as a compatibility requirement

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
- **THEN** the frontend MUST use Relay for loading, deduplication,
  cancellation, stale markers, refetching, and error state

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

#### Scenario: Operator frontend is rebuilt

- **WHEN** the operator frontend foundation is rebuilt from the demo
- **THEN** route composition, query hooks, GraphQL transport/query documents,
  response mappers, derived workflow helpers, layout components, panels, and
  pure presentation helpers MUST live in focused modules with no component
  importing JSON API client code
