# packet-workspace Specification

## Purpose

Define the dedicated packet product route, its Relay-owned read states,
route-local selection, pagination, and packet summary behavior.

## Requirements

### Requirement: Packet Workspace Reads Packets Through Relay

Office Graph SHALL provide a dedicated `/packets` product route whose server
packet, current-version, version-history, source-reference, and required-check
records are owned by route-local Relay queries over AshGraphql-generated
resource types. The route MAY combine those records with the named
`operatorPacketWorkspace` mixed projection for readiness, blockers, next
actions, and command affordances, but that projection SHALL NOT duplicate
packet resource objects or relationship loaders.

#### Scenario: Packet workspace loads

- **WHEN** an authorized operator opens `/packets`
- **THEN** the route MUST load packet edges and page information through the
  generated `listWorkPackets` Relay connection, load selected packet records
  through `getWorkPacket`, and MUST render explicit loading and loaded states
  without a JSON adapter or competing server-state cache

#### Scenario: Selected packet detail loads

- **WHEN** the route resolves an authorized selected packet
- **THEN** its current version, version history, ordered source references, and
  ordered required checks MUST come from generated Ash relationships, with
  packet versions paged through a keyset-backed Relay connection

#### Scenario: Packet resource is refetched

- **WHEN** a client supplies an opaque packet, packet-version,
  source-reference, or required-check identifier to `node(id:)`
- **THEN** GraphQL MUST refetch the generated resource through its authorized
  Ash read action without a resource-specific manual node dispatcher

#### Scenario: Packet workspace is empty

- **WHEN** the packet connection returns no packet edges
- **THEN** the route MUST render a packet-specific empty state and MUST NOT
  render stale selected-packet detail

#### Scenario: Packet workspace read fails

- **WHEN** a generated packet read or mixed readiness projection fails
- **THEN** the route MUST render a safe error state and MUST NOT expose raw
  GraphQL, authorization, or transport details

#### Scenario: Packet workspace has another page

- **WHEN** packet or packet-version page information reports another page
- **THEN** the route MUST expose the corresponding pagination control, request
  that page with Relay cursor variables, and preserve an explicit loading state
  during the request

#### Scenario: External client reads packet contract records

- **WHEN** an authorized JSON API client reads packet versions, source
  references, or required checks
- **THEN** AshJsonApi MUST expose the owning generated resource routes with the
  same actor-scoped authorization and no packet-workspace controller or
  serializer

### Requirement: Packet Selection Is Route-Local

Office Graph SHALL keep packet selection owned by the packet route and SHALL
represent an explicit selection in the route URL as
`?packetId=<opaque-relay-id>`. GraphQL SHALL derive that opaque Relay identifier
from the projected packet identity, and both `/runs` links and the packet route
SHALL use the same representation. The first visible packet SHALL be displayed
locally only when `packetId` is absent; default display SHALL NOT synthesize an
explicit URL selection. Every present `packetId` value SHALL remain the
requested selection until existing authorized detail behavior resolves it.

#### Scenario: First packet page loads without a selection

- **WHEN** a non-empty packet page loads with no `packetId` URL parameter
- **THEN** the route MUST display the first packet without adding `packetId` to
  the URL

#### Scenario: URL selects a visible packet

- **WHEN** `/packets?packetId=<opaque-relay-id>` names a packet on the current
  authorized page
- **THEN** the route MUST select that packet and render its existing
  Relay-owned detail instead of replacing it with the first packet

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

- **WHEN** an operator selects a packet row
- **THEN** the route MUST update `packetId` in the URL and render detail from
  that packet's Relay-owned data

#### Scenario: Pagination has no explicit selection

- **WHEN** the route loads another page while `packetId` is absent
- **THEN** the route MUST display the first packet on that page or an empty
  detail when the page has no rows without changing the URL

#### Scenario: Pagination removes an explicit selection

- **WHEN** the route loads a page that does not contain a URL-selected packet
- **THEN** the route MUST keep the explicit selection pinned and MUST NOT replace
  it with the first packet on the new page

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
