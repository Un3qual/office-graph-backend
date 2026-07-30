# workos-enterprise-sso Specification

## Purpose

Define standalone WorkOS enterprise SSO as an external identity exchange while
Office Graph retains ownership of principals, sessions, authorization, and
identity lifecycle.

## Requirements

### Requirement: WorkOS SSO does not own Office Graph sessions

Office Graph SHALL use WorkOS standalone enterprise SSO only to authorize an
external identity exchange and SHALL NOT adopt AuthKit, WorkOS-hosted sessions,
or WorkOS authorization as product authority.

#### Scenario: Enterprise login succeeds

- **WHEN** WorkOS returns a valid SSO profile for a configured enterprise
  connection
- **THEN** Office Graph MUST reconcile that profile to its own principal and
  external identity link, resolve current internal scope and authorization
  facts, and issue its own durable `human_web` session

#### Scenario: WorkOS returns authentication material

- **WHEN** the WorkOS code exchange returns an authorization code, access
  token, profile, or raw identity-provider attributes
- **THEN** Office Graph MUST retain only bounded stable identity fields and
  MUST NOT persist the code, token, raw attributes, AuthKit cookie, or external
  capability claim

### Requirement: WorkOS transport authenticates the remote server

Office Graph SHALL authenticate the TLS peer and requested hostname before
sending WorkOS credentials or accepting a WorkOS response.

#### Scenario: Production WorkOS request uses HTTPS

- **WHEN** the production WorkOS HTTP adapter sends an authorization or token
  request
- **THEN** it MUST require a certificate chain rooted in the runtime trust
  store and MUST verify the certificate against the requested HTTPS hostname

### Requirement: WorkOS login is bound to one enterprise connection

Office Graph SHALL bind each WorkOS login transaction to one active internal
enterprise connection before redirecting the browser.

#### Scenario: WorkOS login begins

- **WHEN** an unauthenticated human selects an active WorkOS enterprise
  connection
- **THEN** Office Graph MUST create random state and a one-time server-backed
  transaction guard, capture the internal connection and callback URI, and
  send the bound WorkOS organization ID to the WorkOS authorization endpoint

#### Scenario: Callback tries to change tenant

- **WHEN** a WorkOS callback or browser parameter names a different provider,
  enterprise connection, WorkOS organization, Office Graph organization, or
  workspace
- **THEN** Office Graph MUST ignore the untrusted selection and use only the
  connection captured in the one-time login transaction

#### Scenario: WorkOS callback is replayed or invalid

- **WHEN** the callback state is absent or mismatched, the transaction guard is
  absent or expired, the code exchange fails, or the same callback is replayed
- **THEN** Office Graph MUST fail closed without issuing a session and MUST
  preserve bounded authentication evidence when a trace is available

### Requirement: WorkOS profile reconciliation is provider-bound

Office Graph SHALL normalize a WorkOS SSO profile to a connection-scoped
subject and verified email before invoking provider-neutral external identity
reconciliation.

#### Scenario: Known WorkOS subject returns

- **WHEN** a normalized WorkOS organization, connection, and IdP subject match
  an active `workos_sso` external identity link
- **THEN** Office Graph MUST resolve the same active principal regardless of
  changed display fields and MUST re-check current directory lifecycle when
  that enterprise connection requires provisioning

#### Scenario: WorkOS identifier conflicts

- **WHEN** a new or existing WorkOS SSO profile conflicts with a directory
  user, principal, verified email, or external subject binding
- **THEN** Office Graph MUST preserve a deterministic review or conflict state
  and MUST NOT silently relink the identity or issue a session

### Requirement: WorkOS SSO is optional in local verification

Office Graph SHALL keep WorkOS adapters replaceable and SHALL NOT require
hosted WorkOS access for normal development, tests, or canonical verification.

#### Scenario: Canonical verification tests WorkOS SSO

- **WHEN** local or CI tests exercise WorkOS login
- **THEN** they MUST use a deterministic fake SSO and HTTP adapter and MUST NOT
  require a WorkOS account, API key, network request, or hosted callback

#### Scenario: WorkOS configuration is absent

- **WHEN** WorkOS client, credential, connection, or adapter configuration is
  incomplete
- **THEN** WorkOS login MUST be unavailable without disabling the configured
  local generic OIDC path

### Requirement: Organization-wide mapped identities enter a selected workspace

Office Graph SHALL allow an active organization-wide external group-role
mapping to satisfy a trusted preferred workspace in the same organization
while retaining workspace-bound human sessions.

#### Scenario: Organization-wide mapped member completes WorkOS login

- **WHEN** the transaction-bound WorkOS connection selects a workspace and the
  reconciled principal has only an active organization-wide mapping for that
  organization
- **THEN** Office Graph MUST resolve the preferred workspace, issue its own
  workspace-bound session, and validate that session against the inherited
  organization authority

#### Scenario: Organization-wide mapping belongs to another organization

- **WHEN** the preferred workspace scope names an organization different from
  the active organization-wide mapping
- **THEN** the mapping MUST NOT satisfy login scope selection or session
  validation

### Requirement: WorkOS session lifecycle remains connection-bound

Office Graph SHALL retain the internal enterprise connection that issued each
WorkOS session and SHALL use that provenance for validation and logout.

#### Scenario: Issuing connection is disabled

- **WHEN** an administrator disables the enterprise connection that issued an
  existing WorkOS session
- **THEN** the next session validation MUST fail closed and revoke the local
  session even if the principal retains unrelated direct workspace authority

#### Scenario: WorkOS user logs out

- **WHEN** a `workos_sso` session is logged out while generic Authentik OIDC is
  also configured
- **THEN** Office Graph MUST revoke the local WorkOS session and MUST NOT
  construct or visit the unrelated Authentik logout endpoint
