## Why

Office Graph needs a durable way to connect delegated work, agent/runtime
activity, external system observations, evidence, and verified completion
without treating every execution-like thing as the same record. This change
defines the runs and verification layer before backend implementation depends
on implicit run, check, evidence, waiver, or traceability semantics.

## What Changes

- Define Office Graph-managed runs as first-class execution records for work
  started and supervised by Office Graph, including internal agent runtime
  executions and approved Office Graph automation.
- Define separate execution observations for provider-native checks,
  integration jobs, external agent activity, and human handoff milestones that
  Office Graph records, imports, or links without owning their execution
  lifecycle.
- Define run events, failure states, tool-action references, provenance, and
  operation-correlation hooks for managed runs.
- Define verification checks, evidence candidates, accepted evidence,
  verification results, monitoring outcomes, and check waivers.
- Define how approval gates, proposed graph changes, work packets, runtime
  activity, audit records, and external observations can satisfy, block, or
  inform verification without bypassing domain actions or policy.
- Keep this change design-only. It does not implement Ash resources, Ecto
  migrations, Phoenix APIs, GraphQL/JSON surfaces, Oban jobs, agent execution,
  provider adapters, verification engines, or frontend UI.

## Capabilities

### New Capabilities

- `managed-execution-runs`: Office Graph-owned run lifecycle, state model,
  triggering source, authority basis, runtime references, failure handling,
  event taxonomy, tool-action references, provenance, and operation/audit
  linkage.
- `execution-observations`: provider-native check runs, integration jobs,
  external agent activity, human handoff milestones, imported statuses, source
  identity, freshness, trust level, and links to graph items, work packets,
  managed runs, and evidence.
- `verification-evidence`: verification checks, evidence candidates, accepted
  evidence, verification results, monitoring outcomes, check waivers, approval
  gate satisfaction, and traceability from completion claims back to work,
  runs, observations, proposals, decisions, and artifacts.

### Modified Capabilities

- None. Existing accepted specs for run approval governance, audit/compliance,
  walking-skeleton verification, persistence, graph relationships, and
  API/realtime projection remain constraints; this change adds the missing
  runs and verification contract that those specs reference.

## Impact

- Affects future run, run event, external observation, verification check,
  evidence, verification result, waiver, monitoring, review finding, and
  traceability resources.
- Consumes constraints from work packets/readiness, agent runtime, proposed
  graph changes, revision/audit/operation correlation, identity and
  authorization, ingestion/integration design, persistence, code organization,
  API/realtime projections, and the walking-skeleton specs.
- Constrains later backend walking-skeleton implementation, graph projection
  queries, verification gates, work packet handoffs, agent runtime event
  storage, external provider imports, and frontend verification surfaces.
- Creates no application code.
