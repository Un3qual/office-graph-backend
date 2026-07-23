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

The app connects to `localhost:55432` with:

- username: `office_graph`
- password: `office_graph`
- development database: `office_graph_dev`
- test database: `office_graph_test`

Production runtime config enables Postgres TLS by default. Set
`DATABASE_SSL=false` only for an explicitly trusted private database network.

## Agent Runtime Repository Tooling

The automatic OpenSpec-review agent requires an immutable repository mount and
explicit Git and OpenSpec executables. Production starts fail closed before
Oban workers are started unless all three absolute paths are configured and the
runtime can verify a clean, self-contained checkout, read its `HEAD` and
`openspec/project.md`, and parse bounded `openspec list --json` output:

- `OFFICE_GRAPH_AGENT_RUNTIME_REPOSITORY_ROOT`
- `OFFICE_GRAPH_AGENT_RUNTIME_GIT_EXECUTABLE`
- `OFFICE_GRAPH_AGENT_RUNTIME_OPENSPEC_EXECUTABLE`

Build the pinned tool closure with:

```sh
nix --extra-experimental-features 'nix-command flakes' build .#agent-runtime-tools
```

Mount a complete, self-contained Git clone read-only at the configured root.
The clone must include its own object database; a linked worktree whose `.git`
file points outside the mount is not valid. Keep the checkout fixed for the
process lifetime and restart the application after atomically replacing it with
a new revision. Do not bypass ownership checks with a broad
`safe.directory=*` setting.

Each OpenSpec tool request carries the same full revision used by repository
reads and fails closed if the mounted checkout's `HEAD` changes before the CLI
is invoked.

The packaged OpenSpec executable and the application command boundary force
OpenSpec telemetry off. Ambient `OPENSPEC_TELEMETRY` values cannot enable local
telemetry configuration writes or outbound telemetry for runtime reads.

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
fixed port range. `COMPOSE_PROJECT_NAME`, `OFFICE_GRAPH_POSTGRES_PORT`, and
`MIX_TEST_PARTITION` override those defaults.

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
