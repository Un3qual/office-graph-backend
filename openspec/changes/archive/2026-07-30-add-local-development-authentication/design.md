## Context

The three current product routes require an Office Graph-owned durable human
session. Generic `/auth/login` starts an Authentik-compatible OIDC flow, while
WorkOS login starts from a configured enterprise connection. Both flows
eventually reconcile an external identity and issue the same Office Graph
session.

That separation is correct for deployed authentication, but it makes ordinary
local UI work depend on separately operated identity infrastructure. The
repository seeds an owner and demo workflow records, but it does not provide a
browser authentication path for those records. A missing OIDC configuration
therefore redirects every protected page to a bare 503 response.

The accepted enterprise decision remains WorkOS standalone SSO and Directory
Sync without AuthKit. Office Graph continues to own principals, sessions,
authorization, and lifecycle. Authentik remains useful for deliberate generic
OIDC integration testing, but neither hosted WorkOS nor a local Authentik
server should be required for routine product development.

## Goals / Non-Goals

**Goals:**

- Let a developer reach protected local product routes in a few clicks and
  select among deterministic owner, workspace-administrator, member, and
  deprovisioned fixtures.
- Exercise the same durable session issuance, per-request identity validation,
  scope resolution, and authorization policies used by external login.
- Make switching identities explicit and revoke the current durable session
  before returning to the chooser.
- Make the local provider unavailable unless the application is built for
  development, explicitly enabled, and reached over a loopback request.
- Keep fixture creation explicit, idempotent, and owned by Ash-backed setup
  actions rather than browser requests.
- Preserve Authentik and WorkOS as independent integration paths.

**Non-Goals:**

- Add a production password, magic-link, AuthKit, or local-owner fallback
  authentication mechanism.
- Simulate WorkOS, OIDC, SAML, Directory Sync, or deprovisioning transport in
  the local chooser.
- Let the browser select arbitrary principals, emails, scopes, role keys, or
  capabilities.
- Automatically create, reactivate, or grant authority to a fixture during a
  login request.
- Define the complete production role catalog or replace focused provider
  contract tests.

## Decisions

### 1. Treat local development sign-in as a third provider with narrower trust

The authentication boundary will recognize three distinct paths:

- Authentik-compatible generic OIDC for deliberate OIDC testing and
  non-WorkOS deployments;
- WorkOS standalone SSO for an organization-selected enterprise connection;
- an explicit local-development provider for pre-seeded fixtures.

The local provider is not an OIDC fallback. When enabled, `/auth/login` renders
a provider/fixture chooser instead of automatically issuing a session. If
generic OIDC is also configured, the page offers a separate Authentik action
that starts the existing nonce, PKCE, and callback flow. WorkOS remains
connection-selected through its existing route.

Alternative considered: use WorkOS or Authentik for every development login.
Rejected because provider setup and network availability make ordinary
frontend and workflow testing slower without improving the behavior under
test.

Alternative considered: restore automatic local-owner bootstrap in the
request pipeline. Rejected because it hides authorization mistakes, grants
authority as a side effect of an unauthenticated request, and violates the
accepted fail-closed boundary.

### 2. Enforce layered development-only availability

The local provider will require all of the following:

- a development build with the existing `dev_routes` compile-time gate;
- an explicit `LOCAL_DEV_AUTH_ENABLED=true` runtime setting accepted only in
  the development environment;
- a loopback peer address;
- the normal signed browser session and a CSRF-protected POST for fixture
  selection or identity switching.

Production builds will not register the local fixture-selection or switch
routes, and `/auth/login` will never render the fixture chooser in production.
Disabling the runtime setting makes the chooser unavailable rather than
falling through to a seeded identity. The existing development endpoint stays
bound to loopback by default.

Alternative considered: enable the provider automatically whenever
`MIX_ENV=dev`. Rejected because an explicit setting makes the trust decision
visible and protects developers who intentionally expose a development server.

### 3. Resolve only fixed server-owned fixture keys

`mix demo.seed` will reconcile a typed, centralized fixture manifest containing
stable selector keys and expected identity facts. The browser may submit only
one of those keys. It never submits or chooses a principal ID, email,
organization, workspace, role, capability set, or lifecycle state.

The initial chooser contains:

- `owner`: the existing active local owner with the existing owner role;
- `workspace_admin`: an active workspace administrator with current
  workspace-operational capabilities but no organization-level enterprise
  identity or installation administration;
- `member`: an active member with product reads plus bounded ordinary
  participation, without apply, execution, evidence acceptance, waiver, or
  administration capabilities;
- `deprovisioned_member`: a retained member fixture whose identity basis is
  disabled and whose attempted sign-in is expected to fail.

Fixture roles and capability sets live in one setup-owned catalog and use
ordinary `Role`, `RoleCapability`, and `RoleAssignment` records. They are
development fixtures, not an implicit declaration that these are the final
production default-role policies.

