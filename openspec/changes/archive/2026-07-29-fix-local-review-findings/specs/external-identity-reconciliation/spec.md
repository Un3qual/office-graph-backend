## ADDED Requirements

### Requirement: External identity lifecycle preserves principal ownership

Office Graph SHALL keep the principal ownership of an existing external
identity link immutable through generic lifecycle transitions.

#### Scenario: External identity lifecycle changes

- **WHEN** an existing external identity link becomes active, disabled, or
  review-required
- **THEN** the lifecycle action MUST preserve its current principal and MUST
  NOT accept a replacement principal identifier

#### Scenario: Existing email links have no compatible principal

- **WHEN** reconciliation finds existing verified-email links but no compatible
  principal candidate
- **THEN** it MUST fail closed with the bounded
  `verified_identifier_conflict` review reason
