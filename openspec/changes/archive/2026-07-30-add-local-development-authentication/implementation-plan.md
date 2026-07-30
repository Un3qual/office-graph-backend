# Local Development Authentication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended when explicitly
> authorized) or `superpowers:executing-plans` to implement this plan
> task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an explicitly enabled local identity chooser that issues ordinary
Office Graph sessions for seeded roles, supports safe role switching, and keeps
Authentik and WorkOS as independent integration-test and enterprise providers.

**Architecture:** A fixed manifest under `OfficeGraph.Authentication` owns the
only selectable fixture keys and expected facts. Foundation seeds those facts
through Identity and Authorization Ash actions; Authentication resolves an
exact fixture and delegates to the existing locked session action; Phoenix
exposes a compile-gated, runtime-gated, loopback-only, CSRF-protected chooser.
The React shell exposes ordinary sign-out, and local-development logout returns
to the chooser.

**Tech Stack:** Elixir 1.20, Phoenix 1.8, Ash 3.29, AshPostgres 2.10, PostgreSQL
18, ExUnit, React 19, React Router 7, TypeScript, Vitest, pnpm, OpenSpec 1.4.1,
and the repository Nix flake.

## Global Constraints

- Run every project command through
  `nix --extra-experimental-features 'nix-command flakes' develop -c`.
- OpenSpec under `openspec/**` remains the sole planning and specification
  source; do not add `docs/superpowers/**`.
- Use Ash resource actions and existing boundary APIs; add no direct Ecto,
  explicit `Repo.transaction`, repository-authored raw SQL, or browser-triggered
  bootstrap.
- Local fixture selection accepts only fixed server-owned keys, never a
  principal ID, email, tenant ID, role, or capability from the browser.
- Local authentication requires a development/test route build, explicit
  runtime enablement, and an exact IPv4 or IPv6 loopback peer.
- Local sessions use purpose `human_web`, authentication method
  `local_development`, the existing opaque cookie, and the existing locked
  identity/session issuance and per-request validation.
- WorkOS remains enterprise SSO and Directory Sync without AuthKit; Authentik
  remains the optional generic OIDC integration path.
- Frontend tests stay under `assets/tests/**`, separate from production files.
- Commit each independently passing task and leave unrelated `.cache/` content
  untouched.

---

### Task 1: Define And Persist Exact Local Identity Fixtures

**Files:**

- Create:
  `lib/office_graph/authentication/local_development_fixtures.ex`
- Create:
  `lib/office_graph/identity/actions/ensure_local_development_identity.ex`
- Modify: `lib/office_graph/identity.ex`
- Modify: `lib/office_graph/identity/resources/principal.ex`
- Modify:
  `lib/office_graph/identity/resources/external_identity_link.ex`
- Test:
  `test/office_graph/identity/local_development_identity_test.exs`

**Interfaces:**

- Produces:
  `OfficeGraph.Authentication.LocalDevelopmentFixtures.all/0`,
  `fetch/1`, `provider/0`, and `provider_tenant/0`.
- Produces:
  `OfficeGraph.Identity.ensure_local_development_identity/1` returning
  `{:ok, %{principal: Principal.t(), external_identity_link:
  ExternalIdentityLink.t()}}` or a bounded storage/validation error.
- Produces:
  `OfficeGraph.Identity.local_development_identity/1` returning the exact
  current identity facts for a server-owned fixture map, including disabled
  facts for rejection evidence.
- Consumed by Tasks 2 and 3.

- [ ] **Step 1: Write the fixed manifest test**

Add a test that proves exact keys, unique subjects/emails, provider metadata,
and non-browser-owned authorization profiles:

