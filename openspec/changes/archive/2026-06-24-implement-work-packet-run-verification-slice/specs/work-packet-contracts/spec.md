## ADDED Requirements

### Requirement: Initial Packet Contract Is Persisted As A Stable Version

Office Graph SHALL persist the first executable work-packet slice as a stable
packet version rather than as mutable packet fields alone.

#### Scenario: Packet version is created

- **WHEN** an authorized actor creates a work packet for execution
- **THEN** Office Graph MUST create a packet record and a first packet version
  that records organization, workspace, objective, context summary,
  requirements, success criteria, autonomy posture, source graph item
  references, required verification checks, operation correlation, lifecycle
  state, and version number

#### Scenario: Packet version is used for execution

- **WHEN** a work run starts from a packet
- **THEN** the work run MUST reference the selected packet version and MUST NOT
  depend on later mutation of the packet's current editable fields to explain
  the execution contract

### Requirement: Initial Packet Creation Preserves Typed Source References

Office Graph SHALL preserve source graph and verification references through
typed records in the initial packet creation path.

#### Scenario: Packet includes source work

- **WHEN** packet creation receives source tasks, review findings, graph items,
  artifacts, decisions, or verification checks
- **THEN** Office Graph MUST store typed source-reference rows or typed
  foreign keys that identify each source record and the rationale for including
  it

#### Scenario: Packet references inaccessible context

- **WHEN** the creating actor lacks access to a referenced source record
- **THEN** Office Graph MUST reject the reference or store only a
  policy-approved restricted placeholder instead of copying unauthorized
  source data into the packet version

### Requirement: Initial Packet Lifecycle Is Explicit

Office Graph SHALL implement a minimal packet lifecycle for the first execution
slice.

#### Scenario: Packet is ready for run creation

- **WHEN** a packet version has objective, success criteria, source references,
  required check references, operation context, and an allowed autonomy posture
- **THEN** Office Graph MUST be able to mark that version ready for execution
  and allow a work run to start from it

#### Scenario: Packet is missing verification expectations

- **WHEN** a packet version lacks required checks, success criteria, or an
  allowed verification expectation for its execution mode
- **THEN** Office Graph MUST keep the packet draft or not-ready and MUST NOT
  allow verified completion to be inferred from run status alone
