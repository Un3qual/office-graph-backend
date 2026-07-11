## ADDED Requirements

### Requirement: Current Packets Can Receive Explicit New Versions
Office Graph SHALL create a new immutable work-packet version through the
WorkPackets domain without mutating prior packet versions.

#### Scenario: Operator creates a packet version
- **WHEN** an authorized operator submits a packet id, expected current-version
  id, title, objective, context, requirements, success criteria, autonomy
  posture, ordered source ids, ordered required-check ids, and idempotency key
- **THEN** Office Graph MUST create one immutable version, preserve ordered
  links, set it as the packet current version, derive readiness, and return both
  packet and version

#### Scenario: Current version changed
- **WHEN** the submitted expected current-version id is not the packet's current
  version at command execution
- **THEN** Office Graph MUST return a stale-version conflict and MUST NOT create
  a new version

#### Scenario: Version command replays
- **WHEN** the same operation is retried with equivalent packet-version input
- **THEN** Office Graph MUST return the existing version; changed or reordered
  input MUST return an idempotency conflict
