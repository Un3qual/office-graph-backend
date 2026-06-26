## Context

Office Graph is aiming for a company-wide, agent-native work graph where
humans and agents act on the same graph, decisions, evidence, and governance
rules. The walking skeleton now proves manual intake, change proposals,
authorization checks, graph-backed records, and verification evidence, but it
does not yet define how internal agents enter the system, receive context, use
tools, or produce durable outputs.

Several accepted or active planning tracks already constrain the runtime:

- Work graph planning owns addressable graph items, node conversations,
  projection context, and conversation-driven change proposals.
- Enterprise governance owns cross-scope agent authority, context expansion,
  temporary grants, approval gates, AI data controls, and separation of duties.
- Identity and authorization planning owns human, service account, webhook,
  integration, internal-agent, and external-executor principal and credential
  records.
- Change proposals own validation, authorization, approval, and
  application of agent-suggested mutations.
- Revision, audit, and code-organization planning own operation correlation,
  audit/revision separation, thin entrypoints, Boundary rules, and shared
  domain contracts.

The runtime should therefore be an orchestrating domain, not a replacement for
those domains. Its job is to assemble an authorized execution context, supervise
model and tool steps, enforce authority boundaries, and hand outputs to the
owning domain contracts.

## Goals / Non-Goals

**Goals:**

- Define the first internal agent runtime scope: embedded node agents,
  automatic review-style agents, proposal-only graph actions, and approved tool
  actions.
- Keep agent work graph-aware by making selected graph items, projection
  rationale, context boundaries, provenance, and operation context explicit.
- Prevent agents from silently gaining user-equivalent authority, hidden graph
  mutation paths, unrestricted tool access, or untracked cross-scope context.
- Create clear contracts to future work packet, run, verification, API/realtime,
  UI-projection, and tool-adapter designs.
- Preserve a future extraction path for the runtime as a library-ready bounded
  context.

**Non-Goals:**

- No unrestricted coding-agent authority, IDE replacement, generic workflow
  automation platform, or department-pack marketplace in this change.
- No implementation of model provider adapters, tool execution workers,
  migrations, Oban jobs, frontend UI, GraphQL, JSON API, or realtime channels.
- No final run-event, work-packet, verification, conversation-storage, or
  model-payload retention schema. Those remain owned by companion changes.
- No policy shortcut that lets conversation membership, graph edges, or user
  delegation alone grant tool, mutation, credential, or cross-scope access.

## Decisions

### AgentRuntime is an orchestrating bounded context

The future implementation should introduce an `OfficeGraph.AgentRuntime`
bounded context that accepts explicit invocation envelopes and calls public
domain APIs for graph context, authorization, change proposals, operation
correlation, credentials, tools, runs, and verification. It should not own the
canonical records for work packets, runs, change proposals, graph items,
audit records, revisions, credentials, or policy facts.

Rationale: the runtime needs to coordinate many domains, but making it the
owner of their durable records would create a central bypass around the product
boundaries the backend architecture is trying to protect.

Alternatives considered:

- Put runtime logic inside WorkGraph. This keeps graph access close, but it
  overloads WorkGraph with model/tool supervision and authority decisions.
- Put runtime logic inside Runs. This treats every agent interaction as a run
  too early and makes embedded conversations depend on a later execution model.
- Let API entrypoints call model/tool code directly. This is simple for demos,
  but it splits policy, provenance, and mutation rules across transports.

### Runtime entry starts from invocation envelopes

Each internal agent start should use an invocation envelope that records mode,
origin, selected graph item or trigger, organization, scope, principal,
delegator or trigger authority, requested capabilities, autonomy envelope, and
initial operation context. The first modes should be:

- `embedded_conversation`: a node-scoped assistant attached to an addressable
  graph item or conversation.
- `automatic_review`: an agent attached to a graph event, signal, check,
  policy trigger, or completion event.
- `delegated_task`: a user-directed agent request with explicit outcome,
  scope, and allowed action mode.
- `tool_action`: a supervised tool execution step inside an existing agent
  invocation.

Rationale: mode-specific entry makes authority review and audit understandable.
It also lets future UI, API, worker, and trigger surfaces share one runtime
contract.

Alternatives considered:

- A single generic "run agent" command. This is flexible, but it hides whether
  the request is conversational, automatic, delegated, or tool-specific.
- Separate bespoke entrypoints per feature. This would be easy at first but
  would fragment authorization, context assembly, and provenance.

### Context packages come from authorized projections

The runtime should receive context packages from graph/projection domain
contracts rather than directly walking graph tables. A context package should
include the selected item or trigger, authorized neighboring graph items,
related typed records, rich text anchors, external references, raw archive
references or approved payload slices, relevant decisions/checks/evidence,
recent run references when available, and rationale for why each piece is
included or restricted.

