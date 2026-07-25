# Human Session Foundation Implementation Plan

Status: active.

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace request-time local-owner bootstrap with Authentik-compatible
OIDC login/logout, provider-neutral external identity reconciliation, and
expiry-bearing cookie-referenced human sessions that fail closed when identity
state changes.

**Architecture:** Add a focused `OfficeGraph.Authentication` orchestration
boundary over an `oidcc` adapter, Identity-owned external links/events/sessions,
and Authorization-owned login-scope resolution. Phoenix stores only the
durable session UUID in its signed cookie and reconstructs an actor on each
request; bootstrap remains an explicit fixture/first-owner action only.

**Tech Stack:** Elixir 1.20, Erlang/OTP 29, Phoenix 1.8, Ash 3,
AshPostgres/Ecto/PostgreSQL, `oidcc` 3.7, ExUnit, OpenSpec 1.4.1, Nix.

## Global Constraints

- Use
  `openspec/changes/add-human-session-foundation/{proposal,design,specs,tasks}`
  as the implementation source of truth.
- Use the project Nix flake for every Mix, OpenSpec, migration, format, and
  verification command.
- Use strict red-green-refactor cycles: add behavior tests, run them and observe
  the expected failure, then add only enough production code to pass.
- OIDC claims never become capabilities, grants, role assignments, or tenant
  scope.
- The only first-login policy in this batch is explicitly configured
  `verified_email_existing_principal`.
- Unknown, conflicting, disabled, ambiguous-scope, expired, revoked, or
  storage-failed authentication attempts fail closed.
- Cookies contain only the opaque durable session UUID; never store provider
  tokens, raw claims, or capability lists in the cookie or authentication
  events.
- Local logout remains authoritative when provider logout is unavailable.
- No plug, controller, resolver, API handler, or request-session helper may
  invoke local-owner bootstrap.
- Keep SCIM, SAML, IdP group mapping, admin recovery UI, workspace switching,
  refresh-token storage, and non-human token issuance out of scope.
- Preserve existing explicit `Foundation.bootstrap_local_owner/1` semantics.
- Update the Ash ownership inventory and its count for every new table.
- Prefer behavior tests over source-string assertions; use structural checks
  only where the architecture gate already requires an inventory.
- Commit each independently coherent green phase.

---

### Task 1: Commit The Strict OpenSpec Contract And Plan

**Files:**
- Create:
  `openspec/changes/add-human-session-foundation/.openspec.yaml`
- Create:
  `openspec/changes/add-human-session-foundation/proposal.md`
- Create:
  `openspec/changes/add-human-session-foundation/design.md`
- Create:
  `openspec/changes/add-human-session-foundation/tasks.md`
- Create delta specs under:
  `openspec/changes/add-human-session-foundation/specs/`
- Create:
  `docs/superpowers/plans/2026-07-25-human-session-foundation.md`

**Interfaces:**
- Consumes:
  `docs/superpowers/specs/2026-07-25-human-session-foundation-design.md`.
- Produces the complete active change contract for Tasks 2-6.

- [x] **Step 1: Create proposal, design, delta specs, and task artifacts**

Cover `human-authentication`, `external-identity-reconciliation`,
`session-and-token-model`, and `bootstrap-and-local-identity-lab`. Keep every
deferred identity/governance feature explicit.

- [x] **Step 2: Strict-validate the active change**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command \
  openspec validate add-human-session-foundation --strict
nix --extra-experimental-features 'nix-command flakes' develop --command \
  openspec validate --changes --strict
```

Expected: the change and all active changes are valid.

- [x] **Step 3: Check and commit the contract**

Run `git diff --check`, inspect the artifact diff, and commit with:

```bash
git add \
  docs/superpowers/plans/2026-07-25-human-session-foundation.md \
  openspec/changes/add-human-session-foundation