```elixir
test "local development fixtures expose only stable server-owned keys" do
  fixtures = LocalDevelopmentFixtures.all()

  assert Enum.map(fixtures, & &1.key) ==
           ~w(owner workspace_admin member deprovisioned_member)

  assert Enum.uniq_by(fixtures, & &1.subject) == fixtures
  assert Enum.uniq_by(fixtures, & &1.email) == fixtures
  assert LocalDevelopmentFixtures.fetch("unknown") == :error

  assert Enum.all?(fixtures, fn fixture ->
           fixture.provider == "local_development" and
             fixture.provider_tenant == "office_graph_development" and
             is_atom(fixture.role_profile)
         end)
end
```

- [ ] **Step 2: Run the manifest test and verify RED**

Run:

```sh
nix --extra-experimental-features 'nix-command flakes' develop -c \
  mix test test/office_graph/identity/local_development_identity_test.exs
```

Expected: compilation fails because
`OfficeGraph.Authentication.LocalDevelopmentFixtures` does not exist.

- [ ] **Step 3: Implement the typed manifest**

Create a focused module with no runtime/database behavior:

```elixir
defmodule OfficeGraph.Authentication.LocalDevelopmentFixtures do
  @provider "local_development"
  @provider_tenant "office_graph_development"

  @fixtures [
    %{
      key: "owner",
      subject: "owner",
      email: "owner@office-graph.local",
      display_name: "Office Graph Owner",
      principal_status: "active",
      link_status: "active",
      role_profile: :owner
    },
    %{
      key: "workspace_admin",
      subject: "workspace-admin",
      email: "workspace-admin@office-graph.local",
      display_name: "Workspace Administrator",
      principal_status: "active",
      link_status: "active",
      role_profile: :workspace_admin
    },
    %{
      key: "member",
      subject: "member",
      email: "member@office-graph.local",
      display_name: "Workspace Member",
      principal_status: "active",
      link_status: "active",
      role_profile: :member
    },
    %{
      key: "deprovisioned_member",
      subject: "deprovisioned-member",
      email: "deprovisioned@office-graph.local",
      display_name: "Deprovisioned Member",
      principal_status: "disabled",
      link_status: "disabled",
      role_profile: :member
    }
  ]

  def all do
    Enum.map(@fixtures, &Map.merge(&1, provider_metadata()))
  end

  def fetch(key) when is_binary(key) do
    case Enum.find(all(), &(&1.key == key)) do
      nil -> :error
      fixture -> {:ok, fixture}
    end
  end

  def fetch(_key), do: :error
  def provider, do: @provider
  def provider_tenant, do: @provider_tenant

  defp provider_metadata,
    do: %{provider: @provider, provider_tenant: @provider_tenant}
end
```

- [ ] **Step 4: Add failing identity reconciliation tests**

Cover first creation, idempotent replay, non-reactivation after manual
disablement, exact subject/email validation, and retained disabled facts:

```elixir
test "identity setup is idempotent and does not reactivate disabled facts" do
  fixture = fixture!("member")

  assert {:ok, first} = Identity.ensure_local_development_identity(fixture)
  disable!(first.principal, first.external_identity_link)
  assert {:ok, replayed} = Identity.ensure_local_development_identity(fixture)

  assert replayed.principal.id == first.principal.id
  assert replayed.principal.status == "disabled"
  assert replayed.external_identity_link.id == first.external_identity_link.id
  assert replayed.external_identity_link.status == "disabled"
end
```

- [ ] **Step 5: Run identity tests and verify RED**

Run the same focused test file. Expected: failure because
`Identity.ensure_local_development_identity/1` is undefined.

- [ ] **Step 6: Add one transactional Ash setup action**

Add a private `Principal` action named
`:ensure_local_development_identity`. Its action implementation must:

1. use `Principal :ensure` and `PrincipalProfile :ensure`;
2. use a new `ExternalIdentityLink :ensure_local_development` upsert on the
   existing `provider_subject` identity with `upsert_fields []`;
3. set `first_linked_at`/`disabled_at` only on initial creation;
4. return the three records from the same Ash action transaction;
5. never update lifecycle on replay.

