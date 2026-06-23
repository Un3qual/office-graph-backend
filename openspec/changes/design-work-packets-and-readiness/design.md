## Context

Office Graph's foundation already names the core loop:
signal -> question -> decision -> work packet or execution package -> human or
agent run -> evidence -> verification -> reusable context.

The current specs define graph items, typed edges, proposed graph changes,
checks, evidence, approval gates, agent runtime entrypoints, authorized context
packages, API/realtime projection contracts, and operation context propagation.
What remains undefined is the layer that makes work executable: the work packet
and its readiness evaluation.

This design defines the contract that sits between planning/projection state
and execution. A work packet must be concrete enough for a human or agent to
act on, explainable enough for review and audit, and strict enough to prevent
agents from receiving ambiguous scope, unsafe authority, or stale context.

## Goals / Non-Goals

**Goals:**

- Define work packets as versioned execution contracts compiled from graph
  items, decisions, requirements, checks, evidence, artifacts, projections, and
  governance policy.
- Define readiness evaluation for human execution, agent execution,
  investigation-only handling, senior review, and human-only handling.
- Define how blockers such as open questions, missing decisions, missing
  context, unresolved approvals, unsafe autonomy, stale packets, or policy
  restrictions are represented.
- Define handoff boundaries to humans, agent runtime, future runs,
  verification, proposed graph changes, evidence candidates, API/realtime
  projections, and escalation flows.
- Preserve traceable version history when packets are compiled, invalidated,
  superseded, accepted for execution, or retired.

**Non-Goals:**

- Implement Ash resources, Ecto migrations, Phoenix APIs, Absinthe schema,
  JSON API routes, React UI, agent execution, run-event storage, or
  verification engines.
- Define the full run-event model. That remains owned by
  `design-runs-and-verification`.
- Replace graph items, proposed graph changes, approval gates, checks, or
  evidence with packet-specific copies.
- Make work packets authorization containers. They package authorized context
  and authority decisions, but do not grant access by themselves.
- Finalize every UI field or visual layout for work packet screens.

## Decisions

### 1. A Work Packet Is A Versioned Execution Contract

Work packets should be durable, versioned contracts that gather objective,
scope, compiled context, requirements, decisions, constraints, artifacts,
autonomy envelope, success criteria, verification checks, approval gates, and
escalation rules for a bounded unit of work.

Rationale: Delegation needs a stable contract. Humans and agents should know
what they are allowed to do, why the packet exists, what context is in scope,
what counts as completion, and what must happen when the packet is blocked.

Alternative considered: Treat a work packet as a task with extra text fields.
That would be easier to implement, but it would hide the authority, context,
verification, and staleness rules that make execution safe.

### 2. Packets Compile Context, They Do Not Own Truth

The packet should store references to source graph items, typed domain
records, projection inputs, relevant decisions, checks, evidence, artifacts,
external references, and context package metadata. It may store a compiled
snapshot for stable execution, but graph and domain records remain the source
of truth.

Rationale: A packet needs reproducible execution context, but copying graph
truth into packet-owned fields would create divergence. References plus a
compiled snapshot make the handoff explainable without turning packets into
parallel resource models.

Alternative considered: Use live graph queries only at execution time. That
avoids snapshots, but it makes it hard to prove what a human or agent was
asked to do when execution started.

### 3. Packet Versions Are Immutable After Execution Handoff

After a packet version is accepted for execution or attached to a run, that
version should remain immutable except for append-only status, audit,
supersession, and lifecycle metadata. Changed context should create a new
version or supersede the old packet version.

Rationale: Verification and audit need to know what objective, scope,
authority, and context were presented at handoff time.

Alternative considered: Mutate packet content in place. That is simpler for
editing, but it erases the execution contract that a run or human action relied
on.

### 4. Readiness Is An Explainable Evaluation, Not A Boolean

Readiness should produce a status plus reasons, missing inputs, required
actions, relevant graph links, approval state, autonomy safety, and freshness
information. Status should distinguish at least: not ready, blocked by
question, blocked by approval, needs senior review, investigation only,
human-ready, agent-ready, human-only, stale, and superseded.

Rationale: "Ready" is not one state. A packet can be safe for a senior human
but unsafe for an autonomous agent; it can be ready for investigation but not
for mutation; it can be blocked by one answer or by missing evidence.

Alternative considered: Store one `ready` boolean. That would make UI filters
easy, but it would hide the reasons that users, agents, and auditors need to
trust the handoff.

### 5. Agent-Ready Is Stricter Than Human-Ready

A packet may be human-ready while still not agent-ready. Agent-ready requires
explicit autonomy envelope, authorized context package, allowed scopes,
capabilities, tool and credential limits, approval requirements, data-control
posture, context-boundary rationale, and safe fallback/escalation behavior.

