## Context

Office Graph already persists principals, role assignments, and session rows,
and authorization re-reads current policy facts. Phoenix nevertheless assigns a
local owner to normal GraphQL and JSON requests by invoking the bootstrap
helper, while product pages have no human authentication boundary.

The canonical specs require Authentik as the local OIDC fixture, provider-neutral
external identity reconciliation, thin sessions, disabled-user enforcement,
and authentication lifecycle evidence. The project also fixes OpenSpec as the
workflow source of truth, requires the Nix toolchain, and forbids external
claims from becoming capabilities.

## Goals / Non-Goals

**Goals:**

- Deliver Authentik-compatible OIDC authorization-code login with state, nonce,
  and PKCE.
- Reconcile validated OIDC identities to durable internal principals through
  explicit policy.
- Issue expiry-bearing human sessions and store only their opaque IDs in signed
  browser cookies.
- Revalidate session, principal, external-link, and authorization facts on
  requests.
- Revoke sessions on logout and preserve bounded lifecycle evidence.
- Remove automatic owner bootstrap from every normal request path.

**Non-Goals:**

- SAML, SCIM, group mapping, governance-admin recovery UI, workspace switching,
  refresh-token persistence, or non-human token issuance.
- JIT role/capability grants from provider claims.
- A compatibility fallback to the insecure request-time bootstrap behavior.

## Decisions

### Use `oidcc` behind a narrow adapter

The production OIDC adapter uses `oidcc` 3.7 for discovery, JWK refresh,
authorization URL construction, token exchange, nonce/ID-token validation,
userinfo, and optional RP-initiated logout. `oidcc` is OpenID Certified and
supports the pinned OTP version.

The application does not implement JWT or OIDC protocol validation itself.
Phoenix and domain tests use a deterministic adapter so they do not require a
live provider.

The provider-configuration worker starts only when a complete runtime
configuration is present. Partial or absent configuration fails closed.

### Separate authentication orchestration from Identity and Authorization

`OfficeGraph.Authentication` coordinates the OIDC adapter, Identity
reconciliation/session APIs, and Authorization scope resolution. This avoids an
Identity-to-Authorization dependency cycle and keeps Phoenix entrypoints thin.

Identity owns external identity links, authentication events, and durable
session lifecycle. Authorization owns the query that resolves current
workspace-scoped role assignments into an eligible login scope.

### Link only to an eligible existing human principal

The first account-linking policy is explicitly named
`verified_email_existing_principal`. It is opt-in and intended for the
controlled Authentik/local-bootstrap handoff.

For a first subject, the policy links only a provider-verified normalized email
that resolves to exactly one active human principal and has no incompatible
external link. Unknown or conflicting subjects receive a durable
`review_required` link with a bounded reason. Repeat logins return the same
blocked result.

An exact active provider-tenant-subject link remains authoritative even if its
display email later changes, subject to conflict checks. Disabled links or
principals fail closed. No OIDC group, role, or custom claim creates product
authority.

### Resolve scope from internal role assignments

After principal reconciliation, Authorization returns the principal's distinct
workspace-scoped role-assignment contexts. One scope is selected
automatically. Multiple scopes require a configured preferred
organization/workspace pair; zero scopes or a mismatched preference fail
closed.

Provider tenant and claims never select Office Graph scope. A user-facing
workspace selector is deferred.

### Make the durable session the browser authority

Human sessions use purpose `human_web` and record authentication method,
external identity link, issue/expiry, source surface, and trace identifier.
Login revokes the existing active session for the same principal and scope
before creating its replacement.

The signed, HTTP-only, SameSite=Lax cookie stores only the session UUID and is
secure in production. It contains no capabilities, provider claims, tokens, or
serialized actor.

The session loader reconstructs `SessionContext` from the database and rejects
wrong-purpose, revoked, expired, inactive-principal, inactive-link, or
scope-mismatched sessions. Authorization continues to evaluate current
role/capability facts.

### Keep explicit bootstrap but remove request bootstrap

`Foundation.bootstrap_local_owner/1` remains the controlled, idempotent
first-owner/fixture API. No plug, router, controller, resolver, or
`RequestSession` path invokes it automatically.

Tests explicitly bootstrap a fixture in `ConnCase` and place its durable session
ID into the test connection. Tests that exercise unauthenticated behavior opt
out or clear that session.

### Record bounded authentication events

Identity stores immutable events for login success, login rejection, logout,
and policy-relevant invalid-session outcomes. Events contain only identifiers,
auth method, scope, source, trace, result, and bounded reason codes. They never
store authorization codes, provider tokens, cookie values, or raw claims.

Local logout is authoritative: revocation and cookie clearing succeed even
when provider logout is unavailable.

## Risks / Trade-offs

- [Verified-email linking can attach the wrong account if provider policy is
  weak] → Require an explicit linking-policy configuration, provider-verified
  email, active human principal, and conflict-free durable link set.
- [Multi-workspace users cannot log in without a selector] → Support an
  explicit preferred scope now and fail closed otherwise; add interactive
  switching in a later batch.
- [Provider outage blocks fresh login] → Existing unexpired sessions continue
  to validate locally; fresh login fails closed with a bounded error.
- [Signed cookie contents are readable] → Store only the opaque session UUID;
  no provider token, claim, or capability enters the cookie.
- [Existing tests depend on implicit bootstrap] → Replace it centrally with an
  explicit `ConnCase` session fixture and retain opt-out coverage for
  unauthenticated requests.
- [Durable review states have no UI in this batch] → Keep them deterministic
  and queryable; do not silently recover or link until the governance-admin
  batch.

## Migration Plan

1. Add `oidcc`, provider runtime configuration, and an optional supervised
   provider worker.
2. Add external identity link and authentication event tables/resources.
3. Extend the sessions table/resource with nullable metadata so existing local
   fixture sessions remain valid.
4. Add reconciliation, login-scope resolution, human-session lifecycle, and
   authentication orchestration behind public boundaries.
5. Add Phoenix login/callback/logout routes and replace the local owner plug
   with durable session loading.
6. Convert request tests to explicit session fixtures and add fail-closed OIDC,
   reconciliation, session, and logout coverage.
7. Verify strict OpenSpec, migrations, focused tests, dependency audit, and the
   full repository gate before archiving the change.

Rollback before release removes the new routes/resources/migration and restores
the previous code, but it must not restore automatic owner bootstrap in any
deployed environment. Provider tokens are never persisted, so rollback has no
token-secret migration.

## Open Questions

None for this batch. SCIM reconciliation, governance-admin recovery,
multi-workspace selection, and group mapping remain explicit follow-on work.