Restricted context should be omitted, redacted, summarized, represented as a
placeholder, or converted into a context expansion request. The runtime should
preserve enough rationale for an agent, reviewer, or auditor to understand
context boundaries when policy permits disclosure.

Rationale: agent context is a product-critical projection, not an internal
convenience read. Treating it as an authorized projection keeps agents aligned
with the same visibility model as humans and APIs.

Alternatives considered:

- Let agents retrieve graph neighbors on demand. This risks accidental access
  expansion and makes audit explanations weaker.
- Preload large raw archives or provider payloads into prompts. This increases
  leakage, cost, and retention risk; agents should receive typed references,
  summaries, or approved payload slices instead.

### Authority is computed before model and tool steps

Before model or tool execution, the runtime should compute an effective agent
authority from the intersection of delegator permission when present, agent
principal capability, trigger or integration authority, autonomy envelope, tool
or credential scope, organization policy, target scope, sensitivity labels, and
temporary grants. Missing authority should produce denial, approval request,
context expansion request, or proposal-only behavior.

Rationale: internal agents are first-class actors, but they must not inherit
unbounded user authority. The runtime needs a stable authority snapshot so
model output and tool calls cannot change the execution boundary mid-flight.

Alternatives considered:

- Trust the delegating user's permissions. This fails for automatic agents,
  service-account activity, tool use, external writes, and separation of duties.
- Evaluate permissions only when applying changes. This is too late for context
  access, credential use, prompt assembly, tool execution, and external actions.

### Models produce untrusted structured output

Model output should be treated as untrusted structured output until the runtime
validates it and routes it to an owning domain. Smaller or specialized models
may produce findings, summaries, suggested edges, proposed tasks, evidence
candidates, or proposed mutations, but supervising runtime logic owns
classification, validation, and next-step routing.

Rationale: this keeps model behavior useful without granting direct graph or
tool authority to every model call.

Alternatives considered:

- Allow models to call tools and write state directly. This is too risky for an
  enterprise work graph with audit, credential, and authorization requirements.
- Treat model outputs as chat only. This preserves safety but misses the point
  of graph-native agents that can create structured, reviewable work.

### Tools are adapters with explicit manifests and policy checks

Tool execution should go through runtime-managed adapters with declared
capabilities, input/output shapes, credential needs, sensitivity posture,
external-write behavior, timeout/budget limits, and audit requirements. A tool
call should receive an operation context and return classified output:
observation, raw payload, evidence candidate, change-proposal input, external
action result, or error.

Rationale: tool manifests give authorization and governance something concrete
to evaluate, and classified outputs keep raw external data from becoming graph
truth accidentally.

Alternatives considered:

- Use ad hoc function calls from agent prompts. This is fast for prototypes but
  makes tool permissions, credential scope, and audit behavior opaque.
- Expose provider SDKs directly to agents. This increases blast radius and
  couples prompts to provider-specific behavior.

### Durable mutations use change proposals or domain actions

Agent-driven graph or domain mutations should route through proposed graph
changes by default. Direct accepted domain actions are allowed only when the
agent has explicit authority for that action and the same validation,
authorization, revision, audit, and operation-correlation contracts apply as
human and integration entrypoints.

The MVP posture should be proposal-first: embedded and automatic agents can
draft, explain, and package mutations, while sensitive, destructive,
cross-scope, credential-backed, external-write, or high-risk lifecycle actions
require approval gates.

Rationale: change proposals preserve safety without making agents read-only.
They also give humans and future review agents an inspectable object to
approve, reject, amend, or apply.

Alternatives considered:

- Make all agent output read-only. This is safe but undercuts work delegation.
- Let approved agents write directly to graph tables. This bypasses the
  change-proposal, revision, audit, and policy contracts.

### Runtime provenance is a first-class output

Runtime steps should preserve provenance for agent messages, findings, change
proposals, tool calls, external actions, evidence candidates, errors,
approvals, and accepted domain actions. Provenance should include agent principal,
delegator or trigger authority, selected graph item or trigger, context package
reference, operation context, tool or model family when policy permits, time,
visibility context, and failure or retry status when applicable.

Rationale: Office Graph's differentiation depends on proof and reusable
organizational context. Agent work that cannot be traced is not product-grade
work.

Alternatives considered:

- Keep detailed provenance only in logs. Logs are not enough for product
  review, audit, verification, or future graph context reuse.
- Store full prompts and tool payloads everywhere. This overexposes sensitive
  context and conflicts with AI data-control and retention requirements.

### Runtime state is projected, not exposed as raw internals

Future APIs and UI should expose agent runtime state through projection-ready
status and provenance fields: what the agent can see, what it can do, what it
has done, what is blocked, what needs approval, what failed, and what context
was restricted. Internal prompts, raw tool payloads, secret material, and
provider-specific details should remain behind data-control and audit policies.

