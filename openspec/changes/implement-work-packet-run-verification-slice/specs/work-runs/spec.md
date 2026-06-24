## ADDED Requirements

### Requirement: Initial Work Run Starts From A Packet Version

Office Graph SHALL implement work-run creation from a selected packet version
as the first execution path.

#### Scenario: Work run starts

- **WHEN** an authorized actor starts execution from a ready packet version
- **THEN** Office Graph MUST create a work run that records organization,
  workspace, packet, packet version, objective, initiator, authority posture,
  operation correlation, required checks, aggregate state, and timestamps

#### Scenario: Packet version is not ready

- **WHEN** an actor attempts to start a work run from a draft, stale,
  superseded, not-ready, unauthorized, or missing packet version
- **THEN** Office Graph MUST reject the command without creating a work run
  and MUST return an explainable validation or authorization error

### Requirement: Initial Work Run Coordinates Typed Child Observations

Office Graph SHALL link execution observations to work runs as typed child
activity in the first slice.

#### Scenario: Human or provider observation is recorded

- **WHEN** a human handoff note, manual execution status, provider check, test
  result, or integration job status is recorded for a work run
- **THEN** Office Graph MUST create an execution observation or typed link to
  an existing observation and MUST include it in the work run's aggregate
  status inputs

#### Scenario: Child activity is stored

- **WHEN** child activity is added to a work run
- **THEN** Office Graph MUST preserve typed child references and MUST NOT store
  the child activity only as an opaque generic run-event payload

### Requirement: Initial Work Run Status Separates Execution From Verification

Office Graph SHALL compute the first work-run aggregate status separately from
verification completion.

#### Scenario: Execution succeeds without accepted evidence

- **WHEN** all recorded child execution observations are successful but a
  required verification check lacks accepted evidence or a valid result
- **THEN** Office Graph MUST expose the work run as execution-complete or
  awaiting-verification rather than verified-complete

#### Scenario: Required check is satisfied

- **WHEN** all required checks for the selected packet version have accepted
  evidence and passing verification results
- **THEN** Office Graph MUST be able to expose the work run as verified while
  preserving the evidence and result records that explain the status
