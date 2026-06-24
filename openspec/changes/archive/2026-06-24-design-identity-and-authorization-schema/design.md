## Context

Office Graph already accepts a hybrid enterprise authorization model: RBAC,
ABAC, relationship checks, capabilities, explicit grants, scoped visibility,
agent permission intersections, explainable decisions, and relational policy
facts. The missing piece is a concrete schema inventory that future Ash/Ecto
work can use without turning authorization into JSON claims, controller checks,
or scattered per-domain permission tables.

This design owns the persistence inventory for identity and authorization facts.
It does not own authentication mechanics, login flows, sessions, token
issuance, or secret-value storage. Those belong to
`design-identity-and-authentication` and the future `SecretStore` boundary.

## Goals / Non-Goals

**Goals:**

- Name the table families required before the first backend migrations.
- Separate principals from human profile data.
- Store external identity links in a provider-neutral form.
- Represent scopes, scope hierarchy, scope inheritance, and scope moves with
  auditable relational rows.
- Represent roles, capabilities, assignments, custom roles, explicit grants,
  team/group/department/org-unit facts, sensitivity labels, and policy bundle
  versions as typed facts.
- Store credential metadata without secret values.
- Preserve queryable, explainable authorization decisions without copying large
  policy blobs into every decision record.

**Non-Goals:**

- No Phoenix, Ash, Ecto, migration, API, frontend, Oban, or runtime code.
- No login, browser session, refresh-token, or first-admin bootstrap mechanics.
- No final column list for every table.
- No Postgres RLS-first policy engine.
- No customer-facing role-builder UI design.
- No secret value storage implementation.

## Decisions

### 1. Make identity and authorization facts concrete

The first schema cut must have a relational inventory for the facts that
governance policies evaluate. The required table families are:

- `principals`: unified actor records for human users, agents, service
  accounts, integration installations, webhook sources, external executors,
  and system jobs.
- `principal_profiles`: human display/profile data that should not live on the
  generic principal row.
- `external_identity_links`: provider-neutral links from principals to OIDC,
  SAML, SCIM, IdP, provider, or external executor identities.
- `authorization_scopes`: typed scopes for organization, workspace,
  initiative, workstream, department, org unit, team, component, repository,
  service, integration, external source, artifact, and resource boundaries.
- `authorization_scope_paths`: closure rows used to explain and evaluate
  ancestor/descendant inheritance.
- `capabilities`: stable capability identifiers and descriptions.
- `roles`: system and custom role records with organization ownership and
  lifecycle.
- `role_capabilities`: capability membership for each role.
- `role_assignments`: principal-to-role facts at a scope, with inheritance
  mode and operation correlation.
- `explicit_grants`: exceptional capability facts for a principal at a resource
  or scope.
- `teams`, `team_memberships`, `groups`, `group_mappings`, `departments`, and
  `org_units`: organization structure facts when policy needs them.
- `resource_sensitivity_labels` and `resource_sensitivity_assignments`:
  sensitivity facts separate from visibility scope.
- `policy_bundles` and `policy_bundle_versions`: immutable rule-set versions,
  digests, effective periods, and component policy references.
- `policy_component_versions`: immutable component policy versions and digests
  referenced by bundle versions and sensitive decision records.
- `authorization_fact_versions`: optional anchors for sensitive decisions that
  must reconstruct exact fact inputs.
- `authorization_decision_records`: sensitive authorization decisions that
  reference policy and fact versions without replacing the audit log.
- manager, owner, and data-owner relationship facts when policy needs them for
  approver eligibility, separation of duties, ownership, or escalation.
- `credential_metadata`: secret-free metadata for credentials, tokens, webhook
  secrets, signing keys, and model provider keys.
- `credential_allowed_scopes` and `credential_allowed_capabilities` or
  equivalent normalized joins when a credential is limited to multiple scopes
  or capability families.

This inventory is intentionally a table-family inventory rather than migration
syntax. Future implementation may split or rename tables where the accepted
domain model requires it, but it must preserve the facts and ownership
boundaries above.

### 2. Keep authentication mechanics separate

A principal is the identity and authorization actor seen by policy. How a human
logs in, how a browser session maps to a principal, how a service account
receives a token, and how an agent gets runtime credentials are authentication
mechanics. Those belong to `design-identity-and-authentication`.

The handoff contract is:

- authentication resolves or creates a valid `principal_id`
- external identity reconciliation writes `external_identity_links`
- credential issuance writes secret-free `credential_metadata`
- authorization evaluates the principal, scopes, capabilities, roles, grants,
  labels, policy bundle version, and relevant organization facts