Expose it through `Identity.ensure_local_development_identity/1`. Add
`Identity.local_development_identity/1` as an exact provider/tenant/subject
lookup that verifies expected normalized email and returns current principal
and link facts without authorizing from caller data.

- [ ] **Step 7: Run and format the focused identity slice**

Run:

```sh
nix --extra-experimental-features 'nix-command flakes' develop -c \
  mix test test/office_graph/identity/local_development_identity_test.exs
nix --extra-experimental-features 'nix-command flakes' develop -c \
  mix format --check-formatted
```

Expected: focused tests pass and formatting reports no changes required after
formatting the touched files.

- [ ] **Step 8: Commit the identity fixture boundary**

```sh
git add lib/office_graph/authentication/local_development_fixtures.ex \
  lib/office_graph/identity.ex \
  lib/office_graph/identity/actions/ensure_local_development_identity.ex \
  lib/office_graph/identity/resources/principal.ex \
  lib/office_graph/identity/resources/external_identity_link.ex \
  test/office_graph/identity/local_development_identity_test.exs
git commit -m "feat: define local development identities"
```

---

### Task 2: Seed Real Role And Capability Differences

**Files:**

- Modify:
  `lib/office_graph/authentication/local_development_fixtures.ex`
- Modify:
  `lib/office_graph/authorization/services/reference_catalog.ex`
- Modify: `lib/office_graph/authorization.ex`
- Modify: `lib/office_graph/authorization/role.ex`
- Modify: `lib/office_graph/foundation.ex`
- Modify: `priv/repo/seeds.exs`
- Test: `test/office_graph/foundation/bootstrap_test.exs`
- Test:
  `test/office_graph/authorization/local_development_roles_test.exs`

**Interfaces:**

- Consumes Task 1's fixture manifest and Identity setup function.
- Produces:
  `Authorization.ensure_local_development_role/3`.
- Produces:
  `Foundation.seed_local_development_fixtures/1`, returning
  `{:ok, %{bootstrap: Bootstrap.t(), fixtures: %{String.t() => map()}}}`.
- `mix demo.seed` consumes the returned owner bootstrap session for existing
  demo workflow seeding.

- [ ] **Step 1: Write failing seed replay and authorization tests**

The setup test must call the new Foundation function twice, assert stable IDs
for principals, links, roles, and assignments, and assert the deprovisioned
identity remains disabled.

The authorization test must prove concrete differences:

```elixir
assert :ok = Authorization.authorize(owner_session, :proposed_change_apply)
assert :ok = Authorization.authorize(admin_session, :proposed_change_apply)
assert {:error, :forbidden} =
         Authorization.authorize(member_session, :proposed_change_apply)

assert :ok = Authorization.authorize(member_session, :manual_intake_submit)
assert {:error, :forbidden} =
         Authorization.authorize(admin_session, :enterprise_identity_manage)
assert {:error, :invalid_session} =
         Authentication.resolve_session(deprovisioned_session_id)
```

Use sessions issued through test helpers from the exact seeded external links;
do not build trusted `SessionContext` maps in test code.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```sh
nix --extra-experimental-features 'nix-command flakes' develop -c \
  mix test test/office_graph/foundation/bootstrap_test.exs \
  test/office_graph/authorization/local_development_roles_test.exs
```

Expected: failures for missing development role/setup APIs.

- [ ] **Step 3: Centralize exact role profiles**

Extend the fixture manifest with action atoms, not capability strings:

```elixir
@workspace_admin_actions [
  :skeleton_read,
  :durable_delivery_read,
  :manual_intake_submit,
  :proposed_change_apply,
  :evidence_link,
  :verification_complete,
  :work_packet_create,
  :work_packet_version_create,
  :work_run_start,
  :execution_observation_record,
  :evidence_candidate_create,
  :evidence_accept,
  :graph_relationship_create,
  :graph_relationship_supersede,
  :graph_relationship_archive,
  :graph_relationship_restore,
  :agent_definition_bind,
  :agent_invoke,
  :agent_cancel,
  :agent_approval_resolve,
  :agent_context_expansion_resolve,
  :conversation_write
]

@member_actions [
  :skeleton_read,
  :durable_delivery_read,
  :manual_intake_submit,
  :conversation_write
]
```

