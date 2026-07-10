## ADDED Requirements

### Requirement: Operator Dependent Relay Reads Preserve Workspace Context
Office Graph SHALL isolate dependent operator Relay reads so readiness or run
state loading and failure do not discard still-valid inbox and item context.

#### Scenario: Readiness validation is requested
- **WHEN** an operator explicitly validates readiness derived from the selected
  inbox item
- **THEN** the validation read MUST run through Relay under a readiness-panel
  loading boundary while the selected inbox row and item detail remain visible

#### Scenario: Readiness validation fails
- **WHEN** the readiness validation Relay read fails
- **THEN** the readiness panel MUST show a safe validation error without
  exposing raw backend details or replacing the surrounding operator workspace

#### Scenario: Selected item has a linked run
- **WHEN** the selected operator item resolves to a run id
- **THEN** run and verification data MUST render from a Relay query child under
  a panel-scoped loading and error boundary

#### Scenario: Run state read fails
- **WHEN** the linked run Relay read fails
- **THEN** the run and verification area MUST show safe unavailable state while
  the inbox, selected item detail, and readiness context remain visible

#### Scenario: Operator selection changes
- **WHEN** an operator selects a different inbox item
- **THEN** dependent readiness-validation and run-state boundaries MUST reset
  to the new selected identity and MUST NOT render results or errors retained
  from the prior item
