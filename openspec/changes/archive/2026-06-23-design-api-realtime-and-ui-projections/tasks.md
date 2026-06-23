## 1. Direction Lock

- [x] 1.1 Confirm the current hand-written walking-skeleton GraphQL schema,
  JSON controller, serializer, and API support module are temporary smoke-test
  transport code.
- [x] 1.2 Confirm AshGraphql and AshJsonApi are the default path for
  Ash-owned resource and action API surfaces.
- [x] 1.3 Confirm custom Absinthe and Phoenix transport code is allowed only
  for documented orchestration, projection, integration, export, webhook, or
  transport-envelope exceptions.
- [x] 1.4 Confirm future GraphQL schema growth is modular and root-composed
  rather than concentrated in one manually maintained schema file.
- [x] 1.5 Confirm UI projections, realtime events, and render caches are
  designed together with authorization, redaction, sensitivity, audit
  visibility, and staleness behavior.

## 2. Capability Specs

- [x] 2.1 Add `ash-api-surface` requirements for AshGraphql/AshJsonApi
  defaults, walking-skeleton quarantine, custom transport exceptions, modular
  GraphQL ownership, and JSON API package use.
- [x] 2.2 Add `realtime-delivery` requirements for domain/projection events,
  authorization-filtered delivery, explicit topic ownership, and projection
  hint payloads.
- [x] 2.3 Add `ui-projection-contracts` requirements for product projection
  contracts, derived render caches, agent Markdown boundaries, and shared
  API/realtime contracts.

## 3. Design Artifacts

- [x] 3.1 Write the proposal defining the API, realtime, and UI projection
  scope.
- [x] 3.2 Write the design decisions for Ash package defaults, manual API
  quarantine, custom transport exceptions, modular GraphQL composition,
  projection contracts, realtime delivery, and render-cache policy.
- [x] 3.3 Capture follow-on implementation questions for first API migration
  target, GraphQL composition pattern, first projection, first realtime
  transport, and JSON API custom exceptions.
- [x] 3.4 Update related OpenSpec handoff tasks after this change validates.

## 4. Validation

- [x] 4.1 Run `openspec status --change design-api-realtime-and-ui-projections`.
- [x] 4.2 Run `openspec validate design-api-realtime-and-ui-projections --strict`.
- [x] 4.3 Run `openspec validate --changes --strict`.
