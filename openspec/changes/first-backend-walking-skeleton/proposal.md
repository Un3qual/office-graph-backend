## Why

The design remediation gate has enough identity, authorization, persistence,
ingestion, proposed-change, revision/audit, and code-organization decisions to
start a first backend implementation safely. This change turns those decisions
into the smallest executable Phoenix/Ash/Postgres slice that proves Office
Graph's core work loop without pulling in the full future product surface.

## What Changes

- Generate the first Phoenix API backend application with Ecto/Postgres, Ash,
  Boundary enforcement, Absinthe GraphQL, JSON API support, and project
  verification commands.
- Add only the minimal contexts, schemas/resources, migrations, and domain
  actions needed for:
  `manual intake signal -> task -> review finding -> verification check ->
  evidence item -> verified completion`.
- Add first organization/owner bootstrap, authenticated principal/session
  context plumbing, one role assignment path, operation correlation, typed
  revision linkage, and a sensitive-action audit record for the walking
  skeleton.
- Add manual intake normalization through the same raw archive, idempotency,
  replay identity, adapter-output, proposed-change, and domain-action routing
  shape that later provider adapters will use.
- Expose a minimal shared API surface through GraphQL and JSON API over the
  same domain actions and authorization checks.
- Add focused tests and release gates for compile, formatting, Boundary rules,
  migrations/resource behavior, API smoke coverage, authorization filtering,
  OpenSpec validation, and the full walking-skeleton scenario.
- Do not add full agent runtime behavior, generic ordered-placement APIs,
  full rich text/editor infrastructure, complete work-packet/run systems,
  provider webhooks/API polling, polished UI, persisted projection read models,
  or broad department workflow packs.

## Capabilities

### New Capabilities

- `backend-app-baseline`: first Phoenix API app, dependency/config baseline,
  Boundary setup, context/module layout, and verification command surface.
- `walking-skeleton-persistence`: minimal Ash/Ecto resources, migrations, and
  seed/bootstrap records required by the first executable graph loop.
- `walking-skeleton-domain-loop`: domain actions and state transitions for
  manual intake through verified completion, including proposed-change safety.
- `walking-skeleton-api-surface`: minimal GraphQL and JSON API entrypoints that
  reuse the same domain actions, auth context, and authorization decisions.
- `walking-skeleton-verification`: tests, local fixtures, and release gates
  proving the app shell and end-to-end loop are ready for follow-on changes.

### Modified Capabilities

- None. No accepted specs exist under `openspec/specs/`; this change consumes
  active design changes without promoting or rewriting their canonical
  requirements.

## Impact

- Affects the repository root by adding the Phoenix API application structure,
  Elixir configuration, dependencies, migrations, Ash resources/domains,
  Boundary rules, tests, and project verification scripts.
- Affects OpenSpec planning by creating the first implementation change after
  the backend-readiness gate.
- Requires the project Nix flake for Elixir, Erlang, Node, OpenSpec, and all
  project CLI/runtime verification.
- Does not create frontend React screens, production deployment automation,
  provider-specific integrations, or full agent runtime execution.
