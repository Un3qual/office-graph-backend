## Context

Office Graph needs enterprise-ready identity from the beginning, but identity
has two separate concerns:

- `design-identity-and-authorization-schema` owns durable facts such as
  principals, external identity links, authorization scopes, roles, grants,
  policy fact versions, sensitivity labels, and credential metadata.
- This change owns mechanics: login, session verification, token posture,
  service credential issuance, external identity reconciliation, first-org
  bootstrap, and local identity-lab fixtures.

Authentication must produce a trustworthy `principal_id` and operation context.
It must not bake product permissions into sessions or tokens. Authorization is
re-evaluated against durable facts and policy versions.

## Goals / Non-Goals

**Goals:**

- Define the first human login path and local development posture.
- Define session and token behavior without turning claims into permission
  storage.
- Define credential issuance, proof, rotation, revocation, and audit linkage
  for service accounts, webhook sources, integration installations, internal
  agents, and external executors.
- Define SSO/SCIM/provider identity reconciliation and conflict states.
- Define first-organization and first-owner bootstrap.
- Preserve future extraction of authentication/identity into a reusable
  internal library or package.

**Non-Goals:**

- No Phoenix, Ash, Ecto, migration, API, frontend, Oban, identity-lab
  container, or runtime implementation.
- No final passwordless/email-password product decision for hosted production.
- No final SCIM adapter implementation.
- No final SecretStore provider implementation.
- No product authorization semantics beyond producing authenticated principal
  context for the authorization boundary.

## Decisions

### 1. Use authentik OIDC as the primary local human-login fixture

The first supported human login path should be local development login through
the identity lab, with authentik OIDC as the primary local fixture. Optional
SAML and Keycloak paths can exist as compatibility fixtures, but they are not
first backend blockers.

Human login resolves to a `principal_id` by reconciling provider subject,
provider tenant, verified identifiers, account-linking state, and conflict
state through `external_identity_links`. SSO claims may influence internal
teams, group mappings, scoped roles, grants, or review states only through
configured mapping policy. External claim names must never become direct Office
Graph capabilities.

### 2. Keep sessions and tokens thin

Browser sessions and tokens should identify the authenticated principal, auth
method, external identity link used when applicable, selected organization or
workspace context, issue/expiry times, revocation state, and trace metadata.
They should not store product permissions, capability lists, full group lists,
or durable policy decisions.

Every governed action must re-evaluate authorization using the current
principal, scopes, capabilities, role assignments, grants, sensitivity labels,
credential metadata, and effective policy bundle versions. Sensitive session
events such as login, logout, token issuance, refresh, revocation, suspicious
reuse, and tenant switching should emit audit-relevant auth events.

### 3. Reconcile SCIM and SSO into one principal

SSO authenticates a current login. SCIM provisions lifecycle and group facts
over time. Both inputs must converge on the same principal through
`external_identity_links` and explicit reconciliation policy.

The reconciliation process must handle:

- new external identity
- explicit account linking
- duplicate verified identifier
- provider-subject change
- disabled or deprovisioned user
- external group rename/delete
- conflicting group or role mappings
- local account that predates enterprise SSO

Conflicts must enter deterministic conflict or admin review states rather than
silently creating ambiguous principals.

### 4. Treat non-human credentials as principal mechanics

Service accounts, webhook sources, integration installations, internal agents,
external executors, and system jobs are principals. This change defines how
their credentials are issued, verified, rotated, revoked, and scoped; the
schema inventory owns the durable principal and `credential_metadata` records.

Credential mechanics must preserve:

- owner principal or owning integration/source
- organization and allowed scopes
- allowed capabilities or tool families
- SecretStore reference and fingerprint
- issue, expiry, rotation, revocation, and last-use metadata
- authority basis for automatic or delegated use
- operation correlation and audit linkage

Agent credentials are not user sessions with extra powers. Agent runs should
carry an agent principal, delegator or trigger authority basis, autonomy
envelope, allowed scopes/tools/sensitivity labels, and temporary grants only
when approved by policy.

### 5. Bootstrap first organization and first owner explicitly

The first backend needs a bootstrap command or setup path that creates:

- first organization
- first organization owner principal and principal profile
- first workspace
- seeded system roles and capability assignments
- initial policy bundle version
- initial session, invitation, or login handoff for the owner

Development/test bootstrap should be idempotent. Production bootstrap should be
single-use or tightly controlled and disabled after the first owner is
established. Bootstrap must be audited, operation-correlated, and separate from
later break-glass or account-recovery flows.

### 6. Build a local identity lab before hosted IdP dependency

Normal development and CI should not require paid Entra, Okta, or another
hosted IdP. The local identity lab should include:

- authentik as the primary OIDC/SAML/SCIM fixture for local E2E
- optional Keycloak compatibility checks for OIDC/SAML
- a repo-owned fake SCIM client for deterministic CI contract tests
- seeded org owner, workspace admin, member, deprovisioned user, duplicate
  verified identifier, group mapping conflict, service account, webhook source,
  and agent principal scenarios

Hosted vendor smoke tests may be optional later and should not block normal
local development.

### 7. Keep authentication/identity library-ready

Authentication/identity should be an internal Boundary context with boring
public contracts: session verification, external identity reconciliation,
credential issuance/revocation, auth event emission, and SecretStore adapter
calls. Phoenix controllers, Absinthe resolvers, JSON API handlers, webhooks,
Oban jobs, and agent adapters should produce or consume authenticated
principal/session context through those contracts rather than reaching into
private modules.

Office Graph-specific graph semantics should stay behind typed inputs or
adapter contracts so identity/authentication remains extractable later.

## Handoff To Other Changes

- `design-identity-and-authorization-schema` owns durable principal, external
  identity link, role/grant/scope, policy fact, and credential metadata table
  families.
- `design-enterprise-governance` owns policy semantics, SSO/SCIM posture,
  custom-role governance, credential-security semantics, and audit posture.
- `design-code-organization-and-boundaries` owns module layout, Boundary
  exports, entrypoint contracts, and SecretStore behaviour placement.
- `design-ingestion-and-integrations` will consume webhook-source and
  integration-installation authentication mechanics for adapter contracts.
