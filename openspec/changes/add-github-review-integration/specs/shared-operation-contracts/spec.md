## ADDED Requirements

### Requirement: System Operations Use A Separate Authenticated Envelope
Office Graph SHALL create non-human system operations from a request that names
organization, service or webhook principal, authority basis, action, causation,
idempotency scope, optional governing workspace, optional subject/version, and
credential reference when required.

#### Scenario: Webhook source starts an operation
- **WHEN** a verified active installation webhook starts supported processing
- **THEN** Office Graph MUST create or replay a system operation bound to the
  installation source principal and organization without fabricating a session

#### Scenario: Unsupported system action is requested
- **WHEN** a service principal requests an action outside its capabilities,
  installation scope, or declared job kinds
- **THEN** Office Graph MUST deny it before operation or job creation

### Requirement: Human And System Operation Invariants Remain Distinct
Office Graph SHALL prevent system-operation optional fields from weakening
human operation validation.

#### Scenario: Human mutation starts an operation
- **WHEN** GraphQL or JSON API handles a human product command
- **THEN** it MUST continue to require the authenticated principal, session,
  organization, workspace, and command-specific subject data

#### Scenario: Worker receives malformed system operation
- **WHEN** a worker receives missing authority basis, principal, organization, or
  idempotency scope
- **THEN** it MUST fail closed with a safe terminal classification
