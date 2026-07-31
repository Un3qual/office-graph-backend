## MODIFIED Requirements

### Requirement: Administrators bind provider directories through the owning boundary

Office Graph SHALL provide an authorized, operation-correlated enterprise
identity command that binds a provider directory to an existing enterprise
connection.

#### Scenario: Authorized administrator binds a directory

- **WHEN** an administrator with `enterprise_identity.manage` authority at the
  connection's exact scope supplies a stable provider directory identifier and
  lifecycle timestamp
- **THEN** the owning Ash action MUST create one directory binding linked to
  that connection and operation

#### Scenario: Exact directory binding is replayed

- **WHEN** the same operation repeats the same provider directory, connection,
  lifecycle status, and provider update time
- **THEN** Office Graph MUST return the existing binding without changing it or
  creating a duplicate

#### Scenario: Directory binding replay changes material input

- **WHEN** the same operation and provider directory are replayed with a
  different lifecycle status or provider update time
- **THEN** Office Graph MUST return a deterministic command-idempotency conflict
  and MUST preserve the existing binding unchanged

#### Scenario: Concurrent or cross-scope directory binding is attempted

- **WHEN** concurrent commands target the same provider directory or a caller
  targets a connection outside its authorized scope
- **THEN** Office Graph MUST retain one logical binding and MUST fail closed
  rather than rebinding or exposing the foreign directory

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

#### Scenario: Last shared directory basis is deprovisioned

- **WHEN** a directory-created principal is shared by additional directory
  users and the last accepted active directory identity basis is disabled or
  deleted
- **THEN** Office Graph MUST determine principal provenance from retained
  directory history rather than the last user's per-link origin and MUST disable
  the principal and matching SSO access
