# Human Session Foundation Design

## Status

Approved in conversation on 2026-07-25 as option 1 of the next independently
shippable Office Graph batches.

## Problem

Office Graph has durable principals, role assignments, sessions, and
authorization checks, but normal web and API requests still obtain an owner by
calling the local bootstrap path. There is no human login/logout flow, no
provider-neutral external identity link, no expiry-bearing browser session, and
no fail-closed handling for disabled external users.

That makes the current product surface a development shortcut rather than an
authentication boundary. It also prevents Authentik from serving as the local
enterprise identity fixture defined by the canonical OpenSpec requirements.

## Fixed Scope

This batch delivers:

- Authentik-compatible OIDC authorization-code login with state, nonce, and
  PKCE validation;
- provider-neutral external identity reconciliation;
- durable, expiry-bearing human browser sessions referenced by an opaque
  cookie value;
- current-principal and current-external-link lifecycle checks on every
  authenticated request;
- local and provider logout behavior;
- authentication lifecycle evidence for successful, failed, and revoked
  sessions;
- explicit test/bootstrap helpers that replace request-time owner creation.

This batch explicitly defers:

- SAML;
- SCIM provisioning and group synchronization;
- governance-admin identity linking and conflict-resolution UI;
- workspace switching and a workspace picker;
- IdP group-to-role mapping;
- service-account or agent token issuance;
- refresh-token storage or long-lived provider-token storage.

## Considered Approaches

### 1. Keep the request-time local owner and add OIDC beside it

This minimizes test changes, but unauthenticated requests would still become a
fully authorized owner whenever local bootstrap is enabled. OIDC would be
optional decoration rather than the authentication boundary.

Rejected.

### 2. Implement OIDC protocol and JWT validation directly

Office Graph could perform discovery, JWK refresh, authorization URL
construction, token exchange, and ID-token verification with generic HTTP and
JOSE primitives. That would make security-sensitive protocol behavior
application-owned and create a large bespoke conformance burden.

Rejected.

### 3. Use an OIDC-certified protocol client behind an Office Graph adapter

Use `oidcc` for discovery, JWK refresh, PKCE-capable authorization, token
exchange, nonce and ID-token validation, userinfo, and RP-initiated logout.
Keep a narrow Office Graph adapter around it so controller and reconciliation
tests are deterministic and never require a live IdP.

Selected. `oidcc` 3.7 is current, supports OTP 29, is OpenID Certified, and
provides the protocol checks this boundary should not reimplement.

## Architecture

### Authentication Orchestration

Add `OfficeGraph.Authentication` as the public orchestration boundary between
Phoenix, the OIDC client, Identity, and Authorization.

It owns three workflows:

1. `begin_login/1` creates cryptographically random state, nonce, and PKCE
   verifier values and returns the provider authorization URI plus the
   short-lived transaction values that Phoenix stores in the signed cookie
   session.
2. `complete_login/2` exchanges the authorization code, accepts only validated
   OIDC claims, reconciles the external identity, resolves one authorized
   internal scope, replaces the active human session, and records the result.
3. `logout/2` revokes the durable session, records the event, and returns an
   optional provider logout URI.

The Phoenix controller translates request and cookie values only. It does not
query Identity tables, interpret claims, select permissions, or issue durable
sessions directly.

### OIDC Client Boundary

`OfficeGraph.Authentication.OidcClient` defines a narrow adapter contract:

- build an authorization URI from state, nonce, PKCE verifier, and redirect
  URI;
- exchange a code using the same nonce, verifier, and redirect URI and return
  validated claims;
- optionally build an RP-initiated logout URI.

The production adapter wraps `oidcc`. Its provider-configuration worker starts
only when a complete OIDC configuration is present. Missing or partial
configuration fails closed and does not fall back to a local owner.

Tests use a deterministic adapter that returns validated claim fixtures and
records calls.

### External Identity Links

Add `external_identity_links` under `OfficeGraph.Identity` with:

- provider and provider tenant/issuer;
- provider subject;
- optional internal principal;
- normalized verified email;
- lifecycle status;
- account-linking state and review reason;
- first-linked, last-authenticated, disabled, and update timestamps.

The stable lookup key is provider, provider tenant, and provider subject.
OIDC display names, groups, roles, departments, and similar claims are not
stored as capabilities and never grant Office Graph authority.

Reconciliation follows this order:

1. Reject missing subject, missing email, or an email that the provider did not
   verify.
2. Resolve an existing exact provider-tenant-subject link.
3. Fail closed if that link or its principal is inactive.
4. For a first login, apply the configured account-linking policy. The only
   policy in this batch is an explicit
   `verified_email_existing_principal` policy, intended for the local
   Authentik lab and controlled bootstrap handoff.
5. Link only when the verified normalized email names exactly one eligible
   active human principal and no incompatible external link already claims the
   identifier.
6. Persist a `review_required` link for unknown or conflicting identities so
   repeat attempts return the same deterministic outcome.

The system does not create roles from OIDC claims and does not silently create
an authorized principal. Governance-admin recovery is deferred, so a
`review_required` link remains blocked until a future explicit recovery path
changes it.

### Scope Selection

An authenticated identity still needs an internal organization and workspace
context. Authorization resolves current workspace-scoped role assignments for
the principal:

- one distinct scope is selected;
- multiple scopes require a configured preferred organization/workspace pair;
- zero scopes fail closed;
- an invalid preferred scope fails closed.

This avoids treating OIDC tenant, group, or role claims as Office Graph scope
authority. Interactive workspace selection is deferred.

### Durable Human Sessions

Extend `sessions` with:

- authentication method;
- external identity link;
- issued and expiry timestamps;
- source surface;
- trace/request identifier.

Human login uses purpose `human_web`. Within one transaction it revokes any
active `human_web` session for the same principal and selected scope, then
creates the replacement. The existing partial unique index continues to
enforce one active session per principal, scope, and purpose.

The browser cookie contains only the opaque session UUID. It does not contain
capabilities, external claims, provider tokens, or a serialized actor. The
cookie is signed, HTTP-only, SameSite=Lax, and secure in production.

Every request reconstructs `SessionContext` from the durable session and
re-checks:

- the session is the expected human purpose;
- it is not revoked or expired;
- the principal is active;
- the external identity link is active and still belongs to the principal;
- the organization/workspace relationship is valid.

Authorization then continues to query current role/capability facts. Session
claims never become durable authorization.

### Web And API Boundary

Replace `LocalApiOwnerPlug` with a session loader that only sets an Ash actor
when a valid human session UUID is present.

- `/auth/login`, `/auth/callback`, and `/auth/logout` own the browser flow.
- `/operator`, `/packets`, and `/runs` require a valid human session and
  redirect unauthenticated browsers to login.
- GraphQL and JSON API pipelines load a valid session when present but never
  bootstrap one. Existing transport-specific forbidden responses remain in
  charge when the actor is absent.
- static operator assets remain public so the authenticated shell can load.
- webhook authentication remains independent of the human session pipeline.

`RequestSession.resolve(nil)` returns forbidden. It never calls bootstrap.

### Bootstrap And Tests

`Foundation.bootstrap_local_owner/1` remains the explicit, idempotent first-org
bootstrap and fixture API. `ApiSupport.bootstrap_local_api_owner/0` may remain
as a development/test helper during this batch, but no router, plug,
controller, resolver, or request-session path calls it automatically.

`ConnCase` explicitly provisions a local owner fixture and places its durable
session ID into the test connection unless a test opts out. This preserves
focused transport tests without preserving the insecure production behavior.

Development no longer enables automatic owner bootstrap for requests.
Authentik configuration is opt-in through environment-backed runtime config.

### Authentication Evidence

Add immutable authentication-event rows for:

- successful login;
- rejected login;
- logout/revocation;
- invalid, expired, revoked, or disabled session use when request policy
  requires recording.

Each row preserves the available principal, external link, session,
organization/workspace, auth method, source surface, trace/request ID, result,
and a bounded reason code. Raw authorization codes, provider tokens, cookie
values, and unfiltered claims are never persisted.

## Failure Behavior

- Missing OIDC configuration: login returns service unavailable; product and
  API requests remain unauthenticated.
- State mismatch or missing login transaction: callback fails before token
  exchange.
- Provider exchange, discovery, or validation failure: callback fails closed
  with a bounded authentication error.
- Unverified email: no principal link and no session.
- Unknown or conflicting identity: durable `review_required` link and no
  session.
- Disabled link or principal: no new session; existing human sessions fail on
  their next validation.
- Missing or ambiguous internal scope: no session.
- Expired or revoked durable session: cookie is cleared and the request remains
  unauthenticated.
- Logout is locally authoritative: the durable session is revoked and the
  cookie is cleared even if the provider has no logout endpoint or provider
  logout URL generation fails.
- Storage failure: no partial link/session success is reported.

## Testing

Use behavior tests at the public boundaries:

1. Reconciliation tests prove exact subject reuse, explicit verified-email
   linking, durable review state, conflict handling, and disabled-user
   rejection.
2. Session tests prove metadata, replacement revocation, expiry, logout, and
   principal/link lifecycle revalidation.
3. Authentication tests prove one-scope selection, preferred-scope
   disambiguation, claim non-authority, and bounded adapter/storage failures.
4. Controller/plug tests prove state and PKCE transaction handling, successful
   cookie-backed login, mismatch rejection, logout, unauthenticated product
   redirect, and absent API actor behavior.
5. Existing web tests use explicit session fixtures and prove no request path
   invokes local-owner bootstrap.
6. Migration, Ash-resource, Boundary, dependency-audit, and strict OpenSpec
   checks cover the new persistence and dependency surface.
7. Focused tests pass before the complete Nix-backed `./bin/verify` gate.

## Completion Criteria

- Authentik-compatible OIDC login and logout work through the adapter boundary.
- External identities reconcile to durable principals only under explicit,
  deterministic policy.
- Disabled principals or external links cannot log in or reuse a session.
- Browser cookies contain only an opaque durable session identifier.
- Current authorization facts are re-evaluated after authentication.
- No normal product or API request can bootstrap a local owner.
- SCIM, governance-admin UI, group mapping, and workspace switching remain
  explicitly deferred.
- OpenSpec strict validation, focused tests, the complete repository gate, and
  `git diff --check` pass.