### 3. Use adjacency list plus closure table for scopes

`authorization_scopes` should store each scope and its immediate parent when
one exists. `authorization_scope_paths` should store ancestor scope, descendant
scope, depth, inheritance mode, lifecycle state, provenance, and operation
correlation.

This combined model gives future implementation:

- a simple source of truth for direct parentage
- efficient descendant and ancestor queries
- stable rows for authorization explanations
- auditable updates when a scope moves
- a place to record inheritance mode changes without parsing string paths

`ltree` is not the first design because it ties policy inheritance to string
paths and makes scope moves harder to audit and explain. A materialized path
alone is not the first design because inherited permission explanations need
stable ancestor/descendant rows and lifecycle state.

### 4. Make scope moves domain actions

Moving a scope is a governed domain action, not a direct update to a parent id.
The action must:

- validate that the move is allowed by tenant, scope type, policy, and cycle
  rules
- write an operation correlation record
- update the direct parent relationship
- recalculate affected closure rows in the same governed operation
- record before/after inheritance impact for assignments, grants, labels, and
  cached explanations
- invalidate or recompute cached authorization explanations
- preserve enough audit detail to explain who moved the scope, why, and which
  principals/resources were affected

### 5. Treat organization structure as policy facts when policy needs it

Departments, org units, teams, groups, and memberships can be display objects,
but they become authorization facts when they drive scope inheritance,
eligible approvers, role assignment, separation of duties, data ownership, or
agent context expansion. The schema must not collapse all of these into one
generic group table before policy semantics are understood.

External groups and SCIM groups are not direct product authority. They map into
internal teams, role assignments, custom roles, grants, or capabilities through
typed mapping rows.

Manager, owner, and data-owner relationships are also policy facts when they
drive approval eligibility, escalation, separation of duties, or resource
stewardship. They should be typed relationship facts with lifecycle and
operation provenance, not inferred solely from names, comments, or external
group labels.

### 6. Split visibility scope from sensitivity labels

Visibility comes from tenant/scope columns, projection policy, and inherited
scope paths. Sensitivity comes from typed labels assigned to resources or
inherited from scopes. The inventory therefore needs sensitivity labels and
assignments, but it should not reintroduce mixed classification values such as
`workspace_scoped` beside `secret` in one enum.

Initial sensitivity labels should include `normal`, `confidential`, `secret`,
`source_code`, `customer_sensitive`, `finance_sensitive`, `legal_sensitive`,
and `security_sensitive`.

### 7. Version policy rules separately from facts

Policy bundle versions are immutable rule-set versions. Component policy
versions hold the immutable pieces that make up a bundle, such as
organization, workspace, sensitivity, approval, integration, agent, and
autonomy policy components. Role assignments, custom-role definitions, group
memberships, ownership links, sensitivity assignments, grants, manager
relationships, scope paths, and agent capabilities are facts. Sensitive
authorization decision records should reference the effective policy bundle
version, relevant component policy versions or digests, and, when necessary,
an `authorization_fact_versions` anchor that points to the relevant fact
versions without embedding a large policy or fact blob in the decision.

### 8. Store credential metadata, never secret values

`credential_metadata` should record provider or tool, owner principal,
organization, lifecycle state, fingerprint or external reference,
secret-store key/reference, rotation metadata, revocation metadata,
last-used/audit linkage, classification/sensitivity, and audit/operation
links. Allowed scopes and capabilities should be normalized into joins such as
`credential_allowed_scopes` and `credential_allowed_capabilities` when a
credential spans more than one scope or capability family.

The secret value itself belongs behind a `SecretStore` boundary. Product tables
must be sufficient to authorize, audit, rotate, revoke, and explain credential
use without exposing the secret as normal product data.

## Open Questions

- Which seeded capabilities ship in the first migration versus seeds after the
  first walking skeleton?
- Which authorization explanation caches, if any, are needed before volume
  proves they are necessary?
- Which fact families need full temporal version rows in v1 versus operation
  correlation plus current-state rows?

## Handoff To Other Changes

- `design-enterprise-governance` owns policy semantics, agent permission
  formula, approval semantics, and user-facing governance vocabulary.
- `design-persistence-model` owns general persistence rules, graph identity,
  JSON policy, indexing posture, and first migration cut.
- `design-identity-and-authentication` owns login, sessions, tokens, service
  credential issuance, local identity lab, and bootstrap.
- `design-revision-audit-soft-delete` owns durable audit/revision records and
  operation-correlation field ownership.
- `design-code-organization-and-boundaries` owns the future Boundary contexts
  and public APIs that implement this model.