Owner continues through `Authorization.ensure_owner_role/2`.
`ReferenceCatalog` maps every action atom to the already recognized capability
key and rejects unknown atoms rather than accepting free-form strings.

- [ ] **Step 4: Add an idempotent Ash role setup action**

Extend the existing role action implementation with mode
`:local_development`. The action must transactionally ensure:

- recognized `Capability` rows;
- a role keyed `workspace_admin` or `member` in the seeded organization;
- exact `RoleCapability` memberships;
- one workspace-scoped `RoleAssignment`.

Use the existing resource identities and `upsert_fields []`. Do not delete
extra capability memberships during seed replay; a mismatch must be detected
by fixture verification/login rather than silently rewriting manually changed
policy.

- [ ] **Step 5: Add Foundation orchestration and update `mix demo.seed`**

Implement:

```elixir
def seed_local_development_fixtures(attrs \\ []) do
  with {:ok, bootstrap} <- bootstrap_local_owner(attrs),
       {:ok, fixtures} <- seed_non_owner_fixtures(bootstrap) do
    {:ok, %{bootstrap: bootstrap, fixtures: Map.put(fixtures, "owner", owner_fixture(bootstrap))}}
  end
end
```

The browser must never call this function. Change `priv/repo/seeds.exs` to use
the returned `bootstrap.session` for current workflow examples and print the
four stable fixture labels without IDs or credentials.

- [ ] **Step 6: Run the fixture and role tests GREEN**

Run the two focused test files and `mix demo.seed` against the development
database after ordinary `mix ecto.setup`. Expected: all tests pass and repeated
seed execution reports the same fixtures without duplicates.

- [ ] **Step 7: Commit deterministic role fixtures**

```sh
git add lib/office_graph/authentication/local_development_fixtures.ex \
  lib/office_graph/authorization.ex \
  lib/office_graph/authorization/role.ex \
  lib/office_graph/authorization/services/reference_catalog.ex \
  lib/office_graph/foundation.ex priv/repo/seeds.exs \
  test/office_graph/foundation/bootstrap_test.exs \
  test/office_graph/authorization/local_development_roles_test.exs
git commit -m "feat: seed local development roles"
```

---

### Task 3: Issue And Revalidate Ordinary Local Human Sessions

**Files:**

- Create:
  `lib/office_graph/authentication/local_development.ex`
- Modify: `lib/office_graph/authentication.ex`
- Modify: `config/runtime.exs`
- Modify: `config/test.exs`
- Test: `test/office_graph/authentication/local_development_test.exs`

**Interfaces:**

- Consumes Task 1's manifest and identity lookup and Task 2's seeded role facts.
- Produces:
  `OfficeGraph.Authentication.LocalDevelopment.enabled?/0`.
- Produces:
  `Authentication.complete_local_development_login/2` with
  `fixture_key`, `return_to`, `trace_id`, and `source_surface` options.
- Extends `Authentication.resolve_session/2` so a
  `local_development` session is rejected whenever the provider is disabled.
- Extends `Authentication.logout/2` success metadata with
  `authentication_method`.

- [ ] **Step 1: Write failing local session tests**

Cover:

- disabled config returns `{:error, :authentication_unavailable}`;
- active owner/admin/member fixtures issue `human_web` sessions with
  `authentication_method == "local_development"`;
- unknown keys do not query by email/ID or issue a session;
- disabled fixture returns `:identity_disabled` with a bounded rejected login
  event;
- changing principal/link lifecycle after issue invalidates the next resolve;
- disabling local authentication invalidates and revokes an existing local
  session;
- Authentik and WorkOS session resolution remains unchanged.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```sh
nix --extra-experimental-features 'nix-command flakes' develop -c \
  mix test test/office_graph/authentication/local_development_test.exs
```

