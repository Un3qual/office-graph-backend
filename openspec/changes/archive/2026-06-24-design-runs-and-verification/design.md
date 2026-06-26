# Runs And Verification Design

## Context

Office Graph's core loop ends in evidence, verification, and reusable context.
The current foundation, work packet, agent runtime, change-proposal, audit, and
persistence designs already reference runs, run events, checks, evidence,
review findings, approval gates, and verification results, but they do not yet
define the owning concepts.

The most important boundary is that a run of selected work is not the same
thing as one agent invocation. A work run is the parent execution of a selected
work packet, task, requirement, graph selection, or bounded objective. It may
coordinate multiple agent executions, human handoffs, integration activity,
provider observations, change proposals, checks, and evidence.

Agent executions are child runtime invocations inside that parent work run. An
agent execution can perform one step, investigate one task, call tools, produce
findings, propose changes, or emit evidence candidates, but it should not be
the top-level representation of the work being executed.

This gives Office Graph a durable execution spine without pretending that
GitHub Actions, external review bots, human review activity, imported provider
statuses, work-packet execution, and internal agent invocations all share the
same lifecycle semantics.

## Goals / Non-Goals

**Goals:**

- Define work runs as parent execution records for selected work, with
  aggregate status, authority posture, child execution references, evidence
  summary, and operation-correlation semantics.
- Define agent executions as child runtime invocations inside a work run, with
  their own context packages, tool/model steps, failure states, outputs, and
  provenance.
- Define execution observations for provider-native checks, external agent
  activity, integration jobs, human handoff milestones, and imported statuses
  that Office Graph can link, interpret, and use without owning their
  lifecycle.
- Define verification checks, evidence candidates, accepted evidence,
  verification results, monitoring outcomes, and check waivers.
- Define how work runs, agent executions, observations, change proposals,
  approval gates, review findings, work packets, artifacts, audit records, and
  revisions connect through traceable verification.
- Keep work-run events and agent-execution events separate from audit records,
  domain events, external sync events, raw archives, and revision history while
  allowing shared operation correlation.
- Preserve a minimal walking-skeleton path while leaving room for richer agent
  runtime, provider import, monitoring, and frontend verification surfaces.

**Non-Goals:**

- No Phoenix, Ash, Ecto, migration, GraphQL, JSON API, React, Oban, provider
  adapter, agent runtime, or verification engine implementation.
- No attempt to make Office Graph the source of truth for provider-owned job
  lifecycles, CI systems, external review bots, or human communication tools.
- No single generic event table for runs, audit, revisions, sync, domain
  events, and observations.
- No final UI layout, transport schema, or table column list.
- No policy shortcut that lets a passing provider check, external approval,
  work-run success, or agent-execution success automatically satisfy Office
  Graph verification without mapped checks, authority, and evidence acceptance.

## Decisions

### 1. Work Runs Are Parent Executions Of Selected Work

A work run is the Office Graph-owned parent execution record for a selected
unit of work. The selection can be a work packet version, task, requirement,
change proposal, graph item set, conversation request, incident, campaign
artifact, or another bounded objective. A work run answers: "What work did we
try to execute, under which authority and scope, with which participants and
evidence, and what was the aggregate outcome?"

Work runs should carry organization, scope, selected work reference, work
packet version when present, objective, triggering source, initiating
principal or trigger, authority posture, autonomy envelope summary, aggregate
lifecycle state, child execution references, required checks, evidence summary,
operation context, and terminal outcome.

A work run can contain multiple child records:

- agent executions for individual internal agent invocations
- human handoff or review milestones
- execution observations from providers, CI, external agents, and integrations
- change proposals produced during execution
- verification checks, evidence candidates, accepted evidence, and waivers
- operation, audit, authorization-decision, revision, and artifact references

```
work_run
  -> work_packet_version or selected graph/work target
  -> agent_execution[0..n]
  -> execution_observation[0..n]
  -> change_proposal[0..n]
  -> domain_action / revision / audit references
  -> verification_check / evidence / waiver / verification_result
```

Example:

```
work_run WR-1042
  selected work: WP-42 v3 / requirement "contracts expose renewal_date"
  scope: Acme org, contract graph, import connector
  authority: proposal-only until approval
  status: running -> waiting_for_approval -> verifying -> complete

  agent_execution AE-1: investigate current contract model
  agent_execution AE-2: draft the change
  approval_gate AG-9: human approves applying it
  change_proposal CP-12: proposed domain action, not graph truth
  domain_action DA-33: validated application of the approved change
  execution_observation EO-55: provider check passed
  execution_observation EO-56: external review bot finding imported
  evidence_candidate EC-21: test output from AE-2
  accepted_evidence EV-21: test output accepted for "import works"
  verification_result VR-8: required checks satisfied or waived
  audit/revision records: what changed, actor, operation correlation
```

