## MODIFIED Requirements

### Requirement: Directory users reconcile to durable principals

Office Graph SHALL reconcile an active directory user to one human principal
and one `workos_directory` external identity link through deterministic
provisioning policy.

#### Scenario: New active directory user is provisioned

- **WHEN** one valid directory user has a unique normalized verified email and
  no incompatible principal or link
- **THEN** Office Graph MUST create or reuse one human principal, link the
  directory subject, preserve bounded profile fields, and make a later matching
  WorkOS SSO profile resolve to that same principal

#### Scenario: Directory identity is ambiguous

- **WHEN** a directory user's verified email, IdP ID, provider user ID, or
  existing external links identify incompatible principals
- **THEN** Office Graph MUST persist a deterministic review state and MUST NOT
  merge, authenticate, or grant mapped authority to the ambiguous user

#### Scenario: Directory user is deprovisioned

- **WHEN** WorkOS disables or deletes a directory user
- **THEN** Office Graph MUST disable that directory identity in-table, retain
  historical provenance, and disable matching WorkOS SSO access and a
  directory-created principal only when no other accepted active directory
  identity basis remains for that principal and provider tenant
- **AND** existing affected sessions MUST fail on their next validation

#### Scenario: Exact directory user is restored

- **WHEN** a newer active WorkOS event names the same retained provider tenant,
  directory subject, provider identity, normalized verified email, and principal
- **THEN** Office Graph MUST reactivate that directory link and its eligible
  directory-created principal in place without creating a replacement identity
- **AND** any incompatible subject, email, tenant, or principal state MUST remain
  review-required
