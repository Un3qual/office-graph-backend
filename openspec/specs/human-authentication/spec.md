# human-authentication Specification

## Purpose
Define supported human sign-in entry points and their mapping to durable identities.
## Requirements
### Requirement: Human Authentication Entry Points
Office Graph SHALL define human authentication mechanics that resolve a login
to an internal principal without storing product permissions in auth claims.

#### Scenario: Local human login is exercised
- **WHEN** a developer or test logs in locally
- **THEN** Office Graph MUST support a local identity-lab path with authentik
  OIDC as the primary fixture and MUST resolve the authenticated subject to a
  `principal_id`

#### Scenario: SSO login succeeds
- **WHEN** a human authenticates through OIDC, SAML, or another enterprise SSO
  path
- **THEN** Office Graph MUST reconcile provider tenant, provider subject,
  verified identifiers, account-linking state, and lifecycle state through
  external identity links before issuing an authenticated session

#### Scenario: External user is disabled
- **WHEN** an external identity provider or SCIM feed disables or deprovisions
  a user
- **THEN** future login MUST fail closed or require explicit admin recovery,
  while historical provenance for that principal remains intact

### Requirement: External Claims Are Not Capabilities
Office Graph SHALL map external identity claims into internal policy facts
instead of treating claim names as direct permissions.

#### Scenario: SSO claim includes a group or role
- **WHEN** SSO claims include groups, roles, departments, or customer-specific
  attributes
- **THEN** Office Graph MUST map those claims through configured group mapping,
  team, role assignment, custom role, grant, or admin review policy rather
  than trusting the external claim as a product capability

### Requirement: OIDC Browser Login Integrity

Office Graph SHALL use an OpenID Connect authorization-code flow that binds the
browser request, callback, and token validation before reconciling an identity.

#### Scenario: Human login begins

- **WHEN** an unauthenticated human begins Authentik OIDC login
- **THEN** Office Graph MUST generate cryptographically random state, nonce,
  and PKCE verifier values, MUST store the transaction in the signed browser
  session for no more than ten minutes and one callback attempt, and MUST send
  the corresponding values to the provider authorization endpoint
- **AND** the callback handler MUST atomically consume the transaction before
  token exchange and MUST leave it absent after both successful and failed
  exchanges
- **AND** expired server-side one-time transaction guards MUST be pruned during
  normal login processing so abandoned login starts cannot retain guard records
  without bound

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
