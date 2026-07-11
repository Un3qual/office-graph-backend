## ADDED Requirements

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
