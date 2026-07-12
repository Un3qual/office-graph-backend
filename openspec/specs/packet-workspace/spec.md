# packet-workspace Specification

## Purpose

Define the dedicated packet product route, its Relay-owned read states,
route-local selection, pagination, and packet summary behavior.

## Requirements

### Requirement: Packet Workspace Reads Packets Through Relay

Office Graph SHALL provide a dedicated `/packets` product route whose server
state is owned by a route-local Relay query over the generated packet
connection.

#### Scenario: Packet workspace loads

- **WHEN** an authorized operator opens `/packets`
- **THEN** the route MUST load packet edges and page information through the
  generated `listWorkPackets` Relay connection and MUST render explicit
  loading and loaded states without a JSON adapter or competing server-state
  cache

#### Scenario: Packet workspace is empty

- **WHEN** the packet connection returns no packet edges
- **THEN** the route MUST render a packet-specific empty state and MUST NOT
  render stale selected-packet detail

#### Scenario: Packet workspace read fails

- **WHEN** the packet Relay read fails
- **THEN** the route MUST render a safe error state and MUST NOT expose raw
  GraphQL, authorization, or transport details

#### Scenario: Packet workspace has another page

- **WHEN** packet page information reports a next or previous page
- **THEN** the route MUST expose the corresponding pagination control, request
  that page with Relay cursor variables, and preserve an explicit loading state
  during the request

### Requirement: Packet Selection Is Route-Local

Office Graph SHALL keep packet selection as local React interaction state until
an accepted change introduces durable or URL-owned selection semantics.

#### Scenario: First packet page loads without a selection

- **WHEN** a non-empty packet page loads and the route has no selected packet
- **THEN** the route MUST select the first packet on that page

#### Scenario: Operator selects a packet

- **WHEN** an operator selects a packet row on the current page
- **THEN** the route MUST mark that row selected and render detail from the
  selected packet's Relay-owned data

#### Scenario: Pagination removes the selected packet

- **WHEN** the route loads a page that does not contain the selected packet
- **THEN** selection MUST move to the first packet on the new page or become
  empty when the new page has no rows

### Requirement: Packet Workspace Presents Product Summary Fields

Office Graph SHALL present packet data as a dense operational list and detail
surface using named product fields from the generated packet GraphQL type.

#### Scenario: Selected packet renders

- **WHEN** a packet is selected
- **THEN** the detail surface MUST show its title, lifecycle state, update
  time, and current-version linkage while keeping raw compatibility identities
  visually secondary

#### Scenario: Packet route is verified

- **WHEN** frontend and app-shell verification run
- **THEN** tests MUST cover packet Relay compilation, route ownership,
  loading, empty, error, selection, pagination, and Phoenix SPA serving for
  `/packets`

### Requirement: Packet Workspace Creates And Versions Packets

The packet workspace SHALL expose packet creation and version editing through
route-owned Relay mutations.

#### Scenario: Operator creates a packet

- **WHEN** the operator submits complete packet input from an eligible source
  and required checks
- **THEN** the route MUST execute the packet-create command, select the returned
  packet, and render its immutable current version and readiness state

#### Scenario: Operator creates a new version

- **WHEN** the operator edits current packet inputs and submits the current
  version id as the expected version
- **THEN** the route MUST create a new immutable version, preserve prior version
  history, and render the returned version as current

#### Scenario: Packet version is stale

- **WHEN** another command changes the packet current version before submission
- **THEN** the route MUST show a safe stale-version conflict, refresh packet
  data, and MUST NOT silently overwrite the newer version

### Requirement: Packet Workspace Starts Ready Runs

The packet workspace SHALL expose run start only for a packet version whose
current command affordance allows it.

#### Scenario: Current packet is ready

- **WHEN** the current version is ready and run start is authorized
- **THEN** the route MUST allow the operator to submit source surface, reason,
  and authority posture and navigate or link to the returned run state

#### Scenario: Current packet is blocked

- **WHEN** readiness or policy disables run start
- **THEN** the route MUST keep the action unavailable and show safe blockers