git commit -m "docs: specify human session foundation"
```

---

### Task 2: Add Identity Persistence And Reconciliation

**Files:**
- Create:
  `priv/repo/migrations/20260725120000_add_human_session_foundation.exs`
- Create:
  `lib/office_graph/identity/external_identity_link.ex`
- Create:
  `lib/office_graph/identity/authentication_event.ex`
- Modify:
  `lib/office_graph/identity/session.ex`
- Modify:
  `lib/office_graph/identity/session_context.ex`
- Modify:
  `lib/office_graph/identity/domain.ex`
- Modify:
  `lib/office_graph/identity.ex`
- Create:
  `test/office_graph/identity/human_authentication_test.exs`
- Modify:
  `test/support/office_graph/ash_conformance_support.ex`
- Modify:
  `test/office_graph/architecture/ash_resource_conformance_test.exs`
- Modify:
  `openspec/specs/backend-model-ownership/model-inventory.md`

**Interfaces:**
- Produces:
  `Identity.reconcile_oidc_identity(claims, opts)`.
- `opts` requires `:provider`, `:provider_tenant`, and
  `:account_linking_policy`.
- Success returns an active `ExternalIdentityLink` and its active human
  principal.
- Deterministic blocked results use bounded atoms such as
  `:unverified_identifier`, `:identity_review_required`,
  `:identity_disabled`, and `:principal_disabled`.
- Produces:
  `Identity.issue_human_session(principal, link, scope, attrs)`.
- Produces:
  `Identity.resolve_human_session(session_id)`.
- Produces:
  `Identity.revoke_human_session(session_id, attrs)`.
- Produces bounded authentication-event recording owned by Identity.

- [x] **Step 1: Write failing persistence/reconciliation tests**

Cover:

- migration columns, foreign keys, check constraints, and indexes;
- exact provider-tenant-subject reuse;
- normalized, provider-verified email linking to one active human principal;
- refusal of missing/unverified identifiers;
- unknown identifier persisted as `review_required`;
- incompatible verified-identifier conflict;
- repeat review outcome stability;
- disabled link and disabled principal rejection;
- absence of role, grant, or capability writes from group/role claim fixtures.

- [x] **Step 2: Run the new tests and confirm RED**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command \
  mix test test/office_graph/identity/human_authentication_test.exs
```

Expected: compile/test failures because the migration, resources, and public
Identity APIs do not exist.

- [x] **Step 3: Add the migration and canonical Ash resources**

Create:

- `external_identity_links` with unique
  `(provider, provider_tenant, subject)`, optional principal for review state,
  normalized verified email, lifecycle/linking state, review reason, and
  timestamps;
- `authentication_events` with nullable principal/link/session identifiers,
  organization/workspace, auth method, source, trace, result, and reason;
- session columns for authentication method, external link, issued/expiry,
  source, and trace.

Add database checks that active links have principals and that human sessions
have the required metadata. Keep new session columns nullable for pre-existing
explicit local fixture sessions.

Register resources in `Identity.Domain`, the test ownership map, identity map,
durable OpenSpec model inventory, and the implemented table count.

- [x] **Step 4: Implement reconciliation and human session lifecycle**

Keep reconciliation and session writes inside Identity transactions. Normalize
email with trim/downcase, reserve review subjects durably, verify link/principal
lifecycle, and never persist raw claims.

Issue `human_web` sessions with a configurable eight-hour default. Revoke the
existing active same-context session before replacement. Resolve sessions only
when purpose, expiry, revocation, principal, link, and scope all validate.

- [x] **Step 5: Run focused Identity and architecture tests**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command \
  mix test \
  test/office_graph/identity/human_authentication_test.exs \
  test/office_graph/foundation/bootstrap_test.exs \
  test/office_graph/architecture/ash_resource_conformance_test.exs
```

Expected: all pass, including unchanged explicit bootstrap behavior.

- [x] **Step 6: Format, verify the diff, and commit**

Run `mix format` through Nix and `git diff --check`. Commit with:

```bash
git add \
  lib/office_graph/identity* \
  priv/repo/migrations/20260725120000_add_human_session_foundation.exs \
  test/office_graph/identity/human_authentication_test.exs \
  test/support/office_graph/ash_conformance_support.ex \
  test/office_graph/architecture/ash_resource_conformance_test.exs \
  openspec/specs/backend-model-ownership/model-inventory.md
git commit -m "feat: add external identity sessions"
```

---

### Task 3: Add OIDC And Authentication Orchestration

**Files:**
- Modify: `mix.exs`
- Modify: `mix.lock`
- Modify: `config/config.exs`
- Modify: `config/test.exs`
- Modify: `config/runtime.exs`
- Modify: `lib/office_graph/application.ex`
- Modify: `lib/office_graph.ex`
- Create: `lib/office_graph/authentication.ex`
- Create: `lib/office_graph/authentication/oidc_client.ex`
- Create: `lib/office_graph/authentication/oidc_client/oidcc.ex`
- Create:
  `test/support/office_graph/authentication/oidc_client_test_adapter.ex`
- Create: `test/office_graph/authentication_test.exs`
- Modify: `lib/office_graph/authorization.ex`

**Interfaces:**
- Produces:
  `Authentication.begin_login(redirect_uri, attrs)`.
- Returns authorization URI plus state, nonce, and PKCE verifier.
- Produces:
  `Authentication.complete_login(code, transaction, attrs)`.
- Produces:
  `Authentication.logout(session_id, attrs)`.
- Produces:
  `Authentication.oidc_children/0`.
- Produces:
  `Authorization.resolve_login_scope(principal_id, preferred_scope \\ nil)`.
- `OidcClient` adapters implement `authorization_uri/1`, `exchange/1`, and
  `logout_uri/1`.

- [ ] **Step 1: Add `oidcc` and fetch dependencies**

Add `{:oidcc, "~> 3.7"}` and run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command \
  mix deps.get
```

