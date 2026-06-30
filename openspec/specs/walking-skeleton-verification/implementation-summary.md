# Implementation Summary

## backend-app-baseline

- Generated a Phoenix API application at the repository root with
  `OfficeGraph` and `OfficeGraphWeb`.
- Configured Postgres through Docker Compose on `localhost:55432`.
- Added Phoenix/Ecto/Postgres, Ash, Boundary, Absinthe, and JSON API support
  dependencies inside the Nix-shell workflow.

## walking-skeleton-persistence

- Added identity, tenancy, authorization, operation correlation, revision,
  audit, tombstone, graph, raw archive, intake, proposed-change, content,
  work-packet, run, and verification persistence.
- Added graph-backed resources for the executable loop:
  signal, task, review finding, verification check, evidence item, artifact,
  and verification result.
- Preserved graph identity plus typed resource creation in one transaction for
  graph-backed resources.

## walking-skeleton-domain-loop

- Added local owner bootstrap with organization, workspace, initiative,
  principal/profile, role assignment, capabilities, policy bundle, and session
  context.
- Routed manual intake through raw archive, normalized event, replay identity,
  duplicate handling, and proposed graph changes.
- Added proposed-change validation, authorization, rejection, and application.
- Implemented the executable loop from manual intake through verified
  completion with audit and revision traceability.

## walking-skeleton-api-surface

- Added a thin shared `OfficeGraph.ApiSupport` facade for API entrypoints, with
  local owner bootstrap explicitly gated to dev/test configuration until real
  authenticated API session plumbing lands.
- Minimal GraphQL mutations cover manual intake, proposed-change apply, and
  verification completion.
- Matching JSON routes expose the same operations.
- API smoke coverage proves GraphQL and JSON drive equivalent durable
  state and duplicate replay behavior.

## walking-skeleton-verification

- Added Boundary compiler enforcement and a `mix boundary.check` alias.
- Added focused tests for bootstrap/idempotency, authorization, graph identity,
  raw intake replay, proposed-change rejection, API smoke behavior, and the full
  walking-skeleton flow.
- Added `bin/verify-backend` for Docker Compose Postgres startup, database
  readiness, compile, format, Boundary, tests, and OpenSpec validation from
  inside the Nix development shell.

## Architecture Evidence Matrix

| Requirement | Evidence | Gate |
| --- | --- | --- |
| Phoenix API baseline | `lib/office_graph_web`, `config/*.exs`, `mix.exs` | `mix compile --warnings-as-errors` |
| Boundary context layout | `lib/office_graph/*.ex`, Boundary declarations | `mix boundary.check` |
| Stable WorkGraph resources are Ash-backed, all table-backed resources have Ash owners, and planned MVP graph/software-proving/rich-text resources remain tracked separately from implemented tables | `OfficeGraph.*.Domain`, canonical Ash resource modules for all 40 migration-created tables, `openspec/specs/backend-model-ownership/model-inventory.md` | `mix architecture.conformance` |
| WorkGraph Ash actions are authorization-aware | `OfficeGraph.Authorization.Checks.HasCapability`, WorkGraph resource policies | `test/office_graph/architecture/ash_conformance_test.exs` |
| Graph identity plus typed resource creation is atomic | `OfficeGraph.WorkGraph` transaction boundary with Ash-backed graph identity, relationship, and typed resource creates | `test/office_graph/work_graph/persistence_test.exs` |
| Stable product mutations route through Ash or approved exceptions | `OfficeGraph.WorkGraph` Ash create/update helpers, `architecture-exceptions.md` | `mix architecture.conformance` |
| Direct Ecto paths are approved and documented | `openspec/specs/backend-model-ownership/architecture-exceptions.md` | `test/office_graph/architecture/ash_conformance_test.exs` |
| Architecture gate is part of backend verification | `mix.exs`, `bin/verify-backend` | `./bin/verify-backend` |
| GraphQL and JSON use shared actions with gated local bootstrap | `OfficeGraph.ApiSupport`, `OfficeGraphWeb.GraphQL.*`, `OfficeGraphWeb.JsonApi.Compatibility.Controller` | `test/office_graph_web/api_smoke_test.exs` |
| OpenSpec remains valid and mapped to evidence | `openspec/specs/backend-app-baseline/spec.md`, `openspec/specs/walking-skeleton-*/spec.md`, and active changes | `openspec validate --specs --strict`; `openspec validate --changes --strict` |

## Scope Guard

This implementation does not add a React frontend, LiveView UI, provider
webhooks or polling, a full agent runtime, a generic ordered-placement
framework, or full collaborative rich text editor behavior.
