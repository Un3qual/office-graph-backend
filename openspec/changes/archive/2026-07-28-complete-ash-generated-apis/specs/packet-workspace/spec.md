## MODIFIED Requirements

### Requirement: Packet Workspace Reads Packets Through Relay

Office Graph SHALL provide a dedicated `/packets` product route whose packet,
current-version, version-history, source-reference, and required-check records
are owned by route-local Relay queries over AshGraphql-generated resource
types. The route MAY combine those records with the named
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
