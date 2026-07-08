## ADDED Requirements

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
  types, and store updates instead of adding a parallel homemade view-model or
  TanStack Query cache layer for the same GraphQL data

#### Scenario: Product GraphQL data is cached
- **WHEN** a product route reads GraphQL server state
- **THEN** it MUST use Relay and MUST NOT run TanStack Query as a competing
  cache for the same product GraphQL records

## MODIFIED Requirements

### Requirement: Operator Server State Uses Query Hooks
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

### Requirement: Feature Data Hooks

Office Graph SHALL route frontend data access through route-owned Relay data,
Relay fragments, or typed feature clients rather than direct ad hoc fetch calls
inside components.

#### Scenario: Feature reads backend data

- **WHEN** a feature route or panel reads Office Graph backend data
- **THEN** the feature MUST consume product GraphQL data through Relay route
  data, Relay fragment data, or typed UI data independent of raw transport
  response shape or future socket/live invalidation payloads

#### Scenario: Old adapter has no current caller

- **WHEN** a feature moves to the current product API path and an old adapter no
  longer has a current caller
- **THEN** the implementation MUST delete the old adapter and rewrite tests
  around the current data path instead of preserving adapter compatibility

#### Scenario: Product frontend has GraphQL coverage

- **WHEN** the React product frontend has a GraphQL read for a feature route
- **THEN** the product UI MUST use the GraphQL path directly through Relay and
  MUST NOT keep a frontend JSON adapter as a compatibility requirement

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
