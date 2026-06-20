## ADDED Requirements

### Requirement: Phoenix API Application Baseline
Office Graph SHALL start backend implementation as a single Phoenix API
application at the repository root.

#### Scenario: Backend application is generated
- **WHEN** the first backend app-generation task runs
- **THEN** it MUST create an `OfficeGraph` Phoenix API application with
  `OfficeGraphWeb` entrypoints, Ecto/Postgres support, no LiveView product UI,
  no HTML view layer, and no frontend asset pipeline as part of this change

#### Scenario: React frontend is considered
- **WHEN** frontend concerns arise during this backend change
- **THEN** the implementation MUST leave React app creation to a later
  frontend change and expose only backend API and realtime-ready foundations

### Requirement: Backend Dependency Baseline
Office Graph SHALL configure only the backend dependencies needed for the
walking skeleton and its verification gates.

#### Scenario: Dependencies are added
- **WHEN** `mix.exs` and config files are created
- **THEN** they MUST include Phoenix API, Ecto/Postgres, Ash, Boundary,
  GraphQL, JSON API support, test support, and project verification tooling
  needed by the walking skeleton without adding provider-specific integration,
  full agent-runtime, or frontend dependencies

### Requirement: Boundary Context Baseline
Office Graph SHALL enforce modular monolith boundaries from the first backend
cut.

#### Scenario: Context modules are created
- **WHEN** backend modules are introduced
- **THEN** public context modules MUST live under `OfficeGraph` public context
  entrypoints, internal modules MUST stay below their owning context, and
  Boundary rules MUST prevent direct imports of another context's internals

#### Scenario: A context is not implemented yet
- **WHEN** a future context from the accepted context map is not needed for the
  walking skeleton
- **THEN** the first backend cut MAY omit its implementation while preserving
  dependency direction and avoiding placeholder behavior that callers rely on

### Requirement: Nix-Shell Tooling Contract
Office Graph SHALL run project setup and verification through the project Nix
shell.

#### Scenario: Developer runs backend commands
- **WHEN** a developer runs setup, dependency, compile, format, test, Boundary,
  database, or OpenSpec commands
- **THEN** documented commands MUST use
  `nix --extra-experimental-features 'nix-command flakes' develop --command`
  or execute from inside the equivalent Nix development shell

### Requirement: Docker Compose Development Postgres
Office Graph SHALL use Docker Compose to run Postgres for local development and
test database workflows.

#### Scenario: Local database is needed
- **WHEN** a developer starts, stops, resets, or prepares the local Postgres
  database for development or tests
- **THEN** the documented path MUST use a checked-in Docker Compose
  configuration with a named Postgres service, stable local connection
  settings, health check, and durable named volume rather than a Nix-managed
  Postgres process or an assumed host-local database

#### Scenario: Application commands use the database
- **WHEN** Mix, Ecto, test, API, or verification commands connect to Postgres
- **THEN** those application commands MUST still run through the project Nix
  shell while Docker Compose owns only the local Postgres service lifecycle

### Requirement: No Broad Runtime Surface In Baseline
Office Graph SHALL keep the first app baseline focused on the walking
skeleton.

#### Scenario: Non-skeleton feature is requested during implementation
- **WHEN** a feature requires full agent runtime, provider webhooks, frontend
  screens, generic ordered placement, rich text editor collaboration, or
  production deployment behavior
- **THEN** it MUST be deferred to a dedicated future OpenSpec change unless it
  is required to pass the walking-skeleton verification gate
