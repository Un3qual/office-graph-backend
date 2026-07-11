## ADDED Requirements

### Requirement: Manual Intake Has Supported Product Commands
Office Graph SHALL expose manual intake submission through authenticated
GraphQL and JSON API commands over the Integrations domain boundary.

#### Scenario: Operator submits manual intake
- **WHEN** an authorized operator submits body, source identity, replay
  identity, and idempotency key
- **THEN** both API families MUST apply the existing archive, normalization,
  duplicate, operation-correlation, authorization, and proposed-change rules
  and return the normalized event and proposed-change identities

#### Scenario: Intake replay conflicts
- **WHEN** the same source and replay identity arrives with different content
- **THEN** both API families MUST return the existing stable replay conflict and
  MUST NOT create a second accepted event
