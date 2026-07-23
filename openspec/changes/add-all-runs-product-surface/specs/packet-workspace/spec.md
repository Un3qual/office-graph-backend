## MODIFIED Requirements

### Requirement: Packet Selection Is Route-Local

Office Graph SHALL keep packet selection owned by the packet route and SHALL
represent an explicit selection in the route URL as `?packetId=<id>`. The
route SHALL retain its existing list, detail, paging, and mutation ownership;
this URL behavior SHALL NOT add another packet projection or command path.

#### Scenario: First packet page loads without a selection

- **WHEN** a non-empty packet page loads and the route has no valid `packetId`
  URL selection
- **THEN** the route MUST select the first packet on that page and represent
  that selection in the URL

#### Scenario: URL selects a visible packet

- **WHEN** `/packets?packetId=<id>` names a packet on the current authorized
  page
- **THEN** the route MUST select that packet and render its existing
  Relay-owned detail instead of replacing it with the first packet

#### Scenario: URL names a packet outside the current page

- **WHEN** `/packets?packetId=<id>` names an id absent from the current packet
  page
- **THEN** the packet route MUST use its existing authorized detail behavior to
  resolve or safely reject the selection without creating a second packet
  projection

#### Scenario: Packet URL selection is unavailable

- **WHEN** a `packetId` URL value is missing, unauthorized, invalid, or stale
- **THEN** the route MUST clear stale selected-packet detail, preserve the list,
  and render a safe unavailable state without revealing cross-scope existence

#### Scenario: Operator selects a packet

- **WHEN** an operator selects a packet row on the current page
- **THEN** the route MUST mark that row selected, update `packetId` in the URL,
  and render detail from the selected packet's Relay-owned data

#### Scenario: Pagination removes the selected packet

- **WHEN** the route loads a page that does not contain a selection created
  without an explicit valid `packetId` URL value
- **THEN** selection MUST move to the first packet on the new page or become
  empty when the new page has no rows

#### Scenario: Packet deep link reaches the workspace

- **WHEN** `/runs` links to `/packets?packetId=<id>` for an authorized owning
  packet
- **THEN** the packet route MUST preserve that selected product context while
  keeping all packet creation, versioning, and run-start commands in their
  existing owners
