## Why

Routine local UI development currently requires a separately configured
Authentik server before a developer can open `/operator`, `/packets`, or
`/runs`. Office Graph needs an explicit development-only sign-in path that is
fast enough for everyday role testing without weakening production
authentication or bypassing the real session and authorization boundaries.

## What Changes

- Add an opt-in development-only sign-in page with a small fixed chooser for
  seeded owner, administrator, member, and disabled-user fixtures.
- Make protected local product routes preserve their return target through the
  chooser, and add a development-only identity-switch action that revokes the
  current session before another identity is selected.
- Issue ordinary durable Office Graph human sessions for eligible development
  fixtures and evaluate every request through the existing principal,
  workspace, lifecycle, and authorization checks.
- Keep fixture creation explicit through `mix demo.seed`; browser requests never
  bootstrap or grant an identity automatically.
- Require both the development environment and explicit local-auth
  configuration, bind the development server to loopback, reject arbitrary
  principal identifiers, and exclude the local provider from production.
- Keep Authentik available for deliberate OIDC integration testing and keep
  WorkOS as the enterprise SSO and Directory Sync integration without adopting
  AuthKit.
- Replace bare authentication failure downloads with correctly typed,
  actionable browser responses.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `human-authentication`: Add an explicit development-only provider selection
  and sign-in path while keeping missing production provider configuration
  fail-closed.
- `bootstrap-and-local-identity-lab`: Add deterministic seeded development
  identities and a browser chooser without turning bootstrap into request
  authentication.
- `session-and-token-model`: Allow an eligible seeded development identity to
  receive the same durable, auditable, authorization-revalidated human session
  as an externally authenticated identity.

## Impact

- Affects local runtime configuration, development routes, authentication
  controller behavior, local fixture seeding, session issuance provenance, and
  focused Phoenix/browser tests.
- Adds no external dependency, production authentication route, provider
  secret, raw SQL, direct Ecto persistence, or alternative authorization
  mechanism.
- Authentik OIDC and WorkOS SSO/Directory Sync remain independently testable
  through their existing adapters and contracts.