Expected: failure because `complete_local_development_login/2` does not exist.

- [ ] **Step 3: Implement the provider gate**

`config/runtime.exs` must set:

```elixir
local_development_authentication_enabled? =
  config_env() == :dev and
    System.get_env("LOCAL_DEV_AUTH_ENABLED") in ~w(true 1)

config :office_graph, :local_development_authentication,
  enabled: local_development_authentication_enabled?
```

Tests override this application setting around each non-async test. The
provider module returns true only when the application setting is exactly true;
it contains no environment-variable parsing or web request logic.

- [ ] **Step 4: Implement bounded fixture login**

The boundary flow is:

```elixir
with true <- LocalDevelopment.enabled?(),
     {:ok, fixture} <- LocalDevelopmentFixtures.fetch(fixture_key),
     {:ok, linked} <- Identity.local_development_identity(fixture),
     {:ok, scope} <- Authorization.resolve_login_scope(linked.principal.id),
     {:ok, issued} <-
       Identity.issue_human_session(
         linked.principal,
         linked.external_identity_link,
         scope,
         authentication_method: "local_development",
         source_surface: source_surface,
         trace_id: trace_id,
         ttl_seconds: session_ttl_seconds()
       ) do
  {:ok, Map.merge(issued, linked)}
end
```

Normalize unknown/missing/drifted fixtures to
`:authentication_unavailable`; preserve `:identity_disabled`,
`:principal_disabled`, and storage errors. Reuse the existing bounded
authentication-event recording path with method `local_development`.

- [ ] **Step 5: Reject local sessions when the provider gate closes**

Add a `validate_current_authentication_basis/2` clause for
`authentication_method: "local_development"`. If disabled, invoke
`Identity.reject_human_session/3` with bounded reason `identity_disabled`;
never treat an old development session as generic OIDC or an ordinary
provider-neutral session in production.

Add `authentication_method` to successful `Authentication.logout/2` output so
the web controller can select the local chooser after revocation without
reading the session after it is revoked.

- [ ] **Step 6: Run focused authentication suites GREEN**

Run:

```sh
nix --extra-experimental-features 'nix-command flakes' develop -c \
  mix test test/office_graph/authentication/local_development_test.exs \
  test/office_graph/authentication_test.exs \
  test/office_graph/enterprise_identity/workos_authentication_test.exs
```

Expected: all focused tests pass with no WorkOS or Authentik network calls.

- [ ] **Step 7: Commit local session orchestration**

```sh
git add config/runtime.exs config/test.exs \
  lib/office_graph/authentication.ex \
  lib/office_graph/authentication/local_development.ex \
  test/office_graph/authentication/local_development_test.exs
git commit -m "feat: issue local development sessions"
```

---

### Task 4: Add The Safe Browser Chooser And Typed Errors

**Files:**

- Create:
  `lib/office_graph_web/local_development_authentication_plug.ex`
- Create:
  `lib/office_graph_web/authentication_return_target.ex`
- Create:
  `lib/office_graph_web/controllers/local_development_authentication_controller.ex`
- Modify:
  `lib/office_graph_web/controllers/authentication_controller.ex`
- Modify: `lib/office_graph_web/router.ex`
- Modify: `config/config.exs`
- Modify: `config/dev.exs`
- Modify: `config/test.exs`
- Test:
  `test/office_graph_web/local_development_authentication_controller_test.exs`
- Test: `test/office_graph_web/authentication_controller_test.exs`

**Interfaces:**

- Consumes Task 3's local login and provider gate.
- Produces:
  `LocalDevelopmentAuthenticationPlug.available?/1`, accepting only exact
  IPv4 `{127, 0, 0, 1}` or IPv6 `{0, 0, 0, 0, 0, 0, 0, 1}` peers.
- Produces shared `AuthenticationReturnTarget.safe/1`.
- Produces compile-gated POST routes
  `/auth/development/login` and `/auth/development/switch`.
