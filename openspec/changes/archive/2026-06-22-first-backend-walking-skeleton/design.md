## Context

The repository currently contains OpenSpec planning artifacts and a Nix
development shell, but no Phoenix application yet. The active design changes
now define the backend-readiness gate: identity and authorization inventory,
authentication mechanics, work-graph semantics, persistence boundaries,
revision/audit/soft-delete posture, ingestion contracts, proposed graph
changes, and code organization are ready enough to start the first app cut.

The first executable target is intentionally narrow:

```text
manual intake signal
  -> task
  -> review finding
  -> required verification check
  -> evidence item
  -> verified completion
```

This change consumes the active design changes without archiving or promoting
them. It creates the implementation plan that will generate the Phoenix API
app, establish the modular monolith boundaries, and prove the loop with real
storage, actions, API calls, and tests.

## Goals / Non-Goals

**Goals:**

- Generate the first Phoenix API backend at the repository root using the
  project Nix shell for runtime and CLI dependencies.
- Add a Docker Compose managed Postgres service for local development and
  tests, with documented `docker compose` commands for starting, stopping, and
  resetting the database.
- Configure Ecto/Postgres, Ash, Boundary, Absinthe GraphQL, JSON API support,
  ExUnit, formatting, and project verification commands.
- Implement the minimum bounded contexts and public context modules needed for
  identity, tenancy, authorization, operations, work containers, work graph,
  content, ingestion, proposed changes, software proving, verification,
  revisions, audit, and API entrypoints.
- Add the minimal relational schema and Ash/Ecto resources needed to prove the
  walking skeleton with stable extension points for later rich text, ordering,
  agent runtime, run, projection, and integration work.
- Provide first-organization and first-owner bootstrap for local development,
  test, and controlled first setup.
- Expose GraphQL and JSON API surfaces that call the same domain actions and
  share the same authentication/authorization path.
- Add tests and gates for compile, format, Boundary, migrations/resources,
  authorization filtering, API smoke coverage, OpenSpec validation, and the
  complete walking-skeleton scenario.

**Non-Goals:**

- No React frontend, LiveView, HTML product UI, or polished admin screens.
- No full authentik/Keycloak/SCIM identity lab implementation; only the
  bootstrap and local identity seams required by the first backend cut.
- No generic agent runtime, broad work-packet planner, complete run system, or
  autonomous tool execution.
- No provider webhooks, GitHub/Sentry/API polling, provider-specific extension
  packages, or external writes.
- No complete rich text editor, Lexical persistence, collaboration state,
  quote engine, generic ordered-placement API, or projection read-model system.
- No production deployment, release packaging, SIEM export, legal-hold UI, or
  customer-facing billing/administration features.

## Decisions

### 1. Generate one Phoenix API app at the repo root

The first implementation should create a single Phoenix application rooted in
this repository, with `OfficeGraph` as the main Elixir module and
`OfficeGraphWeb` as the API/entrypoint module. It should use the Phoenix API
shape and disable LiveView, HTML views, and frontend assets. React remains the
future UI, but this change should not create the React app.

Alternatives considered:

- **Umbrella app immediately:** Gives visible separation, but adds release and
  dependency overhead before the boundaries are proven.
- **Manual Mix app without Phoenix:** Avoids framework setup, but delays the
  required GraphQL/JSON API and Phoenix channel foundation.
- **Phoenix with LiveView/assets:** Faster to demo screens, but violates the
  project constraint that product UI is React, not LiveView.

### 2. Enforce modular monolith boundaries from the first code cut

Boundary should be configured as soon as the app exists. The first cut should
define public context modules under `lib/office_graph/<context>.ex`, internal
modules under `lib/office_graph/<context>/`, and entrypoints under
`lib/office_graph_web/`. The context map from
`design-code-organization-and-boundaries` remains the target, but the first
implementation may create only the modules needed by the walking skeleton plus
empty boundary stubs where useful for dependency direction.

Alternatives considered:

- **Flat Phoenix contexts first:** Faster, but would immediately erode the
  authorization, revision, ingestion, and graph ownership boundaries.
- **Separate libraries immediately:** Helps extraction later, but freezes APIs
  before the first real resource/action contracts exist.

### 3. Use Ash for normal domain actions and Ecto/Postgres for durable storage

Ash resources and domains should own normal create/update/state-transition
actions, validations, policies, and API-facing resource behavior. Ecto
migrations create the durable Postgres schema. Direct Ecto/SQL modules may be
introduced only for the approved paths: graph neighborhood reads,
authorization-filtered mixed projections, idempotency/replay scans,
operation-correlated history joins, and high-volume maintenance paths.

Alternatives considered:

- **Ecto schemas only:** Simpler initially, but loses the intended policy,
  validation, and API integration model.
- **Ash for everything including specialized SQL:** Keeps one abstraction, but
  forces traversal/replay/history paths through the wrong tool.

### 3a. Use Docker Compose for local Postgres

Development and test Postgres should run through Docker Compose, not through a
Nix-managed database process or an assumed host-local service. The first
implementation should add a checked-in Compose file with a named Postgres
service, stable local ports, durable named volume, health check, and documented
commands for start, stop, reset, and test database preparation. Application,
Mix, OpenSpec, and verification commands still run through the project Nix
shell; Compose owns only the local database process.

Alternatives considered:

- **Nix-managed Postgres process:** Keeps every tool under the flake, but makes
  database lifecycle less familiar and less portable for contributors already
  using Docker.
