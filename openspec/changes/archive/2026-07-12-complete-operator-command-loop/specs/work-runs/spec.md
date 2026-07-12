## ADDED Requirements

### Requirement: Work Run Start Has Supported Product Commands
Office Graph SHALL expose packet-backed work-run start through authenticated
GraphQL and JSON API commands over the Runs domain boundary.

#### Scenario: Operator starts a work run
- **WHEN** an authorized operator submits a ready packet-version id, source
  surface, reason, authority posture, and idempotency key
- **THEN** both API families MUST preserve current readiness, scope, autonomy,
  required-check, operation, and replay rules and return the run and ordered
  required checks

#### Scenario: Packet version is no longer runnable
- **WHEN** the packet version is stale, draft, cross-scope, malformed, or refers
  only to checks already satisfied
- **THEN** run start MUST fail without creating a run