- `/auth/login` remains the stable entry point.

- [ ] **Step 1: Write failing transport/gate tests**

Cover:

- enabled loopback GET `/auth/login?return_to=/runs` returns `text/html`,
  status 200, four fixed labels, no principal IDs, and no cookie session ID;
- disabled or non-loopback local auth does not expose chooser or selection;
- POST without `_csrf_token` returns 403;
- unknown key returns bounded 401/503 without a session;
- eligible selection redirects to the signed-session return target;
- external, encoded-backslash, control-character, invalid UTF-8, and
  double-encoded return targets still become `/operator`;
- missing fixture response says `mix demo.seed` only in local development;
- unavailable OIDC and callback failures set an explicit safe content type.

- [ ] **Step 2: Run controller tests and verify RED**

Run:

```sh
nix --extra-experimental-features 'nix-command flakes' develop -c \
  mix test test/office_graph_web/local_development_authentication_controller_test.exs \
  test/office_graph_web/authentication_controller_test.exs
```

Expected: missing controller/route failures and the existing missing-content
type assertion fails.

- [ ] **Step 3: Add compile-time route and runtime request gates**

Set a compile-time route flag false in `config/config.exs`, true in
`config/dev.exs` and `config/test.exs`. Wrap only the development selection and
switch routes in:

```elixir
if Application.compile_env(:office_graph, :local_development_authentication_routes, false) do
  scope "/", OfficeGraphWeb do
    pipe_through [:browser_session, :local_development_authentication]
    post "/auth/development/login", LocalDevelopmentAuthenticationController, :create
    post "/auth/development/switch", LocalDevelopmentAuthenticationController, :switch
  end
end
```

The pipeline calls the loopback/runtime gate and `:protect_from_forgery`.
Unavailable requests return a typed 404 and halt.

- [ ] **Step 4: Extract and retain return-target hardening**

Move the current recursively decoded, valid-UTF-8, root-relative target logic
unchanged into `AuthenticationReturnTarget.safe/1`. Update
`RequireHumanSessionPlug` and both authentication controllers to use it.

On chooser GET, store the safe target in the signed browser session under
`:local_development_return_to`; do not echo a caller-provided target into form
HTML. On create, consume that value before attempting issuance.

- [ ] **Step 5: Render a server-owned chooser with CSRF forms**

When local auth is available and `params["provider"] != "oidc"`,
`AuthenticationController.login/2` delegates rendering to the focused local
controller. Render only fixture labels and keys from the manifest. Each form
posts:

```html
<form action="/auth/development/login" method="post">
  <input name="_csrf_token" type="hidden" value="...">
  <button name="fixture" type="submit" value="owner">
    Office Graph Owner
  </button>
</form>
```

Generate the token with `Plug.CSRFProtection.get_csrf_token/0` and escape all
manifest display text with `Plug.HTML.html_escape/1`. If OIDC configuration is
complete, include a link to `/auth/login?provider=oidc`; that branch calls the
existing OIDC start function.

- [ ] **Step 6: Centralize typed authentication responses**

Replace every bare browser `send_resp/3` in the authentication controllers with
a helper that calls `put_resp_content_type("text/html")` or
`put_resp_content_type("text/plain")` before the bounded body. Local missing
fixture copy may name `mix demo.seed`; generic production errors remain
`Authentication unavailable` or `Authentication failed`.

- [ ] **Step 7: Run all web authentication tests GREEN**

Run the focused controller tests plus:

```sh
nix --extra-experimental-features 'nix-command flakes' develop -c \
  mix test test/office_graph_web/authentication_controller_test.exs \
  test/office_graph_web/operator_console_controller_test.exs
```

- [ ] **Step 8: Commit the browser chooser**