Rationale: execution of selected work is the product-level unit users care
about. It can span several agent invocations, human decisions, provider checks,
and evidence updates. Making the work run the parent keeps the product model
honest and avoids making a single agent invocation stand in for the whole work.

Alternatives considered:

- Make every agent invocation a run. This matches agent-runtime terminology but
  loses the parent execution context when a work packet requires several
  agents, retries, handoffs, or provider checks.
- Use one broad run table for work runs, agent executions, provider checks, and
  human handoffs. This simplifies querying but erases ownership and lifecycle
  differences.
- Treat work runs as just work packet status. This avoids another record, but
  it hides execution history, retries, child attempts, evidence production, and
  operation correlation.

### 2. Agent Executions Are Child Runtime Invocations

An agent execution is one internal agent runtime invocation inside a work run.
It answers: "Which agent was invoked, with what context and authority, what
model/tool steps happened, what outputs were produced, and how did this
invocation end?"

Agent executions should carry parent work run, invocation mode, selected task
or sub-objective, context package reference, agent principal, delegator or
trigger authority, autonomy envelope, requested capabilities, model/tool step
summaries, current lifecycle state, terminal result, output classification,
failure state, retry/supersession references, and provenance.

The agent-execution lifecycle should distinguish at least queued, running,
waiting for approval, waiting for context expansion, blocked, succeeded,
failed, cancelled, timed out, retried, and superseded. Product projections can
roll these up into the parent work run without exposing raw worker internals.

Agent-execution events should be append-only timeline records for meaningful
runtime steps: execution started, context package selected, authority
evaluated, model step completed, tool action requested, tool action completed,
approval requested, approval received, context expansion requested, output
classified, change proposal created, evidence candidate produced, failure
occurred, retry scheduled, execution completed, and execution cancelled.

Rationale: a work run may have several agent executions: one to analyze a
review finding, another to draft a change proposal, another to run a
verification step, and another to summarize evidence. Each invocation needs its
own context, authority, failure, and provenance without fragmenting the
product-level work execution.

Alternatives considered:

- Store agent executions only inside runtime worker tables. This hides product
  execution history and makes verification evidence hard to explain.
- Store every low-level runtime message as an agent-execution event. This
  creates volume, retention, and sensitivity problems. Low-level traces can
  remain logs or raw archives unless they become product-relevant.
- Make terminal agent-execution success equivalent to work-run or verification
  success. This is wrong: an agent can complete its invocation while producing
  invalid evidence, a failed change proposal, or only partial progress.

### 3. Observations Preserve Source Truth Without Becoming Truth

Execution observations should preserve source identity, provider or human
origin, observed status, source timestamp, ingestion timestamp, freshness,
replay/idempotency key, actor mapping when available, related external
reference, related graph item, trust level, and whether the observation is raw,
normalized, stale, superseded, disputed, or accepted as evidence.

Provider-native payloads and large source details should remain in raw archives
or provider-specific extension records. The observation should store the typed
facts Office Graph needs for verification and projection, not every provider
field.

Rationale: Office Graph should be able to say "GitHub Actions reported this
check passed at this commit," "an external review bot made this finding," or
"a human marked this handoff complete" without claiming it controlled that
activity. Observations are inputs to reasoning, not automatic state changes.

Alternatives considered:

- Copy all provider data into observation records. This bloats the common
  model, weakens provider-specific evolution, and conflicts with raw archive
  boundaries.
- Store observations only as graph edges. Edges can express relationship, but
  not enough source status, freshness, trust, replay, or provider detail.
- Convert every observation directly into evidence. Verification needs a
  separate acceptance step because not all observations are relevant, trusted,
  current, or policy-sufficient.

### 4. Verification Is Check-Based, Not Run-Based

Verification should center on explicit verification checks. A check defines a
condition that must be satisfied before a task, work packet, requirement,
change proposal, completion claim, or monitored outcome is accepted. Checks can
be required, optional, advisory, blocking, satisfied, failed, stale, waived, or
superseded.

