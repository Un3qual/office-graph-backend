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

### Requirement: Human login selects a configured provider before redirect

Office Graph SHALL select the human authentication provider and any enterprise
connection before redirecting the browser and SHALL carry that selection only
inside the bounded one-time login transaction.

#### Scenario: Local OIDC login begins

- **WHEN** a developer or deployment uses the configured generic OIDC entry
  point
- **THEN** Office Graph MUST retain the existing OIDC discovery, nonce, PKCE,
  callback validation, external identity reconciliation, and durable session
  behavior

#### Scenario: WorkOS enterprise login begins

- **WHEN** a human starts login through an active WorkOS enterprise connection
- **THEN** Office Graph MUST use the WorkOS SSO adapter for external exchange
  while using the same internal principal, scope, session, lifecycle, and
  authentication-evidence boundaries as generic OIDC

#### Scenario: Provider selection is unavailable

- **WHEN** the selected provider or enterprise connection is absent, disabled,
  incomplete, or inconsistent with the stored login transaction
- **THEN** Office Graph MUST fail closed without falling back to another
  provider or issuing a session under a different tenant

### Requirement: Canonical principal identity lookup is declaratively indexed

Office Graph SHALL persist principal email in the canonical form used for
verified-email reconciliation and SHALL index that typed attribute through an
AshPostgres identity.

#### Scenario: Principal email is stored

- **WHEN** Office Graph creates a principal from an email containing case or
  surrounding whitespace
- **THEN** it MUST store the lowercase trimmed email and make reconciliation
  query the indexed canonical attribute

#### Scenario: Equivalent emails are written concurrently

- **WHEN** concurrent writes supply case or whitespace variants of the same
  email
- **THEN** canonicalization and the identity index MUST retain one principal
  identity rather than creating ambiguous variants

### Requirement: Local development authentication is explicit and isolated

Office Graph SHALL offer a local-development human authentication provider only
when a development build, explicit local-auth setting, and loopback request all
authorize that provider.

#### Scenario: Developer opens the configured local login page

- **WHEN** an unauthenticated loopback request reaches `/auth/login` in a
  development build with local authentication explicitly enabled
- **THEN** Office Graph MUST render a browser-safe chooser containing only
  fixed server-owned fixture selections and MUST preserve a validated
  root-relative return target
- **AND** it MUST NOT issue a session until the developer explicitly selects a
  fixture

#### Scenario: Local authentication is unavailable

- **WHEN** the application is not a development build, local authentication is
  not explicitly enabled, or the request is not from loopback
- **THEN** the local chooser and selection routes MUST be unavailable and MUST
  NOT authenticate, bootstrap, create, reactivate, or grant any principal
- **AND** missing generic OIDC configuration MUST continue to fail closed
  without selecting the local provider as a fallback

#### Scenario: Browser submits an arbitrary identity

- **WHEN** a local sign-in request supplies an unknown fixture key, principal
  ID, email, scope, role, capability, or altered lifecycle fact
- **THEN** Office Graph MUST reject the request without resolving or issuing a
  session for the caller-selected identity

### Requirement: Local development login uses seeded identity facts

Office Graph SHALL resolve a local-development selection only to an exact,
previously seeded identity fixture and SHALL issue a session through the normal
Identity and Authorization boundaries.

#### Scenario: Eligible seeded fixture is selected

- **WHEN** the developer selects an active seeded owner, workspace
  administrator, or member fixture
- **THEN** Office Graph MUST resolve the fixture's exact principal, external
  identity link, organization, and workspace, revalidate them during durable
  session issuance, and redirect to the validated return target
- **AND** subsequent product and API requests MUST use the ordinary loaded Ash
  actor and current authorization policy

#### Scenario: Disabled fixture is selected

- **WHEN** the developer selects the seeded deprovisioned fixture
- **THEN** Office Graph MUST reject login without issuing a session and MUST
  preserve bounded authentication evidence for the disabled identity basis

#### Scenario: Seeded fixture is missing or drifted

- **WHEN** a recognized fixture key no longer resolves to its exact expected
  active identity, scope, or role facts
- **THEN** Office Graph MUST fail closed and provide a bounded local instruction
  to rerun explicit fixture setup
- **AND** the login request MUST NOT repair, create, reactivate, or regrant the
  fixture

### Requirement: Local login coexists with external providers

Office Graph SHALL keep local development authentication, Authentik-compatible
OIDC, and WorkOS enterprise SSO as distinct provider choices that converge only
at Office Graph-owned session issuance.

#### Scenario: Authentik is configured during development

- **WHEN** local development authentication and generic OIDC are both
  configured
- **THEN** the login page MUST let the developer explicitly start the existing
  Authentik-compatible OIDC flow without weakening its state, nonce, PKCE, or
  callback validation

#### Scenario: Enterprise user starts WorkOS login

- **WHEN** a human selects an active WorkOS enterprise connection
- **THEN** Office Graph MUST continue to use the connection-bound WorkOS route
  and MUST NOT route that login through the local development provider

### Requirement: Browser authentication failures are correctly typed

Office Graph SHALL return browser authentication failures with an explicit safe
content type and bounded actionable text.

#### Scenario: Authentication provider is unavailable

- **WHEN** browser login cannot start because its selected provider is missing,
  incomplete, or unavailable
- **THEN** Office Graph MUST return a correctly typed HTML or plain-text error
  response that browsers render instead of downloading as an opaque file
- **AND** the response MUST NOT expose provider secrets, configuration values,
  raw payloads, tokens, database errors, or stack traces
