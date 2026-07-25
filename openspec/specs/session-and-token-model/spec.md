# session-and-token-model Specification

## Purpose
Define thin sessions and tokens backed by durable identity and authorization state.
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

### Requirement: Cookie-Referenced Human Sessions

Office Graph SHALL keep the durable human session as the authentication
authority and SHALL store only an opaque session identifier in the browser
cookie.

#### Scenario: Human session is issued

- **WHEN** OIDC reconciliation and internal scope selection succeed
- **THEN** Office Graph MUST issue a `human_web` session that records principal,
  external identity link, authentication method, organization, workspace,
  issue time, expiry, source surface, and trace metadata without storing
  provider tokens or capability lists

#### Scenario: Browser cookie is written

- **WHEN** the human session is issued
- **THEN** the signed HTTP-only SameSite cookie MUST contain only the opaque
  durable session identifier and MUST be secure in production

### Requirement: Human Session Validation And Replacement

Office Graph SHALL validate current durable identity state whenever a browser
session is loaded and SHALL keep at most one active human session per principal
and selected scope.

#### Scenario: Existing human session is loaded

- **WHEN** a request presents a human session identifier
- **THEN** Office Graph MUST require the session to be `human_web`, unexpired,
  and unrevoked, the principal and external link to be active and related, and
  the stored organization/workspace context to remain valid

#### Scenario: Replacement login succeeds

- **WHEN** the same principal logs in again to the same organization and
  workspace
- **THEN** Office Graph MUST revoke the previous active `human_web` session
  before issuing its replacement and the previous session MUST remain unusable

#### Scenario: Human logs out

- **WHEN** an authenticated human logs out
- **THEN** Office Graph MUST revoke the durable session, clear the browser
  cookie, and make local logout succeed even if provider logout is unavailable

### Requirement: Human Authentication Lifecycle Evidence

Office Graph SHALL preserve bounded authentication evidence without storing
provider secrets or raw claims.

#### Scenario: Authentication lifecycle result is recorded

- **WHEN** login succeeds, login is rejected, or logout revokes a session
- **THEN** Office Graph MUST preserve the available principal, external link,
  session, scope, auth method, source surface, trace identifier, result, and a
  bounded reason code

#### Scenario: Authentication evidence is persisted

- **WHEN** Office Graph records an authentication event
- **THEN** it MUST NOT persist authorization codes, access tokens, refresh
  tokens, ID tokens, cookie values, or unfiltered provider claims
