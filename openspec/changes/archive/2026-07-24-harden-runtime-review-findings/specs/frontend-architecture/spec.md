## MODIFIED Requirements

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
