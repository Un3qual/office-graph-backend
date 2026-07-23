## Context

AgentRuntime is currently an empty Boundary module. The repo already has
authorized projections, operations, durable jobs/events, work runs, proposals,
evidence candidates, audit/revision traces, and typed relationships. The runtime
must orchestrate those owners rather than become an alternate graph or policy
engine.

This change depends on the typed relationship change and the generic
system-operation contract delivered by the GitHub change. Human identity and
governance administration remains deferred; backend-only agent principals and
credential metadata are allowed.

## Goals / Non-Goals

**Goals:**

- Execute run-linked agents through explicit invocation and immutable authority
  snapshots.
- Assemble explainable authorized context packages.
- Supervise model/tool work durably with retries, cancellation, and recovery.
- Route structured output to proposals and evidence candidates only.
- Persist approval/context-expansion requests and run-aware conversations.
- Deliver one deterministic OpenSpec/spec-review agent and focused operator UI.

**Non-Goals:**

- No direct graph/business mutation or external write authority.
- No verification completion from agent output.
- No general chat product, agent marketplace, workflow builder, or agent-admin
  UI.
- No hosted model vendor requirement in the normal verification gate.
- No human login, SSO/SCIM, role administration, or governance settings.

## Decisions

### 1. AgentRuntime orchestrates owning domains

AgentRuntime owns definitions, executions, context packages, model/tool
requests, approvals, and expansion requests. It calls public WorkGraph,
ProposedChanges, Runs, Verification, Authorization, Operations,
DurableDelivery, Audit, and Revisions contracts for their records.

Putting runtime inside WorkGraph or Runs was rejected because it would couple
model/tool supervision to graph or run persistence. Direct resolver/worker
access to model and tools was rejected because it fragments policy and audit.

### 2. Every MVP execution is run-linked

Invocation records mode, origin, selected graph item, run, organization,
workspace, agent principal, delegator/trigger basis, requested capabilities,
autonomy envelope, and operation. An immutable authority snapshot records the
effective intersection of the definition request and delegator grants, and the
exact model-adapter key/version used for the execution. Automatic invocation
accepts only the canonical binding/run trigger authority, while an exact
persisted invocation replay remains readable after later lifecycle changes.
Schema upgrades that add fields to the canonical snapshot hash rehash existing
rows in the same migration and restore the prior hash form on rollback.

Run-less general conversation was rejected for the first implementation because
the accepted surface is a run-aware operator tool and verification must retain
parent context.

### 3. Context packages are immutable authorized references

Projection contracts assemble selected and neighboring graph items, typed
records, external references, decisions/checks/evidence, and recent run context.
Each entry records included, redacted, omitted, restricted, or expansion-required
posture, a safe rationale, and the selected source version. Raw payload slices
require policy approval.

Allowing agents to traverse graph tables on demand was rejected because it can
self-expand access and cannot explain the prompt boundary.

### 4. Model and tool adapters have typed manifests

Model adapters accept a provider-neutral request and return validated structured
output or classified error. Tool manifests declare input/output schemas,
capabilities, credentials, sensitivity, external-write posture, timeout, budget,
and output classification. The worker validates both pre-gate input authority
and successful output against the selected manifest, so an impossible request
cannot create a durable gate and globally well-formed but adapter-disallowed
output cannot reach routing.

Ad hoc prompt function calls and direct provider SDK exposure were rejected
because they make permission and credential enforcement opaque.

### 5. The first runtime is proposal-first

Model output is untrusted. Agent suggestions route to existing proposal commands;
verification material routes to evidence-candidate commands. No initial adapter
can call a direct business mutation or external write. Output routing checks
the definition allowlist, the invocation's immutable capability snapshot, and
the exact step operation's snapshot, execution causation, and idempotency scope
before calling an owning domain.

Read-only output alone was rejected as too weak, while direct writes were
rejected as a bypass around validation, audit, and approval.

### 6. Durable steps use explicit states and idempotency

