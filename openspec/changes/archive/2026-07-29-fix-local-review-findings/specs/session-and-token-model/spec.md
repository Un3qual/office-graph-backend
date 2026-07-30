## ADDED Requirements

### Requirement: Authentication evidence uses bounded lifecycle vocabulary

Office Graph SHALL validate authentication event names and results before
persisting lifecycle evidence.

#### Scenario: Supported authentication evidence is recorded

- **WHEN** Office Graph records login, logout, revocation, or session-validation
  evidence with a succeeded or rejected result
- **THEN** the authentication event resource MUST accept the bounded event,
  result, and reason values

#### Scenario: Unsupported authentication evidence is attempted

- **WHEN** an internal caller supplies an unrecognized authentication event or
  result
- **THEN** the resource action MUST reject it without persisting evidence
