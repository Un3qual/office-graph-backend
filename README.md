# Office Graph

Office Graph is currently in its first backend walking-skeleton implementation.
OpenSpec artifacts under `openspec/` are the source of truth for scope and
verification.

## Development Shell

Run project commands through the Nix flake:

```sh
nix --extra-experimental-features 'nix-command flakes' develop --command mix deps.get
```

The shell pins Erlang/OTP 29, Elixir 1.20, Node.js 26, OpenSpec, zsh, and the
Docker/Compose CLI used by the local Postgres helpers. It also sets
project-local `MIX_HOME` and `HEX_HOME` paths so old user-global Mix archives do
not leak into this runtime.

## Local Postgres

The canonical verification command starts and waits for an isolated Postgres
service automatically. For focused development, start the default service with:

```sh
docker compose up -d postgres
docker compose ps postgres
```

The repository-managed service runs PostgreSQL 18 so durable Ash resources can
use PostgreSQL's native UUIDv7 generator. The PostgreSQL 18 container stores its
versioned data directory below `/var/lib/postgresql`.

The app connects to `localhost:55432` with:

- username: `office_graph`
- password: `office_graph`
- development database: `office_graph_dev`
- test database: `office_graph_test`

Production runtime config enables Postgres TLS by default. Set
`DATABASE_SSL=false` only for an explicitly trusted private database network.

## Local Human Sign-In

Routine development does not require WorkOS, Authentik, or another hosted
identity provider. Prepare the database and deterministic local identities,
then explicitly enable the loopback-only development provider:

```sh
docker compose up -d postgres
nix --extra-experimental-features 'nix-command flakes' develop --command mix ecto.setup
nix --extra-experimental-features 'nix-command flakes' develop --command mix demo.seed
LOCAL_DEV_AUTH_ENABLED=true \
nix --extra-experimental-features 'nix-command flakes' develop --command mix phx.server
```

Open `http://localhost:4000/operator`, `http://localhost:4000/packets`, or
`http://localhost:4000/runs`. `/auth/login` presents fixed owner, workspace
administrator, member, and deprovisioned-member fixtures. Each selection issues
a normal durable Office Graph human session and exercises the fixture's real
role and capability assignments. Use the product-shell **Sign out** action to
return to the chooser and test another role.

`LOCAL_DEV_AUTH_ENABLED` is honored only by the development runtime. The
fixture-selection routes are omitted from production builds, require an exact
loopback peer, accept only server-owned selector keys, and never seed or repair
identity data during a browser request. If the chooser reports missing
fixtures, rerun `mix demo.seed`.

### Optional Authentik Compatibility Testing

Authentik remains an optional generic OIDC integration fixture; it is not
required for routine local product testing. Run an Authentik identity lab
separately and configure an OAuth2/OpenID provider with:

- redirect URI: `http://localhost:4000/auth/callback`
- scopes: `openid`, `profile`, and `email`
- a user whose verified email is `owner@office-graph.local`
- an `email_verified` claim with the boolean value `true`

`mix demo.seed` creates the matching Office Graph owner and optional
operator-console examples. The OIDC flow links the verified Authentik identity
to that existing principal; it does not create an owner or grant capabilities
from provider claims.

Start the application with the provider values:

```sh
AUTHENTIK_OIDC_ISSUER=http://localhost:9000/application/o/office-graph/ \
AUTHENTIK_OIDC_CLIENT_ID=replace-with-client-id \
AUTHENTIK_OIDC_CLIENT_SECRET=replace-with-client-secret \
AUTHENTIK_ACCOUNT_LINKING_POLICY=verified_email_existing_principal \
nix --extra-experimental-features 'nix-command flakes' develop --command mix phx.server
```

Replace the example issuer with the exact issuer advertised by your Authentik
provider. With local development authentication also enabled, choose **Use
optional Authentik OIDC** from `/auth/login`; otherwise `/auth/login` starts the
OIDC flow directly.

`AUTHENTIK_PREFERRED_ORGANIZATION_ID` and
`AUTHENTIK_PREFERRED_WORKSPACE_ID` may be set together when a principal belongs
to more than one workspace. `HUMAN_SESSION_TTL_SECONDS` optionally overrides
the default eight-hour session lifetime. Missing or partial OIDC configuration
fails closed with `Authentication unavailable`; it never falls back to the
local-owner bootstrap.

## WorkOS Enterprise Identity

WorkOS is an optional managed enterprise adapter for standalone SSO and
Directory Sync. Office Graph continues to own principals, sessions,
authorization, and the local development provider; it does not use AuthKit or
WorkOS-hosted sessions. Authentik is retained only for optional generic OIDC
compatibility testing.

Configure global provider access with references rather than secret values:

```sh
WORKOS_CLIENT_ID=client_... \
WORKOS_API_KEY_REFERENCE=env:WORKOS_API_KEY \
WORKOS_WEBHOOK_SECRET_REFERENCE=env:WORKOS_WEBHOOK_SECRET \
WORKOS_API_KEY=sk_... \
WORKOS_WEBHOOK_SECRET=whsec_... \
nix --extra-experimental-features 'nix-command flakes' develop --command mix phx.server
```

`WORKOS_API_BASE_URL` defaults to `https://api.workos.com`.
`WORKOS_SESSION_TTL_SECONDS` optionally overrides the default eight-hour Office
Graph session lifetime. The production environment secret adapter accepts only
`env:VARIABLE_NAME` references. Secret values, access tokens, and raw WorkOS
profile payloads are never stored in enterprise identity resources.

