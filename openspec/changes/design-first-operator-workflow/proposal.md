## Why

The backend walking skeleton proves the durable loop, but Office Graph still
needs a first operator-facing workflow that turns that loop into a coherent
product slice. The next change should make manual intake, triage, packet
readiness, handoff, evidence, and verification usable together without starting
ordering, rich text/editor, full agent runtime, provider webhook, or frontend
replacement work.

## What Changes

- Define the first operator workflow from manual intake through inbox triage,
  readiness review, work-packet handoff, evidence capture, and verification.
- Define operator-facing projections for the narrow MVP surfaces: inbox,
  question/readiness queue, work packet detail, run/evidence state, and
  verification outcome.
- Define which backend/API behavior must become production-shaped versus which
  walking-skeleton shortcuts remain local or test-only.
- Define how this slice reuses existing graph, intake, packet, run,
  readiness, evidence, authorization, audit, and revision primitives.
- Explicitly defer React polish, generic ordering, full graph canvas, provider
  webhooks or polling, full agent runtime, unrestricted coding-agent behavior,
  collaborative rich text, mobile, and broad workflow-builder behavior.

## Capabilities

### New Capabilities

- `operator-workflow`: Defines the first usable operator loop across manual
  intake, triage, readiness, packet handoff, evidence linking, and verified
  completion.

### Modified Capabilities

- None. Existing durable capabilities provide the primitives; this change adds
  the first product workflow contract over them without changing their base
  requirements.

## Impact

- Affects future implementation of backend APIs, GraphQL/JSON reads and
  mutations, projection queries, authorization checks, tests, and likely the
  first React product screens.
- Uses the existing Phoenix API, Ash, Boundary, Postgres, GraphQL, JSON API,
  operation correlation, revisions, audit, work packets, runs, verification,
  and manual intake foundations.
- Does not require new infrastructure dependencies, background job systems,
  provider-specific integrations, generic ordered placement, or a full agent
  runtime.
