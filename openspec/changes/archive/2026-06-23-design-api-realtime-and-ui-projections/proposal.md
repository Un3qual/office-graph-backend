## Why

The walking skeleton proved equivalent GraphQL and JSON API behavior with
manual smoke endpoints, but that temporary transport shape must not become the
pattern for product APIs. Office Graph needs an explicit API, realtime, and UI
projection design before more frontend, projection, agent-runtime, or
integration work expands those manual endpoints.

## What Changes

- Define AshGraphql and AshJsonApi as the default implementation path for
  Ash-owned resource and action API exposure.
- Quarantine the current hand-written walking-skeleton GraphQL schema and JSON
  controller as temporary smoke-test transport code, not reusable product API
  architecture.
- Define when custom Absinthe/Phoenix transport code is allowed: only for thin
  orchestration commands, projection endpoints, transport-specific envelopes,
  or workflows that do not map cleanly to Ash resource/action APIs.
- Define modular GraphQL/API ownership so future schema growth is split by
  domain or capability instead of expanding one monolithic schema file.
- Define realtime delivery boundaries for Phoenix PubSub, Absinthe
  subscriptions, Channels, projection invalidation, and authorization-filtered
  event delivery.
- Define frontend-facing projection contracts for the first product surfaces:
  inbox, question queue, work packet context, focused node view, blocker view,
  review surface, evidence chain, agent runtime status, and verification view.
- Keep this change design-only. It does not implement Phoenix, Ash, GraphQL,
  JSON API, realtime, React, render-cache, or migration code.

## Capabilities

### New Capabilities

- `ash-api-surface`: GraphQL and JSON API ownership rules, AshGraphql/AshJsonApi
  default exposure, custom transport exceptions, schema modularity, and
  walking-skeleton API quarantine.
- `realtime-delivery`: PubSub, Absinthe subscription, Channel, projection
  invalidation, authorization filtering, and event delivery boundaries.
- `ui-projection-contracts`: frontend-facing projection contracts, render-cache
  posture, agent Markdown/rendered content boundaries, and API/realtime
  handoffs for initial product surfaces.

### Modified Capabilities

- None. The archived walking-skeleton API spec remains evidence for the smoke
  flow; this change adds the forward-looking product API architecture and
  cleanup guardrails.

## Impact

- Affects future GraphQL, JSON API, realtime, projection, frontend, generated
  Ash API, and walking-skeleton cleanup work.
- Consumes requirements from backend architecture, code organization,
  persistence, work graph, revision/audit/soft-delete, agent runtime,
  enterprise governance, and the archived walking-skeleton API surface.
- Creates no application code.