```sh
git add config/config.exs config/dev.exs config/test.exs \
  lib/office_graph_web/router.ex \
  lib/office_graph_web/authentication_return_target.ex \
  lib/office_graph_web/local_development_authentication_plug.ex \
  lib/office_graph_web/controllers/authentication_controller.ex \
  lib/office_graph_web/controllers/local_development_authentication_controller.ex \
  test/office_graph_web/authentication_controller_test.exs \
  test/office_graph_web/local_development_authentication_controller_test.exs
git commit -m "feat: add local development login chooser"
```

---

### Task 5: Add Ordinary Sign-Out And Role Switching

**Files:**

- Create: `assets/src/ui/SessionActions.tsx`
- Modify: `assets/src/ui/WorkspaceShell.tsx`
- Modify: `assets/src/styles/shared.css`
- Test: `assets/tests/src/ui/sessionActions.test.tsx`
- Modify:
  `lib/office_graph_web/controllers/authentication_controller.ex`
- Test: `test/office_graph_web/authentication_controller_test.exs`

**Interfaces:**

- Consumes Task 3's logout authentication-method metadata.
- Produces a standard POST `/auth/logout` control on all authenticated product
  shells.
- Local-development logout redirects to `/auth/login`; OIDC provider logout,
  WorkOS passive logout, and generic passive logged-out behavior stay intact.

- [ ] **Step 1: Write failing frontend sign-out tests**

Render `WorkspaceShell` and assert:

```tsx
const form = screen.getByRole("button", { name: "Sign out" }).closest("form");
expect(form).toHaveAttribute("action", "/auth/logout");
expect(form).toHaveAttribute("method", "post");
expect(screen.queryByText(/owner|workspace administrator|member/i)).not.toBeInTheDocument();
```

The production React shell must expose no fixture list, local-auth flag, email,
or session identifier.

- [ ] **Step 2: Run Vitest and verify RED**

Run:

```sh
nix --extra-experimental-features 'nix-command flakes' develop -c \
  pnpm --dir assets exec vitest run tests/src/ui/sessionActions.test.tsx
```

Expected: module or accessible button is missing.

- [ ] **Step 3: Implement the shared session action**

`SessionActions.tsx` renders only the native POST form and generic `Sign out`
button. `WorkspaceShell` places it in the shared top bar alongside any
route-owned header actions. Add generic styles without route/product role
vocabulary and without Tailwind.

- [ ] **Step 4: Write failing local logout redirect tests**

Issue a real `local_development` session, POST `/auth/logout` with the expected
same-origin header, and assert:

```elixir
assert redirected_to(conn) == "/auth/login"
refute get_session(conn, :human_session_id)
assert {:error, :invalid_session} =
         Authentication.resolve_session(issued.session.id)
```

Retain existing tests that Authentik logout may redirect externally and WorkOS
logout never uses the Authentik endpoint.

- [ ] **Step 5: Implement provider-aware post-logout routing**

When `Authentication.logout/2` returns method `local_development`, and the
local provider is still enabled, clear the cookie and redirect to
`/auth/login`. On revocation failure preserve the cookie and return typed 503.
For every other method, preserve the current provider/passive behavior.

The separate CSRF-protected `/auth/development/switch` action uses the same
logout function, preserves a safe current return target in the signed session,
and redirects to `/auth/login` only after successful revocation.

- [ ] **Step 6: Run frontend and backend switching suites GREEN**

Run:

```sh
nix --extra-experimental-features 'nix-command flakes' develop -c \
  pnpm --dir assets exec vitest run tests/src/ui/sessionActions.test.tsx \
  tests/src/ui/primitives.test.tsx
nix --extra-experimental-features 'nix-command flakes' develop -c \
  mix test test/office_graph_web/authentication_controller_test.exs \
  test/office_graph_web/local_development_authentication_controller_test.exs
```

- [ ] **Step 7: Commit role switching**

```sh
git add assets/src/ui/SessionActions.tsx \
  assets/src/ui/WorkspaceShell.tsx assets/src/styles/shared.css \
  assets/tests/src/ui/sessionActions.test.tsx \
  lib/office_graph_web/controllers/authentication_controller.ex \
  test/office_graph_web/authentication_controller_test.exs
git commit -m "feat: switch local development identities"
```

