# enterprise-directory-sync Specification

## Purpose

Define provider-neutral enterprise directory synchronization, verified event
ingestion, replay-safe lifecycle application, identity reconciliation, and
explicit external-group role mapping.

## Requirements

### Requirement: Enterprise directory state is typed and provider-neutral

Office Graph SHALL represent enterprise connections, directories, users,
groups, memberships, and external-group role mappings through typed relational
resources rather than WorkOS-specific columns or queryable raw payload JSON.

#### Scenario: WorkOS directory is bound

- **WHEN** an administrator binds a WorkOS organization and directory to an
  Office Graph organization and optional workspace
- **THEN** Office Graph MUST persist the exact provider identities, internal
  scope, lifecycle, and operation provenance through owning Ash actions

#### Scenario: Directory user or group is synchronized

- **WHEN** a WorkOS event describes a user, group, or membership
- **THEN** Office Graph MUST persist its stable provider identifiers, bounded
  typed fields, lifecycle, provider update time, and typed relationships
  without promoting unmodeled raw attributes into product columns

#### Scenario: Membership is removed and later restored

- **WHEN** the same external user leaves and later rejoins the same external
  group
- **THEN** Office Graph MUST retain the removed membership provenance and
  permit exactly one current active membership through an in-table lifecycle
  state and ordinary Ash identity

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

### Requirement: WorkOS webhooks are verified before ingestion

Office Graph SHALL verify the WorkOS timestamped webhook signature over the
exact raw request body before decoding or trusting event content.

#### Scenario: Signed WorkOS event is received

- **WHEN** the signature is valid within the configured clock-skew tolerance
  and the event maps to one active known directory
- **THEN** Office Graph MUST derive tenant scope from the directory binding,
  archive the exact delivery, record one operation and sync event, and enqueue
  durable processing

#### Scenario: Signature or directory is invalid

- **WHEN** the signature is missing, malformed, stale, or incorrect, or the
  event names no active bound directory
- **THEN** Office Graph MUST reject the delivery without creating or changing
  a directory user, group, membership, principal, external identity link, or
  role mapping

#### Scenario: Payload contains Office Graph scope fields

- **WHEN** a WorkOS payload includes or is modified to include internal
  organization, workspace, principal, role, or capability identifiers
- **THEN** Office Graph MUST ignore those untrusted fields and use only the
  server-side directory binding and explicit internal mapping records

### Requirement: Present directory fields are validated strictly

Office Graph SHALL distinguish an absent optional WorkOS directory field from
a present field whose type, length, or normalized value is invalid.

#### Scenario: Optional directory field is absent

- **WHEN** a supported directory event omits an optional bounded profile field
- **THEN** normalization MUST accept the field as absent

#### Scenario: Optional directory field is malformed

- **WHEN** a supported directory event supplies an optional field with the
  wrong type, a blank normalized value, or a value beyond its byte limit
- **THEN** Office Graph MUST reject the delivery before persistence or enqueue

### Requirement: Directory deliveries are replay-safe and ordered

Office Graph SHALL process one logical WorkOS directory event once and SHALL
not allow stale or earlier accepted provider state to overwrite a newer
accepted state.

#### Scenario: Identical event is delivered twice

- **WHEN** the same provider event ID and content hash are received again
- **THEN** Office Graph MUST return a successful replay result without
  enqueueing or applying a second mutation

#### Scenario: Event ID content changes

- **WHEN** an existing provider event ID is reused with a different content
  hash
- **THEN** Office Graph MUST record or return a deterministic conflict and
  MUST NOT apply the changed payload

#### Scenario: Older event arrives after newer event

- **WHEN** a user, group, or membership event has an older provider update time
  than the current accepted record
- **THEN** Office Graph MUST preserve the newer state and complete the older
  event with a bounded stale result

#### Scenario: Distinct events have equal provider timestamps

- **WHEN** distinct user, group, or membership events have the same provider
  update time
- **THEN** Office Graph MUST use durable receipt order and provider event
  identity as a deterministic tie-breaker so the later accepted state wins
  regardless of worker execution order

#### Scenario: Worker fails after receipt

- **WHEN** asynchronous application of an accepted directory event fails
- **THEN** Oban MUST retry the idempotent event action without creating
  duplicate resources or bypassing the event's original operation and archive
  provenance

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

### Requirement: Exact directory identities recover after reprovisioning

Office Graph SHALL restore a retained directory identity after a newer active
event only when the provider tenant, provider subject, provider identity,
verified email, linked principal, and lifecycle state still identify the same
accepted basis.

