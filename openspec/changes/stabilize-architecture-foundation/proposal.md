## Why

Office Graph has drifted from its accepted architecture: the backend specs
require Ash-owned GraphQL/JSON API surfaces, modular bounded contexts, and
typed domain actions, while implementation has accumulated hand-written
transport code, oversized orchestration modules, frontend growth without a
foundation, and too many product nouns leaking into API/UI contracts.

This change stops feature expansion long enough to define the remediation
plan, gates, and sequencing needed to make future work build on the intended
architecture instead of normalizing the current walking-skeleton shortcuts.

## What Changes

- Define an architecture stabilization roadmap for API, domain, frontend, and
  product vocabulary remediation before the next large product feature.
- Require the current manual GraphQL/JSON API code to be treated as a
  compatibility layer with explicit exceptions, retirement conditions, and
  generated Ash API migration milestones.
- Require domain/resource cleanup to burn down direct Ecto and `authorize?:
  false` exceptions through public Ash/domain commands rather than expanding
  transport-adjacent orchestration modules.
- Define a frontend architecture foundation covering design tokens,
  components, routing, state management, data fetching, generated API types,
  testing, and feature boundaries before additional product screens are added.
- Establish canonical MVP product vocabulary so operator-facing APIs and UI
  expose a smaller spine: Signal, Change Proposal, Work Item, Work Packet, Run,
  Check, Evidence, and Verification.
- Preserve enterprise requirements as backend guardrails while deferring broad
  UI/API exposure for SCIM, rich text quote models, explicit grants, agent
  execution internals, and other non-spine concepts until a workflow requires
  them.
- Add verification gates that prevent new manual API surfaces, new frontend
  feature sprawl, or new direct database exceptions without an accepted
  exception and retirement condition.
- No production behavior is implemented by this change. It creates the plan and
  spec deltas that implementation changes must follow.

## Capabilities

### New Capabilities

- `architecture-stabilization`: Defines the cross-cutting remediation roadmap,
  sequencing, exception burn-down, and verification gates for stabilizing the
  current codebase before feature expansion.
- `frontend-architecture`: Defines the React product UI foundation for design
  system, routing, state management, data fetching, API typing, testing, and
  feature module boundaries.
- `product-concept-simplification`: Defines canonical MVP product vocabulary
  and separates user-facing concepts from backend infrastructure concepts.

### Modified Capabilities

- `ash-api-surface`: Add requirements for migration milestones from manual
  GraphQL/JSON endpoints to AshGraphql/AshJsonApi, including documented custom
  command/projection exceptions.
- `ash-domain-boundaries`: Add requirements for moving lifecycle,
  authorization, validation, operation correlation, and orchestration behavior
  out of transport-adjacent helpers and into owning Ash/domain commands.
- `backend-model-ownership`: Add requirements for treating the architecture
  exception ledger as a burn-down list with gates for new direct Ecto or
  `authorize?: false` paths.
- `ui-projection-contracts`: Add requirements that frontend screens consume
  explicit projection contracts and avoid inferring business semantics from raw
  backend/infrastructure records.

## Impact

- Affected planning artifacts: OpenSpec specs for API surface, domain
  boundaries, model ownership, UI projections, frontend architecture, concept
  simplification, and stabilization gates.
- Affected future code: `lib/office_graph_web/schema.ex`,
  `lib/office_graph_web/controllers/*`, serializers, `OfficeGraph.ApiSupport`,
  `OfficeGraph.WorkGraph`, `OfficeGraph.WorkPackets`, `OfficeGraph.Runs`,
  `OfficeGraph.Verification`, resource/domain modules, architecture tests, and
  `assets/src/**`.
- Affected APIs: future GraphQL and JSON API surfaces must prefer AshGraphql
  and AshJsonApi for resource operations, with custom transport code limited to
  documented command/projection exceptions.
- Affected frontend: future UI changes must first establish component, routing,
  state/data, and API typing conventions instead of extending the single
  operator console component shape.
- Verification: OpenSpec validation, architecture conformance, API parity
  tests, frontend verification, and new guard tests for manual endpoint and
  exception growth.
