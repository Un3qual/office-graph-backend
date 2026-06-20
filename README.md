# Office Graph

Office Graph is currently in its first backend walking-skeleton implementation.
OpenSpec artifacts under `openspec/` are the source of truth for scope and
verification.

## Development Shell

Run project commands through the Nix flake:

```sh
nix --extra-experimental-features 'nix-command flakes' develop --command mix deps.get
```

The shell pins Erlang/OTP 29, Elixir 1.20, Node.js 26, and OpenSpec. It also
sets project-local `MIX_HOME` and `HEX_HOME` paths so old user-global Mix
archives do not leak into this runtime.

## Postgres

Start local Postgres with Docker Compose:

```sh
docker compose up -d postgres
docker compose ps postgres
```

The app connects to `localhost:55432` with:

- username: `office_graph`
- password: `office_graph`
- development database: `office_graph_dev`
- test database: `office_graph_test`

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

Run the current backend baseline gate:

```sh
nix --extra-experimental-features 'nix-command flakes' develop --command mix compile --warnings-as-errors
nix --extra-experimental-features 'nix-command flakes' develop --command mix format --check-formatted
nix --extra-experimental-features 'nix-command flakes' develop --command mix test
nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate first-backend-walking-skeleton --strict
nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --changes --strict
```