Rationale: users need explainable agent state, but raw runtime internals can
leak sensitive data or create unstable UI/API contracts.

Alternatives considered:

- Expose raw runtime event streams directly. This is attractive for debugging
  but unstable and unsafe as a product surface.
- Hide runtime details behind a simple status. This is too opaque for governed
  human-agent work.

## Runtime Code Decisions

### First direct domain actions

The first runtime implementation should not allow agents to perform direct
business mutations. Agent-suggested work should go through proposed graph
changes unless a later accepted policy grants a narrow direct action. The only
initial direct domain calls should be runtime-supporting actions such as
context package assembly, authorization checks, operation-context creation,
provenance/event recording, validation, and creation of proposal/evidence
candidates through owning domain contracts.

This keeps the MVP useful without letting the first runtime quietly become a
write-capable automation platform.

### Model and tool payload retention

The first retention posture should store typed metadata, classifications,
operation/context references, summaries, hashes, and accepted structured
outputs by default. Full prompts, model inputs/outputs, raw tool payloads, and
provider responses should be retained only when a policy-approved raw archive,
debug-retention rule, audit requirement, or external replay need explicitly
allows it.

This defers provider-specific payload storage while preserving enough
provenance to explain agent behavior and reconstruct accepted graph changes.

### Runtime event ownership

Runtime event ownership should be split by purpose:

- Execution lifecycle, retries, step failures, tool steps, and future run UI
  events belong to the future `runs` model.
- Conversation messages and embedded-agent chat turns belong to conversation
  storage.
- Sensitive authorization, approval, credential, context-expansion, export, and
  external-write decisions belong to audit, authorization decision, and
  operation-correlation records.
- Raw model, provider, and tool payloads belong to raw archive or
  provider-specific payload storage only when policy allows retention.
- Runtime projections should stitch these records through operation context,
  run/conversation references, context package references, and graph item links
  rather than using one generic runtime-events table for everything.

### First automatic review agent

The first automatic agent should be an OpenSpec/spec review agent. It can run
against repo-local OpenSpec artifacts, graph decisions, checks, and proposal
text before external provider integrations are required. PR review comment
triage remains an important proving workflow, but it depends on GitHub
ingestion and richer run/verification surfaces.

This makes the first automatic agent graph-native, self-dogfooding, and
aligned with the current source-of-truth workflow.

### Context rationale visibility

Ordinary users should see concise explanations for included, omitted,
redacted, or placeholder context when those explanations do not reveal
restricted information. Administrators, auditors, and approved debugging
operators may see expanded projection and policy rationale according to
sensitivity labels, audit policy, and support-access rules. No role should gain
access to the underlying restricted context merely because a rationale exists.

## Risks / Trade-offs

- Runtime scope grows into a general automation platform -> Keep the first
  scope to graph-aware conversations, review-style agents, change proposals,
  and approved tool actions. Defer workflow builders and department packs.
- Runtime duplicates work-packet or run ownership -> Treat the runtime as an
  orchestrator and hand off durable execution records through future owning
  domains.
- Context packages leak restricted information -> Require projection-based
  assembly, redaction/placeholder behavior, and explicit context expansion.
- Approval gates create user fatigue -> Use autonomy envelopes and policy
  review opportunities for repeated low-risk approvals while keeping high-risk
  actions gated.
- Tool adapter design becomes provider-specific too early -> Start with tool
  manifests and classified outputs; keep provider SDK details behind adapters.
- Provenance captures too much sensitive prompt or payload data -> Store typed
  references, summaries, hashes, classifications, and policy-approved payload
  slices rather than defaulting to full prompt/tool payload retention.
- Proposal-first agents feel slow for low-risk actions -> Allow future accepted
  policy to grant narrow direct domain actions, but keep the default path
  proposal-first until governance proves safer automation envelopes.

## Migration Plan

This change is design-only and has no deploy or rollback action by itself.
Future implementation should proceed in narrow changes:

1. Add the `OfficeGraph.AgentRuntime` bounded context and public invocation
   envelope types without model providers or tool workers.
2. Add context package assembly contracts that call graph/projection and
   authorization domains rather than reading graph tables directly.
3. Add runtime authority evaluation calls that consume existing authorization,
   governance, credential, and operation-context contracts.
4. Add proposal-only embedded conversation behavior before automatic agents or
   external-write tool actions.
5. Add tool adapter manifests and a local test adapter before provider-backed
   tools.
6. Connect runtime output to change proposals, evidence candidates, and
   future run/work-packet/verification contracts as those designs land.

Rollback for any future implementation should disable the relevant runtime
entrypoint or tool adapter while preserving generated change proposals,
operation records, audit records, and evidence candidates.

## Open Questions

- No blocking runtime-code decisions remain in this change. Future companion
  changes still need to define concrete work-packet readiness, run-event
  persistence, API/realtime projection shapes, and frontend review surfaces.
