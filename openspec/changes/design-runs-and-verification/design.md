# Runs And Verification Design

## Context

Office Graph's core loop ends in evidence, verification, and reusable context.
The current foundation, work packet, agent runtime, proposed-change, audit, and
persistence designs already reference runs, run events, checks, evidence,
review findings, approval gates, and verification results, but they do not yet
define the owning concepts.

The most important boundary is that not every execution-like thing should be a
run. Office Graph should own the lifecycle for work it starts and supervises,
such as internal agent executions or approved Office Graph automation. It
should separately record provider-native checks, integration jobs, external
agent activity, and human handoff milestones as observations or evidence
sources. Verification then decides which checks are required, which observations
or artifacts count as evidence, and whether a completion claim is accepted.

This keeps Office Graph traceable without pretending that GitHub Actions,
external review bots, human review activity, imported provider statuses, and
internal agent runs all have the same lifecycle semantics.

## Goals / Non-Goals

**Goals:**

- Define Office Graph-managed runs as owned execution records with explicit
  authority, lifecycle, event, failure, provenance, and operation-correlation
  semantics.
- Define execution observations for provider-native checks, external agent
  activity, integration jobs, human handoff milestones, and imported statuses
  that Office Graph can link, interpret, and use without owning their
  lifecycle.
- Define verification checks, evidence candidates, accepted evidence,
  verification results, monitoring outcomes, and check waivers.
- Define how runs, observations, proposed graph changes, approval gates,
  review findings, work packets, artifacts, audit records, and revisions
  connect through traceable verification.
- Keep run events separate from audit records, domain events, external sync
  events, raw archives, and revision history while allowing shared operation
  correlation.
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
- No policy shortcut that lets a passing provider check, external approval, or
  run success automatically satisfy Office Graph verification without mapped
  checks, authority, and evidence acceptance.

## Decisions

### 1. Separate Managed Runs From Execution Observations

A managed run is an Office Graph-owned execution record. It is created when
Office Graph starts or supervises work with an explicit invocation source,
authority basis, scope, lifecycle state, and operation context. Initial managed
run categories should include internal agent runtime executions, approved
automation, verification jobs that Office Graph owns, and future delegated
execution packages that run under Office Graph supervision.

An execution observation is a record of execution-like activity whose lifecycle
is owned elsewhere or by a human process. Examples include provider-native
check runs, CI jobs, imported deployment statuses, external review-bot comments,
external agent activity, integration sync jobs, pull request review events,
manual completion notes, and human handoff milestones.

Rationale: Office Graph needs to reason about both categories, but they answer
different questions. A managed run asks, "What did Office Graph start, allow,
supervise, block, retry, or stop?" An observation asks, "What did Office Graph
learn happened elsewhere, how fresh is it, and can it support verification?"

Alternatives considered:

- Use one broad `run` concept for all execution-like records. This simplifies
  search, but it lies about ownership and makes external state transitions look
  controllable by Office Graph.
- Model only managed runs and attach external data as loose evidence. This
  avoids lifecycle confusion but loses important source, status, freshness,
  trust, and replay details for provider-native checks and human handoffs.
- Treat provider-native check runs as domain-specific records only. This keeps
  provider models pure but makes cross-provider verification and evidence
  projections harder.

### 2. Managed Runs Own Office Graph Execution Lifecycle

Managed runs should carry organization, scope, source graph item or trigger,
work packet version when applicable, invocation mode, principal, agent
principal when applicable, delegator or trigger authority, autonomy envelope,
requested capabilities, operation context, current lifecycle state, terminal
result, and provenance references.

The lifecycle should distinguish at least queued, running, waiting for
approval, waiting for context expansion, blocked, succeeded, failed, cancelled,
timed out, and superseded. Domain-specific runtime details can extend this
vocabulary, but product projections should expose an understandable status
instead of raw worker internals.

Managed run events should be append-only timeline records for meaningful
execution steps: run started, context package selected, authority evaluated,
model step completed, tool action requested, tool action completed, approval
requested, approval received, context expansion requested, output classified,
proposed change created, evidence candidate produced, failure occurred, retry
scheduled, run completed, and run cancelled.

