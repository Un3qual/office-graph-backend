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
