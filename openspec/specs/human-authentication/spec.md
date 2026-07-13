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
