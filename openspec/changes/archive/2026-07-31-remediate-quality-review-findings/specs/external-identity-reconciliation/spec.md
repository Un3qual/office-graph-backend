## MODIFIED Requirements

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
