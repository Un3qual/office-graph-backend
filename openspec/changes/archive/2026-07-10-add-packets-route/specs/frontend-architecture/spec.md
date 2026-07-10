## ADDED Requirements

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
