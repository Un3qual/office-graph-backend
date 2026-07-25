## MODIFIED Requirements

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
