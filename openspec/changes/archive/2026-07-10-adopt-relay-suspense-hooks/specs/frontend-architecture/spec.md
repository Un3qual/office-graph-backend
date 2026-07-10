## ADDED Requirements

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