---

### Task 6: Document, Verify, Sync, And Archive

**Files:**

- Modify: `README.md`
- Modify:
  `openspec/changes/add-local-development-authentication/tasks.md`
- Sync:
  `openspec/specs/human-authentication/spec.md`
- Sync:
  `openspec/specs/bootstrap-and-local-identity-lab/spec.md`
- Sync:
  `openspec/specs/session-and-token-model/spec.md`

**Interfaces:**

- No new runtime interface.
- Produces a complete, synced, archived OpenSpec change after all tests and
  review pass.

- [ ] **Step 1: Update local setup documentation**

Document this exact fast path:

```sh
docker compose up -d postgres
nix --extra-experimental-features 'nix-command flakes' develop -c mix ecto.setup
nix --extra-experimental-features 'nix-command flakes' develop -c mix demo.seed
LOCAL_DEV_AUTH_ENABLED=true \
  nix --extra-experimental-features 'nix-command flakes' develop -c mix phx.server
```

Explain `/auth/login`, owner/admin/member selection, deprovisioned rejection,
Sign out for switching, optional Authentik OIDC testing, and WorkOS enterprise
SSO/Directory Sync testing. State that local auth is unsuitable for shared or
production servers.

- [ ] **Step 2: Run focused verification**

Run all new and affected backend tests, then:

```sh
nix --extra-experimental-features 'nix-command flakes' develop -c \
  mix compile --warnings-as-errors
nix --extra-experimental-features 'nix-command flakes' develop -c \
  mix format --check-formatted
nix --extra-experimental-features 'nix-command flakes' develop -c \
  pnpm --dir assets run relay:check
nix --extra-experimental-features 'nix-command flakes' develop -c \
  pnpm --dir assets run typecheck
nix --extra-experimental-features 'nix-command flakes' develop -c \
  pnpm --dir assets run test
nix --extra-experimental-features 'nix-command flakes' develop -c \
  pnpm --dir assets run lint
nix --extra-experimental-features 'nix-command flakes' develop -c \
  pnpm --dir assets run format:check
```

- [ ] **Step 3: Run architecture, migration, and strict spec gates**

Run:

```sh
nix --extra-experimental-features 'nix-command flakes' develop -c \
  openspec validate --changes --strict
nix --extra-experimental-features 'nix-command flakes' develop -c \
  openspec validate --specs --strict
nix --extra-experimental-features 'nix-command flakes' develop -c \
  mix migration.drift
nix --extra-experimental-features 'nix-command flakes' develop -c \
  mix architecture.conformance
nix --extra-experimental-features 'nix-command flakes' develop -c \
  mix static.analysis
```

Review the diff for production route leakage, arbitrary impersonation,
request-time bootstrap, stale local-session reuse, raw SQL, direct Ecto,
explicit `Repo.transaction`, frontend co-located tests, and unrelated edits.

- [ ] **Step 4: Run the canonical repository gate**

Run:

```sh
nix --extra-experimental-features 'nix-command flakes' develop -c ./bin/verify
```

Expected: backend, frontend, production build, PostgreSQL 18 migration replay,
OpenSpec, architecture, security/dependency, format, and static-analysis gates
all pass.

- [ ] **Step 5: Complete and sync OpenSpec**

Mark every verified task in `tasks.md`, run
`openspec-verify-change`, then sync the three delta specs into canonical specs
with `openspec-sync-specs`. Re-run strict validation after sync.

- [ ] **Step 6: Commit documentation and verified OpenSpec state**

```sh
git add README.md openspec
git commit -m "docs: complete local development authentication"
```

- [ ] **Step 7: Archive only after implementation review**

After the implementation diff and verification evidence are accepted, run the
OpenSpec archive workflow. Commit the archive move separately so the change
history and canonical specs remain easy to review.
