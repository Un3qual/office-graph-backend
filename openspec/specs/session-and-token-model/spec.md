# session-and-token-model Specification

## Purpose
TBD - created by archiving change design-identity-and-authentication. Update Purpose after archive.
## Requirements
### Requirement: Thin Session And Token Model
Office Graph SHALL keep sessions and tokens as authentication artifacts, not
authorization fact stores.

#### Scenario: Session is created
- **WHEN** a human, service account, or approved runtime actor receives a
  session or token
- **THEN** the session or token MUST identify principal, authentication method,
  external identity link when applicable, selected tenant/scope context, issue
  time, expiry, revocation state, and trace metadata without embedding product
  capability lists as durable authority

#### Scenario: Governed action is requested
- **WHEN** an authenticated principal attempts a governed action
- **THEN** Office Graph MUST re-evaluate authorization against current policy
  facts, scopes, grants, sensitivity labels, credential metadata, and effective
  policy bundle versions rather than trusting stale session claims
- **AND** the authenticated principal MUST still be active at validation time

### Requirement: Session Lifecycle Audit Events
Office Graph SHALL emit audit-relevant authentication events for sensitive
session and token lifecycle actions.

#### Scenario: Sensitive session action occurs
- **WHEN** login, logout, refresh, token issuance, revocation, suspicious
  reuse, credential exchange, or tenant switching occurs
- **THEN** Office Graph MUST preserve actor, principal, auth method, tenant
  context, source surface, request/trace identifiers, result, and operation or
  audit linkage when policy requires it

#### Scenario: Token is revoked
- **WHEN** a session, API token, service credential, or runtime token is
  revoked
- **THEN** future use MUST fail closed and policy-sensitive revocation context
  MUST be auditable

#### Scenario: Replacement session is issued
- **WHEN** a new session is issued for a principal, tenant scope, and purpose
  whose previous session was revoked
- **THEN** the revoked session MUST remain unusable and Office Graph MUST allow
  only one active session for that principal, tenant scope, and purpose
