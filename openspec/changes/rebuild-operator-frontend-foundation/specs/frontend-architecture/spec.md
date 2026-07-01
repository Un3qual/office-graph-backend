## ADDED Requirements

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
  accepted backend projection contract

#### Scenario: Demo compatibility conflicts with frontend architecture
- **WHEN** preserving demo-era file names, adapter seams, or component
  structure would keep transport, query, view-model, or layout responsibilities
  tangled
- **THEN** the implementation MUST prefer the accepted frontend architecture
  boundaries over demo compatibility

### Requirement: Operator Server State Uses Query Hooks
Office Graph SHALL use feature-owned query hooks over TanStack Query for
operator workflow server state.

#### Scenario: Operator route reads workflow projections
- **WHEN** the operator React route reads inbox, selected item detail, packet
  readiness, run state, or verification state
- **THEN** those reads MUST go through feature-owned query hooks with stable
  query keys, typed view-model return values, retries disabled in component
  tests, and explicit loading, empty, error, and loaded states

#### Scenario: Operator UI needs local interaction state
- **WHEN** the operator UI tracks selected row, selected tab, expanded panel, or
  transient control state
- **THEN** the state MUST remain local React state or an accepted URL parameter
  and MUST NOT be hidden in the server-state cache as durable product state

## MODIFIED Requirements

### Requirement: Projection Client Boundary

Office Graph SHALL route frontend data access through feature-owned projection
client interfaces rather than direct ad hoc fetch calls inside components.

#### Scenario: Feature reads backend projection

- **WHEN** a feature route or panel reads an Office Graph projection
- **THEN** the feature MUST call a typed projection client or hook that returns
  a frontend view model independent of GraphQL response shape, temporary JSON
  migration shapes, or future socket/live invalidation payloads

#### Scenario: Transport adapter changes

- **WHEN** a projection moves from a temporary JSON adapter to the GraphQL
  product adapter or adds socket/live invalidation
- **THEN** component props and rendering logic MUST remain stable unless the
  projection contract itself changes through OpenSpec

#### Scenario: Product frontend has GraphQL projection coverage

- **WHEN** the React product frontend has a GraphQL projection for a feature
  route
- **THEN** the product UI MUST use the GraphQL projection path directly through
  its feature-owned query hooks and MUST NOT keep a frontend JSON adapter as a
  compatibility requirement

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
