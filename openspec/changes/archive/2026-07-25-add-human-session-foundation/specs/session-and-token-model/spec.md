## ADDED Requirements

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
- **AND** same-scope issuance MUST serialize on a stable transaction-scoped
  lock so concurrent logins commit with at most one active session
- **AND** a failed issuance transaction MUST roll back both revocation and
  replacement; retry MUST begin a fresh login rather than replaying a consumed
  callback transaction

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
