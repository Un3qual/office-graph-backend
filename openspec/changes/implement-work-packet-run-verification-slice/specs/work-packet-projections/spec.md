## ADDED Requirements

### Requirement: Initial Packet Run Summary Projection Is Authorized

Office Graph SHALL expose an initial authorized summary projection for packet
versions, work runs, observations, and verification state.

#### Scenario: Packet run summary is requested

- **WHEN** an authorized API client requests the first packet-run summary
- **THEN** Office Graph MUST return packet identity, selected packet version,
  objective, readiness or lifecycle state, work-run state, child observation
  summaries, required checks, accepted evidence summaries, verification
  result state, missing evidence reasons, and safe operation references

#### Scenario: Requester lacks access

- **WHEN** a requester lacks access to packet context, work-run child activity,
  evidence, observations, or source records
- **THEN** Office Graph MUST filter, redact, omit, or reject the restricted
  fields according to policy and MUST NOT reveal unauthorized source payloads

### Requirement: Initial Projection Separates Contract Execution And Evidence

Office Graph SHALL keep packet contract, execution activity, and verification
evidence distinct in the first API projection.

#### Scenario: Summary contains a completed observation

- **WHEN** a work run has a successful execution observation but no accepted
  evidence for a required check
- **THEN** the projection MUST show the observation as execution activity and
  MUST show verification as missing or unverified

#### Scenario: Summary contains accepted evidence

- **WHEN** a required check has accepted evidence and a passing verification
  result
- **THEN** the projection MUST link the packet version, work run, check,
  evidence, and result without presenting the evidence payload as run status
  alone
