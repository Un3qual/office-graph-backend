## Why

Normal Office Graph product and API requests still bootstrap a fully authorized
local owner instead of authenticating a human. The product needs the first
fail-closed Authentik OIDC boundary, durable external identity reconciliation,
and cookie-referenced sessions before broader enterprise identity or governance
work can safely build on it.

## What Changes

- Add Authentik-compatible OIDC authorization-code login using state, nonce,
  PKCE, provider discovery, and validated ID-token/userinfo claims.
- Add provider-neutral external identity links with deterministic verified-email
  account linking, durable review state, and disabled-user handling.
- Extend durable sessions with authentication method, external identity link,
  issue/expiry, source, and trace metadata; store only the opaque session ID in
  the browser cookie.
- Add current principal, external-link, expiry, and revocation checks when
  loading every human session.
- Add local and provider logout plus bounded authentication lifecycle evidence.
- **BREAKING** Remove automatic local-owner bootstrap from normal product,
  GraphQL, and JSON API request paths; tests and development bootstrap through
  explicit helpers instead.
- Defer SCIM, SAML, IdP group mapping, governance-admin recovery UI, workspace
  switching, and non-human token issuance.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `human-authentication`: make Authentik OIDC login concrete, require
  state/nonce/PKCE validation, and define fail-closed verified-identifier
  linking without external claims becoming capabilities.
- `external-identity-reconciliation`: persist provider-tenant-subject links,
  deterministic review states, and disabled lifecycle enforcement.
- `session-and-token-model`: define opaque cookie references, human session
  metadata, replacement, expiry/revocation validation, logout, and
  authentication lifecycle evidence.
- `bootstrap-and-local-identity-lab`: retain explicit idempotent bootstrap while
  forbidding request-time owner creation and making Authentik configuration
  opt-in.

## Impact

- Adds Identity/Authentication Ash resources and Postgres migrations.
- Adds an OpenID Certified OIDC client dependency and an adapter boundary.
- Adds Phoenix authentication routes, controller, and session-loading plugs.
- Changes test connection setup from implicit request bootstrap to explicit
  durable session fixtures.
- Changes unauthenticated product pages to redirect to login and leaves API
  requests without an actor rather than inventing one.
