## Why

Office Graph has already established that delegated work should flow through
versioned work packets, but the exact packet contract and readiness rules are
still undefined. This blocks reliable handoff to humans, internal agents, runs,
verification, and product UI surfaces.

## What Changes

- Define work packets as versioned execution packages with objective, scoped
  context, requirements, decisions, constraints, artifacts, autonomy envelope,
  success criteria, verification checks, approval gates, and escalation rules.
- Define readiness evaluation for human execution, agent execution,
  investigation-only work, senior-review-needed work, and human-only work.
- Define how questions, missing decisions, missing evidence, stale context,
  unresolved approvals, unsafe autonomy, and policy restrictions block or
  downgrade readiness.
- Define how execution packages are compiled from graph projections and typed
  records, invalidated when source context changes, and superseded with
  traceable version history.
- Define handoff contracts from work packets to agent runtime, human assignees,
  change proposals, future runs, future verification, and API/realtime UI
  projections.
- Keep this change design-only. It does not implement Ash resources, Ecto
  migrations, Phoenix APIs, GraphQL/JSON surfaces, agent execution, run-event
  storage, verification engines, or frontend UI.

## Capabilities

### New Capabilities

- `work-packet-contracts`: versioned work packet shape, lifecycle, ownership,
  source graph links, compiled context, constraints, success criteria,
  verification references, and supersession rules.
- `readiness-evaluation`: readiness status, blocker detection, required
  questions/decisions, context completeness, approval gate state, autonomy
  safety, stale context handling, and human/agent execution eligibility.
- `execution-package-handoffs`: contracts for handing packets to humans,
  internal agents, future run records, change proposals, evidence
  candidates, approval flows, context expansion, and escalation paths.
- `work-packet-projections`: packet-specific projection, API/realtime, and UI
  contract requirements for work packet context, readiness explanations,
  stale markers, blockers, approvals, and execution status.

### Modified Capabilities

- None. Existing graph, verification, agent runtime, governance,
  change-proposal, API/realtime, and persistence specs remain source
  constraints; this change adds the missing packet/readiness layer that those
  changes reference.

## Impact

- Affects future work packet resources, readiness evaluators, graph projection
  contracts, approval/escalation flows, agent runtime delegation, run creation,
  verification setup, and work packet UI/API surfaces.
- Consumes requirements from work graph, verification, agent runtime, enterprise
  governance, change proposals, code organization, persistence, and
  API/realtime projection design.
- Creates no application code.
