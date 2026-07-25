## ADDED Requirements

### Requirement: OIDC Browser Login Integrity

Office Graph SHALL use an OpenID Connect authorization-code flow that binds the
browser request, callback, and token validation before reconciling an identity.

#### Scenario: Human login begins

- **WHEN** an unauthenticated human begins Authentik OIDC login
- **THEN** Office Graph MUST generate cryptographically random state, nonce,
  and PKCE verifier values, MUST store the short-lived transaction in the
  signed browser session, and MUST send the corresponding values to the
  provider authorization endpoint

#### Scenario: OIDC callback is accepted

- **WHEN** Authentik returns an authorization code with the matching state
- **THEN** Office Graph MUST exchange the code with the original redirect URI
  and PKCE verifier, MUST validate the ID token issuer, audience, signature,
  expiry, and nonce through the OIDC client, and MUST reconcile only validated
  claims

#### Scenario: OIDC callback transaction is invalid

- **WHEN** callback state is missing or mismatched, the login transaction is
  missing, or provider token validation fails
- **THEN** Office Graph MUST fail closed without issuing a durable human
  session

### Requirement: Explicit Human Account Linking

Office Graph SHALL link an OIDC subject to an internal principal only through a
configured account-linking policy and SHALL NOT create product authority from
provider claims.

#### Scenario: Verified existing principal is linked

- **WHEN** the configured policy is `verified_email_existing_principal`, the
  provider verifies the claimed email, exactly one eligible active human
  principal owns that normalized email, and no incompatible link exists
- **THEN** Office Graph MUST create the external identity link to that
  principal and MUST derive scope and permissions only from current internal
  facts

#### Scenario: Provider claims include groups or roles

- **WHEN** validated OIDC claims contain groups, roles, departments, or custom
  capability-like values
- **THEN** the login flow MUST NOT create role assignments, grants, or
  capabilities from those claims

#### Scenario: Account linking is not allowed

- **WHEN** no supported account-linking policy is configured
- **THEN** an unknown OIDC subject MUST remain unlinked and MUST NOT receive a
  session