Each eligible fixture has a stable `local_development` external identity link
in the seeded local tenant. The authentication boundary resolves the submitted
key to that expected link and scope, then the existing session-issuance action
locks and revalidates the exact principal and link before writing. Missing,
drifted, ambiguous, inactive, or wrong-scope facts fail closed.

Alternative considered: query principals by a browser-supplied email or UUID.
Rejected because it turns a convenience route into an unrestricted
impersonation endpoint and makes fixture drift invisible.

### 4. Issue and validate ordinary Office Graph human sessions

Successful local selection calls the existing Identity and Authorization
boundaries rather than creating a special actor or cookie. The session:

- has purpose `human_web`;
- records authentication method `local_development`;
- references the selected active external identity link;
- records the exact organization and workspace;
- uses the existing expiry, opaque-cookie, replacement, evidence, and
  revocation behavior.

Every GraphQL, JSON API, and product-page request continues to load that session
through `SessionAuthenticationPlug`, revalidate the principal, link, scope, and
current authority, and set the Ash actor. No capability list from the chooser
or browser is trusted.

The fixture lookup may identify the intended records, but session issuance
must re-lock and revalidate them inside the owning Ash action. No
`Repo.transaction`, direct Ecto persistence, or repository-authored raw SQL is
introduced.

### 5. Switch identities by logging out before choosing again

The development UI exposes a switch action that first invokes the existing
durable logout/revocation path. Only after revocation succeeds does it clear the
cookie and redirect to `/auth/login` with the safe current return target. The
developer then selects the next fixture and receives a new session.

The switch is intentionally two phases rather than an in-place principal
mutation. If revocation storage is unavailable, the current cookie remains and
the response reports an unavailable state. If later selection fails, the
developer remains logged out instead of retaining an undisclosed prior
identity.

The switch entry point may be a standard sign-out/switch control shared by the
product shell, but production rendering must never expose fixture identities
or the development provider.

### 6. Keep the pre-authentication UI server-rendered and bounded

The chooser is a small Phoenix-rendered browser page because it exists before
the React application can make authenticated GraphQL requests. It preserves
only a validated root-relative `return_to`, labels the current development
trust mode clearly, and posts a stable fixture key with CSRF protection.

Eligible selection redirects to the original product page. A disabled fixture
shows an expected rejection without issuing a cookie. Missing fixtures show an
actionable local message to run `mix demo.seed`; the request never runs the
seed itself.

All browser authentication failures set an explicit HTML or plain-text content
type. Development responses may name the missing local setup command but must
not expose configuration values, provider payloads, tokens, database errors, or
stack traces. Production responses remain bounded.

### 7. Verify provider isolation and real authorization behavior

Focused tests will prove:

- the chooser and POST routes are unavailable outside the layered development
  gates and for non-loopback requests;
- the chooser accepts only fixed keys and safe local return targets;
- seed replay creates no duplicate principals, links, roles, assignments, or
  sessions and does not reactivate the deprovisioned fixture;
- owner, administrator, and member sessions produce different real
  authorization outcomes;
- disabled and drifted identities cannot receive a session;
- switching revokes the old session before another selection;
- Authentik OIDC still performs nonce/PKCE/callback validation;
- WorkOS login and Directory Sync behavior remain unchanged;
- authentication error responses have a browser-safe content type and do not
  download as opaque files.

## Risks / Trade-offs

- [A developer exposes the local server beyond loopback] → Require a
  development build, explicit enablement, loopback peer, signed session, and
  CSRF-protected POST; document that rebinding the server does not make local
  sign-in suitable for shared environments.
- [Fixture capability profiles are mistaken for final product policy] → Keep
  them in a clearly named development fixture catalog and state that production
  role governance remains independently specified.
- [Seeded identity facts drift or are manually edited] → Resolve exact expected
  facts and revalidate under lock during session issuance; fail with an
  actionable reseed message instead of repairing data during login.
- [Switching logs the developer out before the next selection succeeds] → Make
  the two-phase behavior explicit; this is safer than retaining two active
  identities or silently restoring the prior session.
- [Local convenience hides provider integration defects] → Keep focused OIDC
  and WorkOS adapter tests and make Authentik/WorkOS smoke paths independently
  runnable.

## Migration Plan

1. Add failing route, gate, selector, lifecycle, authorization, switching,
   content-type, and seed-replay tests.
2. Add the typed development fixture manifest and idempotent Ash-backed setup
   actions, then extend `mix demo.seed`.
3. Add the gated authentication boundary functions and Phoenix chooser/switch
   routes.
4. Add the product-shell sign-out/switch affordance without exposing
   development fixtures in production.
5. Update local setup documentation and run focused auth/frontend tests,
   strict OpenSpec validation, and the canonical verification gate.

Rollback disables `LOCAL_DEV_AUTH_ENABLED`, removes the development routes and
fixture additions, and leaves Authentik, WorkOS, production sessions, and
existing seeded product data unchanged. No schema rollback is required.

## Open Questions

None. The provider responsibilities, fixture set, trust gates, ordinary session
contract, switch behavior, and explicit seeding boundary are accepted.
