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
  accepted backend read contract

#### Scenario: Demo code conflicts with frontend architecture
- **WHEN** preserving demo-era file names, adapter split points, or component
  structure would keep transport, query, view-model, or layout responsibilities
  tangled
- **THEN** the implementation MUST prefer the accepted frontend architecture over
  demo compatibility

### Requirement: Operator Server State Uses Query Hooks
Office Graph SHALL use feature-owned query hooks over TanStack Query for
operator workflow server state.

#### Scenario: Operator route reads workflow data
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

Office Graph SHALL route frontend data access through feature-owned data hooks
or clients rather than direct ad hoc fetch calls inside components.

#### Scenario: Feature reads backend data

- **WHEN** a feature route or panel reads Office Graph backend data
- **THEN** the feature MUST call a typed hook or client that returns a frontend
  view model independent of raw GraphQL response shape or future socket/live
  invalidation payloads

#### Scenario: Old adapter has no current caller

- **WHEN** a feature moves to the current product API path and an old adapter no
  longer has a current caller
- **THEN** the implementation MUST delete the old adapter and rewrite tests
  around the current data path instead of preserving adapter compatibility

#### Scenario: Product frontend has GraphQL coverage

- **WHEN** the React product frontend has a GraphQL read for a feature route
- **THEN** the product UI MUST use the GraphQL path directly through
  its feature-owned query hooks and MUST NOT keep a frontend JSON adapter as a
  compatibility requirement

### Requirement: Feature Components Stay Decomposed

Office Graph SHALL keep feature route containers, data hooks, layout
components, panels, and pure presentation helpers in separate modules once a
feature grows beyond a narrow screen.

#### Scenario: Operator workflow UI is refactored

- **WHEN** the operator workflow UI is touched for non-trivial behavior
- **THEN** the implementation MUST split route/container state, data hooks,
  workbench layout, inbox list, item detail, readiness panel, run panel, and
  verification panel into focused modules before adding more screen
  behavior

#### Scenario: Operator frontend is rebuilt

- **WHEN** the operator frontend foundation is rebuilt from the demo
- **THEN** route composition, query hooks, GraphQL transport/query documents,
  response mappers, derived workflow helpers, layout components, panels, and
  pure presentation helpers MUST live in focused modules with no component
  importing JSON API client code
