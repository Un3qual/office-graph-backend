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

### Requirement: React Router Framework Mode Route Ownership

Office Graph SHALL use React Router Framework Mode conventions as the product
frontend route ownership model before adding more product routes.

#### Scenario: Frontend platform is implemented

- **WHEN** the frontend platform implementation begins
- **THEN** it MUST introduce React Router Framework Mode entry files under
  `assets`, including a root route and route configuration, and MUST keep route
  behavior in route modules rather than a manually composed single-route app
  shell

#### Scenario: Product route is added

- **WHEN** a product screen family such as operator, packets, runs,
  verification, settings, or integrations is added
- **THEN** the route MUST own its route module, route-specific components,
  route data contract, route tests, and route state rules in one route-owned
  folder unless repeated real code proves a smaller shared boundary

#### Scenario: Phoenix serves the React app

- **WHEN** Phoenix serves the product frontend
- **THEN** it MUST serve the React Router Framework Mode build as a
  Phoenix-served SPA unless a later accepted change explicitly adds SSR or a
  different rendering strategy

### Requirement: Frontend Layout Stays Route-First And Shallow

Office Graph SHALL keep the first frontend platform layout conventional and
route-first instead of adding abstract platform or domain layers before the app
has enough real screens to justify them.

#### Scenario: Frontend folders are introduced

- **WHEN** the frontend platform creates or reorganizes top-level frontend
  folders
- **THEN** the default layout MUST be limited to React Router app files,
  route-owned folders, shallow shared UI, styles, and the chosen GraphQL client
  setup, and MUST NOT introduce `platform`, `domains`, `shared/design`, or
  `shared/ui` layers without a concrete repeated-code need

#### Scenario: Shared UI component is introduced

- **WHEN** a reusable UI component is added outside a route
- **THEN** it MUST stay generic, shallow, and product-vocabulary-free, while
  route or product-specific mapping remains inside the owning route folder

#### Scenario: App providers are introduced

- **WHEN** the frontend platform adds top-level React providers
- **THEN** the file SHOULD use a clear name such as `AppProviders.tsx` and MUST
  contain only React application wrappers such as the Relay provider, router
  integration, session context, feature flags, or app config; it MUST NOT be
  confused with external integration provider adapters

### Requirement: Product GraphQL Client Model Uses Relay

Office Graph SHALL use Relay as the product GraphQL server-state model for the
frontend platform.

#### Scenario: Frontend platform implementation starts

- **WHEN** the frontend platform implementation starts
- **THEN** product GraphQL server state MUST use Relay and MUST document any
  schema compatibility work needed for Office Graph's projection,
  authorization, pagination, realtime, and testing requirements

#### Scenario: Product route consumes GraphQL data

- **WHEN** a product route consumes GraphQL data
- **THEN** route data and components MUST follow Relay conventions for
  environment setup, route/root queries, fragments, pagination, generated
  types, Node IDs, and store updates instead of adding a parallel homemade
  view-model or TanStack Query cache layer for the same GraphQL data

#### Scenario: Product GraphQL data is cached

- **WHEN** a product route reads GraphQL server state
- **THEN** it MUST use Relay and MUST NOT run TanStack Query as a competing
  cache for the same product GraphQL records

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

### Requirement: Available Product Navigation Uses Route Links

Office Graph SHALL render implemented product destinations as accessible
React Router links while keeping unavailable destinations explicitly disabled.

#### Scenario: Product destination is implemented

- **WHEN** a navigation item points to an implemented product route
- **THEN** the shared navigation primitive MUST render an accessible
  client-side route link and MUST derive its current-page state from React
  Router rather than a route-specific hard-coded active flag

#### Scenario: Product destination is unavailable

- **WHEN** a navigation item represents a product destination that is not yet
  implemented
- **THEN** the shared navigation primitive MUST render it as a disabled,
  non-navigating control

#### Scenario: Shared navigation receives product destinations

- **WHEN** a product route configures navigation labels and paths
- **THEN** product vocabulary and route descriptors MUST remain in the owning
  route or layout while the shared navigation implementation stays generic,
  shallow, and independent from route modules and GraphQL data

### Requirement: Relay Product Reads Use Render-Time Boundaries

Office Graph SHALL render product GraphQL reads through Relay hooks under
explicit React loading and safe error boundaries instead of mirroring request
lifecycle into parallel route-owned query-state machines.

#### Scenario: Product route performs its root read

- **WHEN** an operator or packet route reads its root GraphQL operation
- **THEN** the route MUST use a Relay render-time query hook with generated
  operation types and MUST render a product-specific Suspense fallback while
  the read is pending

#### Scenario: Product route root read fails

- **WHEN** a root Relay read throws a transport, GraphQL, authorization, or
  network error during rendering
- **THEN** a route-owned safe error boundary MUST replace the affected route
  content without rendering the raw error details

#### Scenario: Product panel performs a dependent read

- **WHEN** a selected identity or explicit operator event enables a dependent
  Relay read
- **THEN** the read MUST execute in an unconditionally rendered query child or
  through a preloaded-query hook and MUST use a boundary scoped to the affected
  panel when the surrounding route context can remain useful

#### Scenario: Product read lifecycle is represented

- **WHEN** Relay owns a product GraphQL read
- **THEN** route code MUST NOT duplicate Relay lifecycle in a custom object of
  pending, success, error, and fetch-status booleans

#### Scenario: Cursor route replaces pages

- **WHEN** a product route intentionally presents one cursor page at a time
- **THEN** the route MAY use changing query variables and local cursor history
  instead of a cumulative pagination fragment, while Relay MUST remain the
  server-state owner

#### Scenario: Independent activity page is requested

- **WHEN** a run-detail surface requests an additional page of activity
- **THEN** the continuation operation MUST fetch only the run identity and
  requested activity connection page rather than re-fetching unrelated run
  detail, packet, evidence, candidate, and verification fields

### Requirement: Shared Async Boundaries Stay Product Neutral

Office Graph SHALL keep reusable Suspense and error-boundary mechanics shallow
and independent from product vocabulary.

#### Scenario: Shared async boundary catches an error

- **WHEN** a generic async boundary catches a rendering error
- **THEN** it MUST render caller-supplied safe content and MUST NOT inspect,
  normalize, log, or expose product, GraphQL, authorization, or transport
  details itself

#### Scenario: Boundary input changes

- **WHEN** a caller-provided reset key changes after a prior error
- **THEN** the boundary MUST discard the captured error and attempt to render
  its children for the new input