A verification result records how a specific target's verification state was
decided at a point in time: target, check set, satisfied checks, failed checks,
waived checks, accepted evidence, rejected or stale evidence, approver or
policy basis, operation correlation, actor/source, and timestamp.

Rationale: completion should depend on requirements and evidence, not merely
on whether a run ended or a provider status is green. This makes verification
portable across internal agents, humans, CI, external tools, and future
department-specific workflows.

Alternatives considered:

- Mark tasks verified when the latest run succeeds. This fails for human work,
  external checks, partial completion, policy approvals, and evidence review.
- Store verification as a boolean on each task. This hides which checks were
  required, why evidence was trusted, and what changed after verification.
- Let provider check status be authoritative. External systems can provide
  strong evidence, but Office Graph policy decides whether that evidence
  satisfies graph-native requirements.

### 5. Evidence Moves Through Candidate And Acceptance States

Evidence should be an explicit product concept with source, target, evidence
kind, supporting artifact or observation, produced-by run or imported source,
claim, freshness, sensitivity, trust basis, and visibility policy. Agent
outputs, tool results, provider checks, human notes, artifacts, approvals,
monitoring outcomes, and change-proposal application traces can create evidence
candidates.

An evidence candidate should not satisfy a check until accepted automatically
by policy or manually by an authorized principal. Acceptance should record
which check or claim it supports, why it is sufficient, whether any redactions
apply, and what operation or approval basis made it acceptable.

Rationale: separating candidate from accepted evidence keeps agents and
integrations productive without letting unreviewed or stale outputs silently
close work.

Alternatives considered:

- Treat every artifact or observation as evidence. This creates noisy and
  misleading verification chains.
- Require human acceptance for every evidence item. This is safe but creates
  approval fatigue and prevents low-risk automated checks from being useful.
- Store evidence only as attachments. Attachments preserve payloads but not
  claims, sufficiency, freshness, policy, or check linkage.

### 6. Waivers Are Governed Exceptions, Not Evidence

A check waiver should be a governed exception against a verification check. It
must record target, check, requester, approver or policy basis, reason,
expiration or review rules, sensitivity, separation-of-duties status, related
approval gate, related run or observation when applicable, and audit linkage.

Waivers may let verification proceed, but they do not prove the underlying
condition. Product projections should distinguish "verified by evidence" from
"accepted with waiver."

Rationale: enterprise users need to ship, approve, or proceed through
exceptions, but those exceptions must remain explicit and reviewable.

Alternatives considered:

- Represent waivers as passing evidence. This erases the fact that the
  condition was not proven.
- Represent waivers as task comments. This hides policy, approval, retention,
  and separation-of-duties requirements.

### 7. Approval Gates Can Satisfy Or Unblock Verification

Approval gates remain governed requirements owned by enterprise governance.
The verification layer should consume approval gate state and may link an
approval as evidence for a check when policy says the approval proves or
unblocks the condition. Provider-native approvals can be imported as execution
observations and then accepted as evidence only after actor mapping, scope,
source, and policy relevance are validated.

Rationale: approvals are shared across work packets, change proposals, context
expansion, waivers, sensitive data access, external writes, and verification.
Runs and verification should not fork approval semantics.

Alternatives considered:

- Add verification-local approvals. This duplicates governance and weakens
  separation-of-duties rules.
- Trust all provider approvals automatically. External approvals can be useful,
  but Office Graph policy may require graph-native approval or additional
  evidence.

### 8. Review Findings Are Work Inputs With Verification Effects

Review findings should be treated as graph-linked work inputs that may be
produced by work runs, agent executions, execution observations, external
reviewers, imported provider comments, or humans. Findings can require tasks,
change proposals, verification checks, evidence, or waivers, but they are not
the same as evidence by default.

Rationale: a CodeRabbit comment, internal review-agent finding, or human review
note may identify work to do. It only becomes evidence when it supports a
specific verification claim.

Alternatives considered:

- Treat findings as evidence. Many findings are allegations or questions, not
  proof.
- Treat findings as tasks only. Some findings remain review context,
  duplicate markers, waived concerns, or monitoring signals rather than direct
  tasks.

### 9. Operation Correlation Links Related Records

Work runs, work-run events, agent executions, agent-execution events,
execution observations, evidence candidates, accepted evidence, verification
results, waivers, change proposals, revisions, audit records, and
authorization decisions should reference operation correlation when they belong
to the same meaningful command or externally observed action.

The operation record should not become the event payload or a polymorphic
target table. Each owning domain keeps its typed record and uses the operation
reference for traceability.

