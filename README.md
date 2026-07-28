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

Office Graph uses an Authentik-compatible OpenID Connect provider for browser
sign-in. The repository Compose file starts Postgres only, so run your local
Authentik identity lab separately and configure an OAuth2/OpenID provider with:

- redirect URI: `http://localhost:4000/auth/callback`
- scopes: `openid`, `profile`, and `email`
- a user whose verified email is `owner@office-graph.local`
- an `email_verified` claim with the boolean value `true`

`mix ecto.setup` creates the matching local Office Graph owner. The login flow
links the verified Authentik identity to that existing principal; it does not
create an owner or grant capabilities from provider claims.

Start the application with the provider values:

```sh
AUTHENTIK_OIDC_ISSUER=http://localhost:9000/application/o/office-graph/ \
AUTHENTIK_OIDC_CLIENT_ID=replace-with-client-id \
AUTHENTIK_OIDC_CLIENT_SECRET=replace-with-client-secret \
AUTHENTIK_ACCOUNT_LINKING_POLICY=verified_email_existing_principal \
nix --extra-experimental-features 'nix-command flakes' develop --command mix phx.server
```

Replace the example issuer with the exact issuer advertised by your Authentik
provider. Then open `http://localhost:4000/operator`; unauthenticated requests
redirect through `/auth/login`.

`AUTHENTIK_PREFERRED_ORGANIZATION_ID` and
`AUTHENTIK_PREFERRED_WORKSPACE_ID` may be set together when a principal belongs
to more than one workspace. `HUMAN_SESSION_TTL_SECONDS` optionally overrides
the default eight-hour session lifetime. Missing or partial OIDC configuration
fails closed with `Authentication unavailable`; it never falls back to the
local-owner bootstrap.

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

Run the canonical repository gate:

```sh
nix --extra-experimental-features 'nix-command flakes' develop --command ./bin/verify
```

`bin/verify` derives a stable Compose project name and test database partition
from the worktree path, then asks Docker to allocate an available loopback host
port so concurrent worktrees do not share database state or contend for a small
fixed port range. It also confirms that the ready Compose server is PostgreSQL
18 before running migrations and tests. `COMPOSE_PROJECT_NAME`,
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
