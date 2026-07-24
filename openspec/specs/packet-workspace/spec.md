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

Office Graph SHALL keep packet selection owned by the packet route and SHALL
represent an explicit selection in the route URL as
`?packetId=<opaque-relay-id>`. GraphQL SHALL derive that opaque Relay identifier
from the projected packet identity, and both `/runs` links and the packet route
SHALL use the same representation. The route SHALL retain its existing list,
detail, paging, and mutation ownership; this URL behavior SHALL NOT add another
packet projection or command path. The first visible packet SHALL be selected
only when `packetId` is absent. Every present `packetId` value SHALL remain the
requested selection until existing authorized detail behavior resolves it, and
this URL behavior SHALL use the existing shared `RequestSession` resolution
unchanged without creating a route-specific actor, session, or fallback.

#### Scenario: First packet page loads without a selection

- **WHEN** a non-empty packet page loads with no `packetId` URL parameter
- **THEN** the route MUST select the first packet on that page, represent that
  selection in the URL, and retain its route-local origin as a default
  selection

#### Scenario: URL selects a visible packet

- **WHEN** `/packets?packetId=<opaque-relay-id>` names a packet on the current
  authorized page
- **THEN** the route MUST select that packet with explicit origin and render its
  existing Relay-owned detail instead of replacing it with the first packet

#### Scenario: URL names a packet outside the current page

- **WHEN** `/packets?packetId=<opaque-relay-id>` names an id absent from the
  current packet page
- **THEN** the packet route MUST use its existing authorized detail behavior to
  resolve or safely reject the selection without creating a second packet
  projection

#### Scenario: Packet URL selection is unavailable

- **WHEN** a present `packetId` URL value is missing, unauthorized, invalid, or
  stale after its authorized detail behavior resolves
- **THEN** the route MUST clear stale selected-packet detail, preserve the list,
  retain the requested URL value, and render a safe unavailable state without
  revealing cross-scope existence or falling back to the first or another row

#### Scenario: Operator selects a packet

- **WHEN** an operator selects a packet row on the current page
- **THEN** the route MUST mark that row selected with operation origin, update
  `packetId` in the URL, and render detail from the selected packet's Relay-owned
  data

#### Scenario: Pagination removes the default selection

- **WHEN** the route loads a page that does not contain a route-local default
  selection even though the URL reflects that selection
- **THEN** selection MUST move to the first packet on the new page or become
  empty when the new page has no rows

#### Scenario: Pagination removes an explicit selection

- **WHEN** the route loads a page that does not contain a URL or
  operator-selected packet
- **THEN** the route MUST keep the explicit selection pinned and MUST NOT replace
  it with the first packet on the new page

#### Scenario: Present packet selection is outside the page

- **WHEN** a page does not contain a present explicitly requested `packetId`
  selection
- **THEN** the route MUST retain that URL value and authoritatively resolve it
  through existing authorized detail behavior instead of defaulting to a row on
  the page

#### Scenario: Packet URL behavior resolves a session

- **WHEN** packet URL selection requires an authorized detail read
- **THEN** the route MUST use the existing shared `RequestSession` resolution
  unchanged and MUST NOT create a route-specific actor, session, bootstrap, or
  fallback

#### Scenario: Packet deep link reaches the workspace

- **WHEN** `/runs` links to
  `/packets?packetId=<opaque-relay-id>` for an authorized owning packet
- **THEN** the packet route MUST preserve that selected product context while
  keeping all packet creation, versioning, and run-start commands in their
  existing owners

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