Rationale: verification needs a chain from completion claim back through
packet, work run, agent execution, observation, evidence, approval,
domain action, audit, and revision. Operation correlation provides the spine without
collapsing all record types into one table.

Alternatives considered:

- Store only loose graph edges between all records. Edges are useful for graph
  traversal but weaker for command traceability, idempotency, and audit review.
- Put all execution and verification facts on the work run. This fails when
  the source is an individual agent execution, external observation, or
  human-owned activity, and when verification spans multiple child records.

### 10. High-Volume Events Need Tiered Retention

Work-run events, agent-execution events, execution observations, monitoring
outcomes, and provider check imports can grow quickly. The first design should
require tenant/scope, source, status, target, operation, and time indexes, and
it should identify likely partitioning paths before implementation.
Product-relevant summaries and evidence links should remain queryable even if
raw low-level traces expire or move to archive storage.

Rationale: run and verification data is valuable, but unrestricted retention of
every low-level event will create performance, privacy, and cost problems.

Alternatives considered:

- Keep everything forever in primary tables. This is simple, but likely
  unsustainable for CI, monitoring, provider imports, and agent runtime traces.
- Keep only terminal results. This loses failure analysis, provenance, and
  reusable context.

## Risks / Trade-offs

- [Risk] The distinction among work runs, agent executions, and observations
  may feel abstract in early implementation. Mitigation: make the walking
  skeleton create a work run only when there is a selected work objective being
  coordinated, create an agent execution only when the internal runtime is
  invoked, and use observations for imported or human-owned activity.
- [Risk] Verification records become too complex for the MVP. Mitigation:
  start with required checks, evidence candidates, accepted evidence,
  verification results, and waivers; defer richer monitoring and confidence
  scoring.
- [Risk] Provider-native checks look duplicated across provider extension
  tables and observations. Mitigation: provider tables own provider detail;
  observations own cross-provider verification facts and source freshness.
- [Risk] Evidence acceptance creates approval fatigue. Mitigation: allow
  policy-approved automatic acceptance for low-risk, deterministic checks while
  requiring human approval for sensitive, ambiguous, stale, or external-write
  claims.
- [Risk] Run events become a hidden audit log. Mitigation: keep audit records
  separate and require sensitive tool use, credential use, waivers, approvals,
  exports, and external writes to create audit records when policy requires.
- [Risk] Verification state goes stale after source context changes.
  Mitigation: track source timestamps, packet versions, target revisions,
  observation freshness, and invalidation events; mark verification stale or
  require re-verification when material inputs change.
- [Risk] A single evidence chain crosses many domains. Mitigation: use typed
  records plus operation correlation and graph relationships, not a generic
  payload table.

## Migration Plan

1. In a later implementation plan, introduce the minimal record families
   needed by the walking skeleton: verification checks, evidence items,
   verification results, and only the skeletal work run, agent execution, or
   observation records required to prove the loop.
2. Add work run records and work-run events when Office Graph first coordinates
   execution of a selected work objective.
3. Add agent execution records and agent-execution events when the internal
   agent runtime first performs child invocations inside a work run.
4. Add execution observations for imported provider checks, external review
   bot activity, integration jobs, and human handoff milestones as integrations
   require them.
5. Connect work packet handoff to work runs, agent executions, or observations
   through explicit packet version, authority, context package, parent/child,
   and operation references.
6. Connect change-proposal application, revisions, audit records, and
   authorization decisions through operation correlation so verification can
   trace accepted changes.
7. Add projection and API/realtime contracts for verification summary, evidence
   chain, work-run status, child execution status, observation freshness,
   waiver state, and stale markers.
8. Add growth controls, indexing, partitioning, raw archive references, and
   retention behavior before high-volume provider checks, monitoring outcomes,
   or agent event streams become production-scale.

Rollback for early implementation should avoid destructive migration rollback
where possible: disable new producers, stop accepting new observations or run
events, and leave historical evidence and verification records readable until a
data migration can safely remove or supersede them.

## Open Questions

- Which first walking-skeleton path should create a work run, if any, versus
  relying on observations and evidence around manual intake?
- What exact product vocabulary should appear in the UI for observation trust:
  raw, normalized, accepted, stale, disputed, superseded, or a smaller set?
- Should verification results be materialized immediately for every target or
  created only when a completion claim is evaluated?
- Which low-risk evidence candidates can be automatically accepted in MVP?
- What monitoring outcomes belong in this design's first implementation slice
  versus a later observability-specific design?