Rationale: Humans can ask clarifying questions and apply judgment across
ambiguous context. Agents need stricter boundaries because their authority and
tool use must be checked before execution.

Alternative considered: Treat human and agent readiness as the same status.
That would blur autonomy limits and encourage handing ambiguous work to agents.

### 6. Approval Gates Stay Governed Requirements

Work packets should reference approval gates and their state rather than
representing approvals as packet-local flags. Approval gates remain governed
requirements with approver eligibility, expiration, separation-of-duties, and
evidence or verification-check effects.

Rationale: Approval semantics are shared across packets, proposed graph
changes, context expansion, external writes, waivers, and verification. Packet
readiness should consume those semantics instead of forking them.

Alternative considered: Add packet-specific approval booleans. That would
fragment governance and make separation-of-duties checks inconsistent.

### 7. Handoffs Create References, Not Hidden Side Effects

Handing a packet to a human, internal agent, future run, proposed graph change,
or verification flow should create explicit references and operation context.
The packet handoff itself should not mutate graph truth except through approved
domain actions or proposed graph changes.

Rationale: Packet execution must use the same entrypoint, authorization,
revision, audit, operation-correlation, and proposed-change contracts as other
durable actions.

Alternative considered: Let a packet executor directly update linked tasks,
checks, or evidence. That bypasses the mutation safety model and makes agent
work harder to review.

### 8. Packet Projections Own Product Read Shapes

The work packet view should be a projection contract over packet version,
source graph context, readiness reasons, blockers, approval gates, context
package metadata, execution status, stale markers, and verification summary.
Realtime events should invalidate or update this projection, not replace
authoritative reads.

Rationale: Users need one coherent packet screen, but the data spans graph,
authorization, governance, agent runtime, verification, and future run state.
A projection contract prevents UI and API code from inferring business rules
from raw resource combinations.

Alternative considered: Let the frontend assemble work packet views from many
resource endpoints. That would scatter readiness and redaction logic across UI
code.

### 9. Packet Compilation Is A Domain Service Boundary

Packet compilation and readiness evaluation should live behind public domain
contracts. Future Ash resources may own durable packet/version records, while
projection compilation may use explicit Ecto/SQL where graph traversal and
read-model performance require it.

Rationale: Compilation coordinates graph, authorization, projection,
governance, and agent-runtime constraints. It should be callable from API,
workers, agents, and integration flows without duplicating logic.

Alternative considered: Compile packets inside controllers, resolvers, or UI
queries. That would repeat the same temporary-transport problem already
quarantined for API work.

## Risks / Trade-offs

- [Risk] Packet contracts become too broad and slow to implement. Mitigation:
  start with a minimal packet version that covers objective, scope, context,
  constraints, readiness, checks, and escalation, then add optional sections by
  capability.
- [Risk] Readiness rules become opaque. Mitigation: store reason codes,
  affected graph links, missing inputs, and policy references for every
  non-ready or downgraded status.
- [Risk] Compiled context leaks restricted data. Mitigation: compile through
  authorization-filtered projections, carry sensitivity labels, and scope
  snapshots to the authorized actor or policy context.
- [Risk] Packet snapshots go stale quickly. Mitigation: define invalidation
  sources, stale markers, recompilation paths, and supersession history.
- [Risk] Approval gates duplicate governance semantics. Mitigation: readiness
  consumes approval gate state and eligibility rules rather than reimplementing
  them locally.
- [Risk] Agent handoff outruns run/verification design. Mitigation: define
  references and handoff contracts now, leaving concrete run-event and final
  verification semantics to `design-runs-and-verification`.

## Migration Plan

1. Define the first durable packet/version resource shape in a later
   implementation plan.
2. Add packet compilation contracts that read authorized graph projections and
   typed domain records.
3. Add readiness evaluation with reason codes, status families, blockers,
   approval state, autonomy envelope checks, and stale context markers.
4. Add packet projection contracts for work packet context, blocker lists,
   readiness explanation, approval state, execution status, and realtime
   invalidation.
5. Connect packet handoff to agent runtime through explicit context package,
   authority, autonomy envelope, and operation context references.
6. Connect packet handoff to future run and verification contracts once
   `design-runs-and-verification` lands.
7. Retire or supersede packet versions when source graph context, decisions,
   checks, approvals, artifacts, or autonomy policy changes materially.

## Open Questions

- What is the first product flow that should create a real packet: PR review
  fix work, Sentry investigation, manual intake, or agent-generated follow-up?
- Should readiness results be materialized as durable records immediately, or
  recomputed from packet version plus source graph state until performance
  requires materialization?
- What exact status vocabulary should appear in product UI versus internal
  audit/debug views?
- Which packet sections are required for the MVP and which can be optional
  extensions?
- What stale-context events should trigger automatic packet invalidation versus
  only marking the packet as possibly stale?