Inspect `mix.lock` and run `mix deps.unlock --check-unused`.

- [ ] **Step 2: Write failing orchestration and scope tests**

Cover:

- random state, nonce, and PKCE transaction creation;
- the exact redirect URI and transaction reaching the adapter;
- validated claims reaching Identity reconciliation;
- one internal role-assignment scope selected;
- multiple scopes rejected without a matching preference;
- matching preferred scope selected;
- no scope rejected;
- provider/Identity/Authorization failures normalized and recorded;
- logout revoking locally when provider logout is unsupported;
- external group/role claims creating no internal authority.

- [ ] **Step 3: Run orchestration tests and confirm RED**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command \
  mix test test/office_graph/authentication_test.exs
```

Expected: failures because the boundary, adapter, and scope resolver do not
exist.

- [ ] **Step 4: Implement config, adapter, scope resolution, and orchestration**

Runtime config is complete only with issuer, client ID, client secret, and the
explicit account-linking policy. Partial/missing config returns unavailable and
starts no provider worker.

The `oidcc` adapter requires PKCE and nonce on authorization and exchange,
returns only validated ID-token/userinfo claims, and can build logout without
persisting the ID token.

Scope resolution queries current workspace-scoped role assignments, deduplicates
organization/workspace pairs, and applies only an explicit matching preference.

- [ ] **Step 5: Run focused orchestration and dependency checks**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command \
  mix test \
  test/office_graph/authentication_test.exs \
  test/office_graph/identity/human_authentication_test.exs
nix --extra-experimental-features 'nix-command flakes' develop --command \
  mix dependency.audit
```

Expected: tests pass and no dependency advisory is reported.

- [ ] **Step 6: Format, verify the diff, and commit**

Run `mix format` through Nix and `git diff --check`. Commit with:

```bash
git add \
  mix.exs mix.lock config \
  lib/office_graph.ex \
  lib/office_graph/application.ex \
  lib/office_graph/authentication.ex \
  lib/office_graph/authentication \
  lib/office_graph/authorization.ex \
  test/office_graph/authentication_test.exs \
  test/support/office_graph/authentication
git commit -m "feat: add Authentik OIDC orchestration"
```

---

### Task 4: Replace Request Bootstrap With Cookie Sessions

**Files:**
- Create: `lib/office_graph_web/controllers/authentication_controller.ex`
- Create: `lib/office_graph_web/session_authentication_plug.ex`
- Create: `lib/office_graph_web/require_human_session_plug.ex`
- Delete: `lib/office_graph_web/local_api_owner_plug.ex`
- Modify: `lib/office_graph_web/request_session.ex`
- Modify: `lib/office_graph_web/router.ex`
- Modify: `lib/office_graph_web/endpoint.ex`
- Modify: `test/support/conn_case.ex`
- Create: `test/office_graph_web/authentication_controller_test.exs`
- Modify:
  `test/office_graph_web/generated_api_read_test.exs`
- Modify if failures identify explicit fixture assumptions:
  other `test/office_graph_web/**/*_test.exs`

**Interfaces:**
- Routes:
  `GET /auth/login`, `GET /auth/callback`, `POST /auth/logout`.
- Browser session keys are namespaced and contain the login transaction or
  `human_session_id`; the authenticated steady-state cookie contains only the
  session ID.
- `SessionAuthenticationPlug` sets the Ash actor only for a valid durable human
  session.
- `RequireHumanSessionPlug` redirects product HTML requests to `/auth/login`
  with a bounded local return path.
- GraphQL and JSON API pipelines load but do not invent an actor.

- [ ] **Step 1: Write failing controller and plug tests**

Cover:

- login redirects to the adapter URI and saves state/nonce/verifier;
- callback rejects missing/mismatched state before exchange;
- successful callback stores only `human_session_id`, clears the transaction,
  and redirects to a validated local return path;
- malicious/external return paths fall back to `/operator`;
- callback/provider failures do not create sessions;
- logout revokes, clears the cookie, and optionally redirects through provider
  logout;
- unauthenticated product routes redirect to login;
- authenticated product routes render;
- a valid cookie sets the same `SessionContext` for GraphQL and JSON;
- missing, expired, revoked, or disabled sessions set no actor and clear stale
  state;
- requests never invoke local bootstrap.

- [ ] **Step 2: Run web authentication tests and confirm RED**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command \
  mix test test/office_graph_web/authentication_controller_test.exs
