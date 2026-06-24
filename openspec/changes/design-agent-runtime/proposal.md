## Why

Office Graph has locked the product direction around a graph-aware internal
agent runtime, but the executable runtime contract is still only described as
handoffs from graph, governance, persistence, and boundary planning. This
change defines that runtime before work packet, run, verification, API,
realtime, and frontend designs depend on implicit agent behavior.

## What Changes

- Define the internal agent runtime as the managed environment for embedded
  node agents, automatic review agents, proposal-only graph actions, and
  approved tool actions.
- Define how the runtime receives authorized graph context packages, preserves
  projection rationale, handles missing or restricted context, and requests
  context expansion instead of bypassing policy.
- Define the boundary between model output, supervising runtime logic, tool
  execution, durable domain actions, and change proposals.
- Define how agent activity carries operation context, agent/delegator or
  trigger authority, autonomy envelope, tool or integration scope, provenance,
  and audit/revision hooks.
- Define the runtime handoff points to future work packet, run, verification,
  API/realtime, and UI-projection changes without implementing those surfaces
  in this change.
- Keep the first scope bounded to graph-aware conversations, automatic
  review-style agents, change proposals, and approved tool actions. This change
  does not introduce unrestricted coding-agent authority or a generic workflow
  automation platform.

## Capabilities

### New Capabilities

- `agent-runtime`: embedded and automatic agent runtime behavior, context
  packages, authority inputs, model/tool separation, approved tool execution,
  mutation boundaries, provenance, and handoff contracts to runs, work packets,
  verification, and API/realtime projections.

### Modified Capabilities

- None. Existing archived specs cover the backend baseline, model ownership,
  and walking-skeleton behavior; this change adds a new runtime capability
  instead of changing those accepted requirements.

## Impact

- Affects OpenSpec planning for the future agent-runtime implementation.
- Consumes constraints from work graph node conversations and projections,
  enterprise governance, identity/credential design, change proposals,
  revision/audit/operation correlation, persistence, and code organization.
- Constrains later work packet, run, verification, API/realtime, frontend,
  Oban/job, and tool-adapter designs.
- Creates no Phoenix, Ash, Ecto, GraphQL, JSON API, React, Oban, model
  provider, tool execution, migration, or runtime code.
