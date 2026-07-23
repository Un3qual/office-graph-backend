## Why

Office Graph has durable jobs, work runs, evidence, authorization records, and
graph projections, but its AgentRuntime boundary is empty. A governed runtime is
needed to turn those records into active, explainable agent work without giving
models direct graph, credential, tool, or verification authority.

## What Changes

- Add migration-owned agent definitions and authorized organization binding,
  run-linked agent executions, immutable authority snapshots, context packages,
  model requests, tool requests, approval requests, and context-expansion
  requests.
- Add durable Oban orchestration for model/tool steps, leases, retries,
  cancellation, restart recovery, and step-specific idempotency.
- Add provider-neutral model and tool adapter behaviors with deterministic local
  implementations and safe output classification.
- Route agent outputs through existing change-proposal and evidence-candidate
  commands; the first runtime cannot perform direct business mutations,
  external writes, or verification completion.
- Add node-scoped conversations and messages plus one run-aware conversation
  surface inside the operator workflow.
- Add the first automatic run-review agent using authorized Office Graph run,
  work-packet, graph, check, conversation, and evidence context without local
  repository or planning-tool access.
- Add only backend agent principals and credential metadata. Human login,
  SSO/SCIM, identity administration, generic agent administration, and general
  chat remain deferred.

## Capabilities

### New Capabilities

- `agent-definitions`: Owns migration-approved agent definitions,
  organization binding, lifecycle, model/tool configuration references, and
  default autonomy envelopes.
- `agent-context-packages`: Owns immutable authorized context references,
  inclusion/redaction rationale, and context-expansion linkage.
- `agent-tool-adapters`: Defines typed model/tool adapter manifests, requests,
  classified outputs, credential checks, limits, and retry behavior.
- `agent-approval-requests`: Defines durable approval and context-expansion
  requests plus narrow resolution commands.

### Modified Capabilities

- `agent-runtime`: Implements explicit invocation, authority computation,
  proposal-first mutation safety, durable orchestration, provenance, and
  projection handoffs.
- `agent-executions`: Adds run-linked execution lifecycle, immutable authority
  snapshots, product-relevant steps, retry, cancellation, and output routing.
- `node-conversations`: Adds persisted run-aware conversations and messages for
  human and agent contributions.
- `work-runs`: Links child agent executions and product-relevant runtime state
  without allowing child completion to verify the parent run.
- `verification-evidence`: Accepts agent material only as evidence candidates
  until the owning verification workflow accepts it.
- `operator-console`: Adds one focused run-aware agent conversation and approval
  surface without a general chat or agent-admin route.

## Impact

- Depends on typed relationships and on the provider-neutral generic
  system-operation contract owned by `OfficeGraph.Operations`; agent
  implementation must follow those contracts.
- Adds migrations, Ash resources, AgentRuntime commands, Oban workers, model and
  tool adapters, GraphQL/JSON commands and reads, Relay artifacts, operator UI,
  and deterministic execution fakes.
- Satisfies the existing realtime, API, and backend-ownership requirements
  without changing their general contracts.
- Uses existing WorkGraph, ProposedChanges, Runs, Verification, Authorization,
  Operations, DurableDelivery, Audit, and Revisions public boundaries rather
  than taking ownership of their records.
- Does not select a hosted model vendor or introduce external-write authority.