Executions move through queued, running, waiting approval, waiting context,
retry scheduled, completed, failed, or cancelled. Oban jobs use execution and
step identities, leases, bounded attempts, and classified retry/terminal
results. Step completion records before dispatching the next step.
Storage-availability failures retain their retryable classification through
output validation instead of being collapsed into terminal authorization
failure.
Cancellation replays reissue the adapter's idempotent cancellation signal when
the persisted request still identifies an adapter operation that may remain
active.

A single long-running process was rejected because restart and retry would lose
or duplicate product effects.

### 7. Approvals and context expansion are durable requests

Requests identify execution, step, requested action/context, reason, scope,
capabilities, sensitivity, expiry, and operation. Narrow GraphQL/JSON commands
authorize resolve/deny/cancel and resume only the matching waiting step. When a
step crosses multiple gates, the later request retains the prior approved gate
lineage so every grant in every immutable successor context package remains
revalidated until adapter dispatch.

Implicit approval through conversation membership was rejected because it
cannot express tool, credential, external-write, or cross-scope authority.

### 8. Conversations are node-scoped, run-aware records

Conversation and message resources retain graph item, run, execution, author or
source, visibility, operation, and contribution provenance. The operator route
adds one focused conversation/approval panel. Messages that suggest durable work
create proposals or evidence candidates rather than hidden side effects.
Human conversation writes use a dedicated owner capability, validate the exact
command input digest, and prove that the selected graph item belongs to the
run's packet-source contract. Proposal and domain-operation links are separately
scope checked. The read projection is bounded, redacts context packages that do
not independently match the reader's tenant/run/graph scope, and exposes only
safe execution and gate-request metadata needed by the focused operator panel.

### 9. Retention defaults to typed metadata

Store hashes, adapter/model family, classifications, references, safe summaries,
accepted structured output, and failure codes. Full prompts, responses, tool
payloads, and secrets require a separate policy-approved raw archive path.

Always retaining raw model/tool traffic was rejected for sensitivity and cost;
retaining only logs was rejected because product provenance would disappear.

### 10. The first automatic agent reviews OpenSpec artifacts

Install one migration-owned definition for read-only repository/OpenSpec tools,
graph context, findings, proposals, checks, and evidence candidates. An
authorized backend command binds it to an organization. GitHub tools remain
optional after the integration change and do not shape core runtime schemas.

## Risks / Trade-offs

- Runtime scope can become a general automation platform → enforce the
  proposal-first and no-external-write contracts in adapter conformance tests.
- Authority can change mid-run → snapshot start authority and revalidate mutable
  principals, credentials, grants, and approvals before each step.
- Durable retries can duplicate model/tool effects → use step identities,
  leases, completion records, and adapter idempotency contracts.
- Context packages can leak restricted data → assemble through projections,
  persist rationale, and test redaction/cross-tenant cases.
- Deterministic adapters can hide production behavior → keep adapter contracts
  strict and hosted adapters replaceable, with optional smoke tests later.
- Operator UI can grow into chat/admin scope → keep it run-scoped and expose only
  invocation, messages, approvals, expansion, cancellation, and status.

## Migration Plan

1. Add agent definition/binding, execution, authority snapshot, context package,
   request, conversation, and message resources with no workers enabled.
2. Add deterministic adapters and adapter conformance suites.
3. Add invocation, context assembly, durable step orchestration, cancellation,
   retry, and recovery.
4. Add proposal/evidence routing, approvals, expansion, and realtime projections.
5. Install and bind the OpenSpec review agent and add the focused operator UI.

When adapter lineage is added to pre-existing authority snapshots, recompute
their canonical hashes after the backfill and recompute the legacy form before
removing those fields on rollback.

Rollback disables invocation/workers first, waits for active steps or marks them
cancelled with provenance, retains execution/conversation history while API
surfaces are removed, and drops tables only when no run, proposal, evidence,
audit, or revision references depend on them.

## Open Questions

None. Hosted model selection, human identity/governance, generic agent
administration, and external-write tools are explicit future changes.
