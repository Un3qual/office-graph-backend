## ADDED Requirements

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

### Requirement: Directory deliveries are replay-safe and ordered

Office Graph SHALL process one logical WorkOS directory event once and SHALL
not allow stale provider state to overwrite a newer accepted state.

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
- **THEN** Office Graph MUST disable the directory identity and matching
  WorkOS SSO access in-table, make existing affected sessions fail on their
  next validation, retain historical provenance, and disable the principal
  only when no accepted active identity basis remains

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