```

Expected: route/module failures because the new browser boundary does not exist.

- [ ] **Step 3: Implement routes, controller, and plugs**

Keep callback state comparison constant-time, consume the transaction once, and
normalize HTTP status/error responses without leaking provider details.

Set session cookie options to signed, HTTP-only, SameSite=Lax, and production
secure. Store no actor or capabilities in the cookie.

Replace both API pipeline uses of `LocalApiOwnerPlug` with the durable loader.
Add loader-plus-require to `/operator`, `/packets`, and `/runs`; leave static
assets and webhooks on their existing independent boundaries.

- [ ] **Step 4: Make existing web tests use explicit session fixtures**

Have `ConnCase` call explicit bootstrap once per test and place the resulting
durable session ID into the test connection. Provide a helper/option to produce
an unauthenticated connection. Update the few tests that previously toggled
`allow_local_api_owner_bootstrap` to clear the explicit session instead.

Remove the request fallback from `RequestSession.resolve(nil)` and delete
`LocalApiOwnerPlug`.

- [ ] **Step 5: Run all web and focused domain tests**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command \
  mix test \
  test/office_graph_web \
  test/office_graph/authentication_test.exs \
  test/office_graph/identity/human_authentication_test.exs \
  test/office_graph/foundation/bootstrap_test.exs
```

Expected: all pass with explicit request actors and fail-closed unauthenticated
coverage.

- [ ] **Step 6: Format, verify the diff, and commit**

Run `mix format` through Nix and `git diff --check`. Commit with:

```bash
git add \
  lib/office_graph_web \
  test/support/conn_case.ex \
  test/office_graph_web
git commit -m "feat: require durable human web sessions"
```

---

### Task 5: Anti-Slop Review And Repository Verification

**Files:**
- Modify only files required by findings.
- Modify:
  `openspec/changes/add-human-session-foundation/tasks.md`
- Modify:
  `docs/superpowers/plans/2026-07-25-human-session-foundation.md`

- [ ] **Step 1: Review the aggregate diff**

Check every new module, public API, fallback, config key, and guard for a
concrete reachable responsibility. Remove duplicate adapters, compatibility
aliases, speculative claim mapping, source-string tests, and branches that
cannot be exercised.

Confirm with repository searches that:

- no normal request path calls `bootstrap_local_api_owner`;
- no cookie/session transaction contains capability or provider-token fields;
- no OIDC group/role claim reaches Authorization mutation APIs;
- no SCIM/admin/workspace-switching behavior leaked into the batch.

- [ ] **Step 2: Run focused static and migration checks**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command \
  mix ecto.migrate
nix --extra-experimental-features 'nix-command flakes' develop --command \
  mix boundary.check
nix --extra-experimental-features 'nix-command flakes' develop --command \
  mix architecture.conformance
nix --extra-experimental-features 'nix-command flakes' develop --command \
  mix spec.verify
```

Expected: migrations and every focused gate pass.

- [ ] **Step 3: Run the complete repository gate**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command \
  ./bin/verify
git diff --check
```

Expected: every backend, frontend, architecture, type, dependency, production
build, and strict OpenSpec check passes.

- [ ] **Step 4: Mark implementation tasks complete**

Only after fresh successful evidence, check every completed OpenSpec task and
set this plan status to `completed`.

- [ ] **Step 5: Commit verified implementation closeout**

Commit any verification-only corrections and completed task state with:

```bash
git add -A
git commit -m "test: verify human session foundation"
```

Do not create an empty commit if the prior coherent commit already contains all
verified changes.

---

### Task 6: Verify And Archive The OpenSpec Change

**Files:**
- Move through OpenSpec archive:
  `openspec/changes/add-human-session-foundation/`
- Modify synced durable specs:
  `openspec/specs/human-authentication/spec.md`
- Modify:
  `openspec/specs/external-identity-reconciliation/spec.md`
- Modify:
  `openspec/specs/session-and-token-model/spec.md`
- Modify:
  `openspec/specs/bootstrap-and-local-identity-lab/spec.md`

- [ ] **Step 1: Verify implementation against every requirement**

Use the `openspec-verify-change` workflow. For every scenario, cite a behavior
test or inspected implementation path. Resolve every critical or warning
finding before archive.

- [ ] **Step 2: Archive and sync**

Use the `openspec-archive-change` workflow to merge delta requirements into
durable specs and archive the completed change. Preserve checked tasks and the
implementation design.

- [ ] **Step 3: Re-run final validation**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command \
  openspec validate --specs --strict
nix --extra-experimental-features 'nix-command flakes' develop --command \
  openspec validate --changes --strict
nix --extra-experimental-features 'nix-command flakes' develop --command \
  ./bin/verify
git diff --check
```

Expected: durable specs and the repository remain fully green with no active
change left.

- [ ] **Step 4: Commit archive state**

Commit with:

```bash
git add \
  openspec/changes \
  openspec/specs \
  docs/superpowers/plans/2026-07-25-human-session-foundation.md
git commit -m "docs: archive human session foundation"
```