- **Assume a host-local Postgres service:** Avoids Compose files, but produces
  inconsistent local setup and hidden prerequisites.
- **Remote/shared development database:** Reduces local setup, but is wrong for
  repeatable tests, destructive resets, and offline development.

### 4. Implement a narrow schema with stable extension points

The first migrations should include only the records needed to prove the
walking skeleton and the minimum companion records required by the readiness
gate. The schema should still preserve stable identities and foreign keys so
later changes can extend rather than replace it:

- organizations, workspaces, initiatives, optional workstreams
- principals, profiles, sessions or session references, roles, capabilities,
  role assignments, policy bundle/version anchors, credential metadata
- graph items and typed graph relationships
- raw archives, external sources/references, normalized intake events,
  idempotency/replay identities
- signals, tasks, review findings, verification checks, evidence, artifacts
- rich text documents, current blocks, basic marks/references, derived plain
  text, and whole-document semantic revisions
- operation correlation, typed revisions, audit records, tombstones where
  mutable records require deletion semantics
- skeletal work packets, runs, run events, proposed graph changes, and
  verification results only where needed to prove readiness and traceability

Alternatives considered:

- **Maximal first schema:** Reduces future migrations, but blocks the first app
  behind unproven domains.
- **Only task/check/evidence tables:** Faster, but fails to prove the core
  enterprise constraints: identity, authorization, audit, revision,
  proposed-change safety, and ingestion replay.

### 5. Route manual intake through the future adapter shape

Manual pasted intake is the first adapter. It should create a raw archive,
normalized event, source/replay identity, operation correlation, and proposed
graph changes. Proposed changes then apply through authorized domain actions.
The adapter must not write graph truth tables directly.

Alternatives considered:

- **Manual form writes domain records directly:** Quicker, but bypasses the
  ingestion and proposed-change contracts that future providers need.
- **Wait for GitHub/Sentry webhook ingestion:** More realistic for engineering
  demos, but adds provider-specific complexity before the product loop exists.

### 6. Keep API entrypoints thin and shared

GraphQL and JSON API should expose the same walking-skeleton capabilities over
shared domain actions. Controllers and resolvers should authenticate a
principal/session context, build an operation context, call public domain
contracts, and return authorization-filtered results. API-specific code must
not duplicate mutations, policy decisions, or lifecycle transitions.

Alternatives considered:

- **GraphQL first, JSON API later:** Faster, but contradicts the project
  requirement that both APIs are required.
- **Separate API implementations:** Gives each surface flexibility, but risks
  divergent authorization and state behavior immediately.

### 7. Make verification a first-class implementation deliverable

The implementation must add repeatable commands for compile, format, tests,
Boundary checks, migrations/resource behavior, and OpenSpec validation. The
end-to-end scenario should be a testable executable flow, not only a manual
demo.

Alternatives considered:

- **Manual demo first:** Faster to show, but weak as a foundation for future
  design changes.
- **Broad CI pipeline first:** Useful later, but unnecessary before the first
  app and test commands exist.

## Risks / Trade-offs

- [Risk] The first slice still pulls in many enterprise concepts. -> Mitigation:
  implement only skeletal records and one happy-path-plus-policy test for each
  concept required by the readiness gate.
- [Risk] Boundary rules may slow early iteration. -> Mitigation: start with
  coarse boundaries and tighten exports as resources stabilize, while still
  preventing private-module lateral coupling from day one.
- [Risk] Dual GraphQL and JSON API surfaces duplicate work. -> Mitigation:
  expose a very small API surface and force both APIs through shared domain
  actions and shared authorization context.
- [Risk] Manual intake may look too artificial. -> Mitigation: model it through
  the exact archive, normalization, idempotency, and proposed-change path that
  later provider adapters will use.
- [Risk] Docker Compose adds a non-Nix local service prerequisite. -> Mitigation:
  keep the Compose contract narrow to Postgres, document exact commands, and
  continue running application and verification commands through the Nix shell.
- [Risk] Dependency setup may need network access for Hex packages and Phoenix
  generator archives. -> Mitigation: keep dependency choices explicit in
  `mix.exs`, run setup inside the Nix shell, and document any required
  network-backed setup commands in the implementation notes.

## Migration Plan

1. Generate the Phoenix API application in the repository root and commit the
   clean app baseline before adding domain behavior.
2. Add dependencies, configuration, formatter, Boundary setup, Docker Compose
   Postgres config, Ecto database config, and verification aliases.
3. Add migrations/resources in dependency order: identity/tenancy,
   operations, graph identity, content, intake/raw archive, domain loop,
   proposed changes, verification/evidence, revision/audit.
4. Add bootstrap seeds/commands for local development and controlled first
   organization/owner setup.
5. Add domain actions and tests for the walking-skeleton flow.
6. Add GraphQL and JSON API entrypoints over the same actions.
7. Run the full verification gate and update OpenSpec task state.

Rollback before production is simple because there is no shipped data yet:
revert the implementation commits or drop/reset the local development database.
After persistent data exists, normal Ecto migration rollback rules apply.

## Open Questions

- The first buyer, daily user, and flagship success metric remain product
  questions in the foundation change and do not block this backend skeleton.
- Exact Hex dependency versions should be selected during implementation based
  on currently compatible Phoenix, Ash, Absinthe, JSON API, Boundary, Ecto,
  Postgrex, and test package releases.
- The local Postgres startup path is fixed: use Docker Compose. Implementation
  should decide the exact Compose file name, service name, database names,
  credentials, and reset commands, then document them beside the app setup
  commands.
