# external-identity-reconciliation Specification

## Purpose
Define how SSO and SCIM identities reconcile to one durable principal.
## Requirements
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

### Requirement: Durable OIDC Identity Link State

Office Graph SHALL persist provider-neutral OIDC reconciliation state keyed by
provider, provider tenant or issuer, and provider subject.

#### Scenario: Known OIDC subject returns

- **WHEN** a validated OIDC subject matches an active external identity link
  whose principal is active
- **THEN** Office Graph MUST resolve the same durable principal, MUST update
  bounded last-authenticated identity metadata, and MUST NOT relink the subject
  based only on a changed display identifier

#### Scenario: Unknown verified identifier cannot be linked

- **WHEN** a validated OIDC subject has no exact link and its verified
  identifier names no eligible principal
- **THEN** Office Graph MUST persist a deterministic `review_required` link
  state with a bounded reason and MUST refuse a session

#### Scenario: Verified identifier conflicts

- **WHEN** a new OIDC subject's verified identifier conflicts with an
  incompatible external link or principal
- **THEN** Office Graph MUST persist or return a deterministic conflict/review
  outcome and MUST NOT silently attach either identity

### Requirement: External identity lifecycle preserves principal ownership

Office Graph SHALL keep the principal ownership of an existing external
identity link immutable through generic lifecycle transitions.

#### Scenario: External identity lifecycle changes

- **WHEN** an existing external identity link becomes active, disabled, or
  review-required
- **THEN** the lifecycle action MUST preserve its current principal and MUST
  NOT accept a replacement principal identifier

#### Scenario: Existing email links have no compatible principal

- **WHEN** reconciliation finds existing verified-email links but no compatible
  principal candidate
- **THEN** it MUST fail closed with the bounded
  `verified_identifier_conflict` review reason

### Requirement: External Lifecycle Revalidation

Office Graph SHALL re-check external identity lifecycle state at login and
while loading a linked human session.

#### Scenario: External link is disabled before login

- **WHEN** a known external identity link is disabled or marked for review
- **THEN** future login MUST fail closed without changing historical principal
  or link provenance

#### Scenario: External link is disabled during a session

- **WHEN** an external identity link is disabled after a human session was
  issued
- **THEN** the next use of that session MUST fail closed even when the cookie
  and session row are otherwise unexpired and unrevoked

### Requirement: WorkOS SSO and directory identities converge safely

Office Graph SHALL reconcile WorkOS login-time SSO profiles and
provisioning-time directory users to one durable principal while retaining
distinct provider-bound external identity links.

#### Scenario: Directory user exists before first SSO login

- **WHEN** an active `workos_directory` link and later `workos_sso` profile
  have compatible provider organization, IdP identity, and verified email
- **THEN** both external links MUST resolve to the same principal and SSO MUST
  preserve the directory link's lifecycle and provisioning provenance

#### Scenario: SSO login arrives before optional directory provisioning

- **WHEN** an enterprise connection permits SSO without required directory
  provisioning and one eligible existing principal matches the verified WorkOS
  email
- **THEN** Office Graph MAY link the SSO subject through the existing explicit
  account-linking policy without creating roles from profile attributes

#### Scenario: Required provisioning is absent

- **WHEN** an enterprise connection requires directory provisioning but the
  reconciled principal has no active matching directory user
- **THEN** Office Graph MUST refuse the SSO session with a bounded review or
  provisioning-required outcome

#### Scenario: Directory lifecycle changes after SSO login

- **WHEN** the directory user becomes disabled, deleted, conflicted, or marked
  for review
- **THEN** matching WorkOS SSO links and sessions MUST fail closed while all
  historical principal, ownership, audit, revision, and authentication
  provenance remains addressable

#### Scenario: Exact SSO subject returns after directory restoration

- **WHEN** an active restored directory basis proves the retained disabled SSO
  link has the same provider tenant, immutable subject, IdP identity, verified
  email, and principal
- **THEN** Office Graph MUST reactivate that exact SSO link in place and MUST NOT
  create or relink an identity from email alone
