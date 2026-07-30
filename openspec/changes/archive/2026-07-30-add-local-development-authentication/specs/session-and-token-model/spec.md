## MODIFIED Requirements

### Requirement: Cookie-Referenced Human Sessions

Office Graph SHALL keep the durable human session as the authentication
authority and SHALL store only an opaque session identifier in the browser
cookie.

#### Scenario: Human session is issued

- **WHEN** a supported external or explicitly enabled local-development
  authentication provider resolves an eligible linked principal and internal
  scope
- **THEN** Office Graph MUST issue a `human_web` session that records principal,
  external identity link, authentication method, organization, workspace,
  issue time, expiry, source surface, and trace metadata without storing
  provider tokens, local selector keys, role names, or capability lists

#### Scenario: Browser cookie is written

- **WHEN** the human session is issued
- **THEN** the signed HTTP-only SameSite cookie MUST contain only the opaque
  durable session identifier and MUST be secure in production

## ADDED Requirements

### Requirement: Local development sessions use the normal lifecycle

Office Graph SHALL issue, validate, replace, reject, revoke, and audit
local-development human sessions through the same owning actions used by other
human authentication providers.

#### Scenario: Local development session is issued

- **WHEN** an eligible seeded fixture completes local development login
- **THEN** the durable session MUST record authentication method
  `local_development`, the exact active external identity link, and the seeded
  organization and workspace
- **AND** session issuance MUST lock and revalidate current identity facts
  before committing

#### Scenario: Local development session is reused

- **WHEN** a product, GraphQL, or JSON API request presents the local
  development session cookie
- **THEN** Office Graph MUST revalidate the current session, principal,
  external identity link, tenant scope, and authorization facts before setting
  the Ash actor

#### Scenario: Developer switches identity

- **WHEN** an authenticated developer requests an identity switch
- **THEN** Office Graph MUST revoke the current durable session before clearing
  its cookie and returning to the chooser
- **AND** it MUST NOT mutate the existing session's principal, retain the old
  session as active, or issue the next identity until the developer makes a new
  explicit selection

#### Scenario: Current session cannot be revoked

- **WHEN** durable storage prevents the current local development session from
  being revoked during a switch
- **THEN** Office Graph MUST fail closed, preserve the current cookie, and MUST
  NOT proceed to another fixture