Each customer binding is an authorized `EnterpriseConnection` record naming
the exact Office Graph organization/workspace and WorkOS organization. The
browser entry point is `/auth/workos/:connection_id/login`; callback parameters
cannot select or change that connection. Group memberships grant authority only
through explicit active `ExternalGroupRoleMapping` records to existing Office
Graph roles at the exact mapping scope.

Configure the WorkOS Directory Sync webhook as:

```text
https://YOUR_OFFICE_GRAPH_HOST/api/v1/webhooks/workos
```

The endpoint verifies the WorkOS timestamped signature against the exact raw
request body before it archives or processes a delivery. Rotating an API or
webhook key requires changing only the value behind its configured secret
reference; restart the release after environment-backed rotation so runtime
configuration is refreshed. Disable the affected connection during a
connection-specific incident.

Normal tests use deterministic SSO, HTTP, signature, and secret-store fakes and
require no WorkOS account. An optional sandbox smoke test should use a
non-production WorkOS organization, create the connection through
`OfficeGraph.EnterpriseIdentity`'s authorized management API, verify one SSO
login and one Directory Sync delivery, and then disable the sandbox connection.
Never put sandbox credentials or provider payloads in fixtures or source
control.

## GitHub App Runtime

Development and production use the live GitHub App adapter. Set
`GITHUB_APP_ID` to the numeric App ID before processing GitHub reconciliation or
outbound jobs. Installation binding stores only credential references; with the
environment secret store, point those references at variables such as
`env:GITHUB_APP_PRIVATE_KEY` and `env:GITHUB_WEBHOOK_SECRET`.

GitHub.com uses `https://api.github.com` by default. GitHub Enterprise Server
deployments can set `GITHUB_API_URL` and `GITHUB_GRAPHQL_URL` explicitly. Normal
tests replace the live adapter and secret store with deterministic in-memory
implementations and require no GitHub credentials or network access.

Stop Postgres:

```sh
docker compose stop postgres
```

Reset local database state:

```sh
docker compose down -v
docker compose up -d postgres
nix --extra-experimental-features 'nix-command flakes' develop --command mix ecto.setup
```

An existing repository-managed PostgreSQL 17 volume cannot be mounted directly
by PostgreSQL 18. Because local Compose data is disposable, use the reset
sequence above when upgrading this checkout. For a database whose data must be
preserved, perform an explicit PostgreSQL major-version upgrade outside this
Compose workflow instead of removing its volume.

The unreleased migration history was also replaced by one current logical
baseline. Any local database created from the old migration chain must use the
same database/volume reset before applying the new baseline, even if it already
runs PostgreSQL 18. Export and explicitly re-import any development data that
must be preserved; the old chain is retained in Git history, not as a supported
upgrade path.

## Setup And Verification

Fetch dependencies:

```sh
nix --extra-experimental-features 'nix-command flakes' develop --command mix deps.get
```

Prepare the database:

```sh
docker compose up -d postgres
nix --extra-experimental-features 'nix-command flakes' develop --command mix ecto.setup
```

Migrations create schema only, apart from Oban's dependency-owned schema
installer. `mix ecto.setup` then runs the idempotent
`OfficeGraph.Release.setup!()` entry point once to reconcile required
capabilities, relationship registry records, and the canonical run-review agent
definition through Ash.

Demo data is optional:

```sh
nix --extra-experimental-features 'nix-command flakes' develop --command mix demo.seed
```

Packaged releases run the same canonical setup after migration:

```sh
bin/office_graph eval "OfficeGraph.Release.setup!()"
```

Run the canonical repository gate:

```sh
nix --extra-experimental-features 'nix-command flakes' develop --command ./bin/verify
```

`bin/verify` derives a stable Compose project name and test database partition
from the worktree path, then asks Docker to allocate an available loopback host
port so concurrent worktrees do not share database state or contend for a small
fixed port range. It also confirms that the ready Compose server is PostgreSQL
18, checks migration drift without rewriting snapshots, migrates an empty
scratch database, replays release setup, and proves rollback/re-application
before running the full gate. `COMPOSE_PROJECT_NAME`,
`OFFICE_GRAPH_POSTGRES_PORT`, and `MIX_TEST_PARTITION` override those defaults.

When PostgreSQL is managed externally, skip Compose and provide explicit test
connection settings:

```sh
OFFICE_GRAPH_SKIP_COMPOSE=1 \
OFFICE_GRAPH_TEST_DATABASE_HOST=localhost \
OFFICE_GRAPH_TEST_DATABASE_PORT=5432 \
MIX_TEST_PARTITION=_local \
nix --extra-experimental-features 'nix-command flakes' develop --command ./bin/verify
```

Focused developer commands remain available inside the Nix shell:

```sh
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/work_graph/walking_skeleton_test.exs
nix --extra-experimental-features 'nix-command flakes' develop --command mix architecture.conformance
nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets test
nix --extra-experimental-features 'nix-command flakes' develop --command mix dependency.audit
nix --extra-experimental-features 'nix-command flakes' develop --command mix frontend.verify
nix --extra-experimental-features 'nix-command flakes' develop --command mix test
nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --specs --strict
nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --changes --strict
```

Successful database queries are quiet in the test environment. Enable query
debug logging for a focused diagnostic run without changing tracked config:

```sh
OFFICE_GRAPH_TEST_SQL_LOG=1 nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/path/to/failing_test.exs
```

The historical script name remains for compatibility and delegates to the
canonical `bin/verify` entry point:

```sh
nix --extra-experimental-features 'nix-command flakes' develop --command ./bin/verify-backend
```

If Postgres is already provided outside Docker Compose, skip the local Compose
startup:

```sh
OFFICE_GRAPH_SKIP_COMPOSE=1 nix --extra-experimental-features 'nix-command flakes' develop --command ./bin/verify-backend
```
