## ADDED Requirements

### Requirement: Current generic map fields are normalized
Office Graph SHALL remove the current generic map attributes from run events,
execution observations, raw archives, proposed graph changes, document marks,
operation correlations, evidence items, and GitHub outbound actions.

#### Scenario: Stable map keys carry product behavior
- **WHEN** a current map key is read for idempotency, workflow, provider command, projection, or policy behavior
- **THEN** it MUST become a typed column or typed related resource with action validation

#### Scenario: Current map is an unused placeholder
- **WHEN** a current map attribute has no production behavior or only stores an empty map
- **THEN** it MUST be removed until a typed requirement exists

#### Scenario: Raw provider body is archived
- **WHEN** a raw archive preserves the original provider payload for replay or debugging
- **THEN** the opaque body MAY remain archive content while provider event, installation, delivery, source, scope, operation, digest, and retention facts remain typed
