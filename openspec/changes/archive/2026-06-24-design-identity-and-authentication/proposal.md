## Why

The identity/authorization schema inventory defines durable facts, but Office
Graph still needs a separate design for how principals become authenticated,
how sessions and runtime credentials map to principals, and how first
organization bootstrap works without a hosted enterprise IdP. This change
closes that blocker before backend code generation.

## What Changes

- Define human authentication mechanics for local development login, OIDC
  through authentik, optional SAML/Keycloak compatibility fixtures, external
  identity linking, and deprovisioning.
- Define browser sessions, API tokens if any, refresh/revocation behavior,
  tenant scoping, and session-to-principal mapping.
- Define service account, webhook source, integration installation, internal
  agent, and external executor credential issuance, proof, rotation, revocation,
  and audit linkage.
- Define deterministic external identity reconciliation across SSO and SCIM.
- Define first-organization, first-owner, first-workspace, initial policy
  bundle, and development/test bootstrap behavior.
- Preserve a future extraction path for authentication/identity as an internal
  Boundary context.
- This change is design-only and does not implement migrations, Phoenix, Ash,
  Ecto, GraphQL, JSON API, React, Boundary, Oban, identity-lab containers, or
  runtime code.

## Capabilities

### New Capabilities

- `human-authentication`: human login methods, OIDC/authentik fixture, optional
  SAML/Keycloak compatibility, and deprovisioning behavior.
- `session-and-token-model`: browser sessions, token posture, revocation,
  tenant scoping, audit events, and principal mapping.
- `service-account-and-agent-credentials`: service account, webhook,
  integration, internal agent, and external executor credential mechanics.
- `external-identity-reconciliation`: SSO/SCIM/provider identity linking,
  conflict handling, account linking, and lifecycle reconciliation.
- `bootstrap-and-local-identity-lab`: first-org/first-admin bootstrap and local
  identity-lab fixtures.

### Modified Capabilities

- None. No durable specs have been archived yet; this change adds active
  design deltas and cross-links only.

## Impact

- Affects OpenSpec planning and future authentication/identity implementation
  only.
- Depends on `design-identity-and-authorization-schema` for durable principal,
  external identity link, policy fact, and credential metadata records.
- Updates governance and code-organization artifacts to clarify ownership
  handoffs.
- Creates no application code or runtime dependencies.
