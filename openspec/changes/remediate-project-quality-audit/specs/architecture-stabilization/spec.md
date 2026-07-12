## MODIFIED Requirements

### Requirement: Architecture Drift Gates

Office Graph SHALL include verification gates that fail when new architecture debt is added without accepted documentation.

#### Scenario: Verification runs

- **WHEN** backend, frontend, or full project verification runs
- **THEN** the gate MUST check for undocumented manual API endpoints, direct database exceptions, broad `authorize?: false` paths, missing frontend build verification, dependency advisories, and OpenSpec drift relevant to the stabilization tracks

#### Scenario: Full project verification runs

- **WHEN** a developer or CI runs the named full-project verification or precommit alias
- **THEN** the gate MUST compile the backend once with warnings as errors, validate the current Relay schema and frontend build, check locked dependencies for published advisories, and run strict validation for checked-in OpenSpec specs and changes

#### Scenario: New exception is required

- **WHEN** implementation requires a custom transport, direct database access, frontend architecture exception, or infrastructure noun exposed in a product projection
- **THEN** the exception MUST record owner, reason, approving spec, allowed scope, verification coverage, and retirement condition
