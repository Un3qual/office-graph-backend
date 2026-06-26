## ADDED Requirements

### Requirement: SSO And SCIM Reconcile To One Principal
Office Graph SHALL reconcile login-time SSO identities and provisioning-time
SCIM identities into one internal principal when policy proves they represent
the same actor.

#### Scenario: Same person arrives through SSO and SCIM
- **WHEN** a user is provisioned through SCIM and later logs in through SSO
- **THEN** Office Graph MUST reconcile both inputs through external identity
  links, provider tenant, provider subject, verified identifiers, and
  configured account-linking policy

#### Scenario: Duplicate verified identifier appears
- **WHEN** two external identities claim the same verified email, username, or
  provider identifier incompatibly
- **THEN** Office Graph MUST enter a deterministic conflict or admin review
  state rather than silently linking the identities

#### Scenario: External group mapping changes
- **WHEN** SCIM or IdP group data creates, renames, removes, or changes
  membership for a mapped group
- **THEN** Office Graph MUST update internal team, role assignment, custom
  role, grant, or review-state facts according to mapping policy and preserve
  provisioning provenance

### Requirement: Deprovisioning Preserves Provenance
Office Graph SHALL prevent future access for deprovisioned identities while
preserving historical graph, audit, run, approval, and credential provenance.

#### Scenario: User is deprovisioned
- **WHEN** an external identity is disabled or a SCIM event deprovisions a user
- **THEN** Office Graph MUST disable future authentication and credential use
  for affected principals while retaining historical ownership, authorship,
  run, approval, audit, and revision references