Rationale: a managed run is the audit-adjacent product record for supervised
execution. It needs enough lifecycle detail for product review, debugging,
verification, and future context reuse without becoming the audit log or the
agent runtime's private state dump.

Alternatives considered:

- Store managed run state only in worker/job tables. This hides product
  execution history and makes verification evidence hard to explain.
- Store every low-level runtime message as a run event. This creates volume,
  retention, and sensitivity problems. Low-level traces can remain logs or raw
  archives unless they become product-relevant.
- Make terminal run success equivalent to verification success. This is wrong:
  a run can execute successfully while producing invalid evidence or incomplete
  work.

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
proposed change, completion claim, or monitored outcome is accepted. Checks can
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
monitoring outcomes, and proposed-change application traces can create evidence
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

Rationale: approvals are shared across work packets, proposed changes, context
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
produced by managed runs, execution observations, external reviewers, imported
provider comments, or humans. Findings can require tasks, proposed changes,
verification checks, evidence, or waivers, but they are not the same as
evidence by default.

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

Managed runs, run events, execution observations, evidence candidates,
accepted evidence, verification results, waivers, proposed changes, revisions,
audit records, and authorization decisions should reference operation
correlation when they belong to the same meaningful command or externally
observed action.

The operation record should not become the event payload or a polymorphic
target table. Each owning domain keeps its typed record and uses the operation
reference for traceability.

Rationale: verification needs a chain from completion claim back through
packet, run or observation, evidence, approval, proposed change, audit, and
revision. Operation correlation provides the spine without collapsing all
record types into one table.

Alternatives considered:

- Store only loose graph edges between all records. Edges are useful for graph
  traversal but weaker for command traceability, idempotency, and audit review.
- Put all execution and verification facts on the run. This fails when the
  source is external or human-owned and when verification spans multiple runs
  and observations.

### 10. High-Volume Events Need Tiered Retention

Managed run events, execution observations, monitoring outcomes, and provider
check imports can grow quickly. The first design should require tenant/scope,
source, status, target, operation, and time indexes, and it should identify
likely partitioning paths before implementation. Product-relevant summaries and
evidence links should remain queryable even if raw low-level traces expire or
move to archive storage.

Rationale: run and verification data is valuable, but unrestricted retention of
every low-level event will create performance, privacy, and cost problems.

Alternatives considered:

- Keep everything forever in primary tables. This is simple, but likely
  unsustainable for CI, monitoring, provider imports, and agent runtime traces.
- Keep only terminal results. This loses failure analysis, provenance, and
  reusable context.

## Risks / Trade-offs

- [Risk] The distinction between managed runs and observations may feel
  abstract in early implementation. Mitigation: make the walking skeleton use
  one managed run only if Office Graph truly starts work; otherwise use
  observations and evidence links for imported or human-owned activity.
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
   verification results, and only the skeletal managed run or observation
   records required to prove the loop.
2. Add managed run records and run events when the internal agent runtime or
   Office Graph-owned automation first starts supervised work.
3. Add execution observations for imported provider checks, external review
   bot activity, integration jobs, and human handoff milestones as integrations
   require them.
4. Connect work packet handoff to managed runs or observations through explicit
   packet version, authority, context package, and operation references.
5. Connect proposed graph change application, revisions, audit records, and
   authorization decisions through operation correlation so verification can
   trace accepted changes.
6. Add projection and API/realtime contracts for verification summary, evidence
   chain, run status, observation freshness, waiver state, and stale markers.
7. Add growth controls, indexing, partitioning, raw archive references, and
   retention behavior before high-volume provider checks, monitoring outcomes,
   or agent event streams become production-scale.

Rollback for early implementation should avoid destructive migration rollback
where possible: disable new producers, stop accepting new observations or run
events, and leave historical evidence and verification records readable until a
data migration can safely remove or supersede them.

## Open Questions

- Which first walking-skeleton path should create a managed run, if any, versus
  relying on observations and evidence around manual intake?
- What exact product vocabulary should appear in the UI for observation trust:
  raw, normalized, accepted, stale, disputed, superseded, or a smaller set?
- Should verification results be materialized immediately for every target or
  created only when a completion claim is evaluated?
- Which low-risk evidence candidates can be automatically accepted in MVP?
- What monitoring outcomes belong in this design's first implementation slice
  versus a later observability-specific design?
