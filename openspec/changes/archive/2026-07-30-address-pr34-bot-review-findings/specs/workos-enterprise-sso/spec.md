## ADDED Requirements

### Requirement: WorkOS transport authenticates the remote server

Office Graph SHALL authenticate the TLS peer and requested hostname before
sending WorkOS credentials or accepting a WorkOS response.

#### Scenario: Production WorkOS request uses HTTPS

- **WHEN** the production WorkOS HTTP adapter sends an authorization or token
  request
- **THEN** it MUST require a certificate chain rooted in the runtime trust
  store and MUST verify the certificate against the requested HTTPS hostname

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
