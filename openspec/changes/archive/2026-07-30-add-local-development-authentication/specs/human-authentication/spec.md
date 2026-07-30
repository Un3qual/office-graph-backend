## ADDED Requirements

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