#### Scenario: Exact directory-created identity is reprovisioned

- **WHEN** an active directory identity is deprovisioned and a newer active event
  repeats the same trusted provider and identity basis without conflicts
- **THEN** Office Graph MUST reactivate the retained directory link and its
  eligible directory-created human principal in place rather than creating a
  replacement or requiring review

#### Scenario: Reprovisioned identity basis conflicts

- **WHEN** a newer active event changes the provider tenant, provider subject,
  provider identity, verified email, retained principal, or conflicts with
  another email-linked identity
- **THEN** Office Graph MUST retain deterministic review-required behavior and
  MUST NOT reactivate the retained principal or disabled link

### Requirement: External groups grant only explicitly mapped roles

Office Graph SHALL treat active directory group membership as an authorization
fact only through an active explicit mapping to an existing internal role and
exact scope.

#### Scenario: Mapped member requests a capability

- **WHEN** an active principal belongs to an active directory group whose
  active mapping names a role with the requested capability in the target
  organization and workspace
- **THEN** Office Graph MUST include that role in current authorization and
  login-scope evaluation without creating capability names from external data

#### Scenario: Group is unmapped or inactive

- **WHEN** a group has no active mapping, its mapping targets another scope,
  or its directory, user, group, membership, or connection is inactive
- **THEN** the external group MUST grant no role, capability, login scope, or
  session authority

#### Scenario: Membership or mapping is removed

- **WHEN** a previously effective membership or group-role mapping becomes
  inactive
- **THEN** the mapped authority MUST be absent from the next authorization
  evaluation without deleting unrelated direct role assignments

### Requirement: Organization mappings inherit into workspace authorization

Office Graph SHALL treat an active external group-role mapping with no
workspace as organization-wide authority.

#### Scenario: Organization-wide mapped member selects login scope

- **WHEN** an active mapped member has an active organization-wide mapping
- **THEN** login-scope discovery MUST include the organization with a nil
  workspace

#### Scenario: Organization-wide mapped member acts in a workspace

- **WHEN** an active mapped member requests a mapped capability in a workspace
  belonging to the mapping's organization
- **THEN** the organization-wide mapping MUST contribute the mapped role in
  that workspace

#### Scenario: Workspace mapping targets another workspace

- **WHEN** an active mapping names a different non-nil workspace
- **THEN** it MUST NOT grant authority in the requested workspace

### Requirement: Directory Sync has deterministic local contract coverage

Office Graph SHALL provide fake WorkOS SSO and directory adapters plus signed
event fixtures that cover the supported enterprise identity contract without
hosted dependencies.

#### Scenario: Directory contract suite runs

- **WHEN** canonical verification exercises directory synchronization
- **THEN** tests MUST cover user create, update, deactivate and delete; group
  create, rename and delete; membership add and remove; duplicate and
  out-of-order events; invalid signatures and payloads; identity conflicts;
  SSO reconciliation; and group mapping authorization

#### Scenario: Hosted compatibility is checked

- **WHEN** a developer opts into a credentialed WorkOS sandbox smoke test
- **THEN** that test MUST remain separate from canonical verification and MUST
  not persist provider secrets or raw profile attributes as product data

### Requirement: Organization-wide mapping management preserves explicit scope

Office Graph SHALL distinguish an omitted management workspace from an
explicitly organization-wide external group-role mapping and SHALL require
authority at the target scope before persistence.

#### Scenario: Authorized administrator creates an organization-wide mapping

- **WHEN** an administrator with organization-scoped
  `enterprise_identity.manage` authority explicitly creates a mapping with no
  workspace
- **THEN** the authorized management action MUST persist `workspace_id: nil`
  rather than replacing it with the administrator's session workspace

#### Scenario: Organization-wide mapping lifecycle changes

- **WHEN** an administrator explicitly targets an existing organization-wide
  mapping for disablement or another supported lifecycle transition
- **THEN** Office Graph MUST require organization-scoped management authority,
  update the nil-scoped record, and leave workspace-scoped mappings unchanged

#### Scenario: Workspace authority targets organization-wide scope

- **WHEN** an administrator has management authority only in the current
  workspace and explicitly targets organization-wide scope
- **THEN** Office Graph MUST reject the create or lifecycle mutation

#### Scenario: Workspace connection cannot back an organization-wide mapping

- **WHEN** an organization-authorized administrator targets organization-wide
  scope for a group owned by a workspace-scoped enterprise connection
- **THEN** Office Graph MUST reject the mapping instead of widening the
  connection's directory authority
