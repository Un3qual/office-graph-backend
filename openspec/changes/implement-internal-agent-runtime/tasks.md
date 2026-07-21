## 1. Runtime Persistence And Definitions

- [x] 1.1 Add failing migration/resource tests for agent definitions/bindings, executions, authority snapshots, context packages/entries, model/tool requests, approval/expansion requests, conversations, and messages.
- [x] 1.2 Add focused AgentRuntime and NodeConversations resources/domains/migrations, indexes, lifecycle constraints, ownership/API ledgers, and migration-owned OpenSpec-review definition.
- [x] 1.3 Add failing tests and implement the authorized organization-binding command for the OpenSpec-review definition and backend agent principal.

## 2. Model And Tool Adapter Contracts

- [x] 2.1 Add adapter conformance tests for manifests, typed input/output, capabilities, credentials, sensitivity, external-write denial, limits, idempotency, success, retry, terminal, malformed output, and cancellation.
- [x] 2.2 Implement provider-neutral model/tool behaviors, registry, deterministic adapters, classified results, and safe metadata retention without raw prompt/tool payload storage.

## 3. Invocation, Authority, And Context

- [ ] 3.1 Add failing tests for human and automatic run-linked invocation, replay, definition/run/scope validation, generic system-operation consumption, and immutable authority snapshots.
- [ ] 3.2 Implement invocation commands, effective-authority computation, operation/execution creation, and pre-step revalidation of principals, credentials, grants, approvals, and tools.
- [ ] 3.3 Add failing context-package tests, then implement authorized projection assembly, inclusion/redaction rationale, immutable versions, and cross-tenant fail-closed behavior.

## 4. Durable Execution State Machine

- [ ] 4.1 Add failing worker/concurrency tests for queued/running/waiting/retry/completed/failed/cancelled transitions, leases, restart recovery, duplicate dispatch, attempt budgets, and cancellation.
- [ ] 4.2 Implement durable step workers, state transitions, step idempotency, retry/terminal classification, cancellation, and run/projection invalidations using the unchanged shared system-operation schema.

## 5. Approvals, Expansion, And Output Routing

- [ ] 5.1 Add failing GraphQL/JSON/domain tests for approval and expansion creation, versioned approve/deny/cancel, stale conflicts, expiry, bounded scope, and resume-only-matching-step behavior.
- [ ] 5.2 Implement approval/expansion commands and resume orchestration with authorization, operation, audit, revision, and realtime provenance.
- [ ] 5.3 Add failing proposal/evidence tests, then route validated agent output through owning proposal, observation, message, and evidence-candidate commands with no direct business mutation, external write, or verification completion.

## 6. Conversations And Operator Surface

- [ ] 6.1 Add failing conversation tests for run/graph scope, human/agent provenance, redacted referenced context, message replay, and explicit proposal/domain-action linkage.
- [ ] 6.2 Implement NodeConversations commands, projections, GraphQL/JSON reads/commands, and product-relevant run timeline summaries.
- [ ] 6.3 Add failing Relay/operator tests, then implement the focused run-aware conversation, invocation, cancellation, approval, expansion, status, and error/conflict UI without agent administration or general chat.

## 7. First Automatic Agent

- [ ] 7.1 Add end-to-end deterministic tests for the OpenSpec-review agent reading authorized repo/OpenSpec context and producing messages, findings, proposals, checks, and evidence candidates.
- [ ] 7.2 Implement the read-only repository/OpenSpec tool adapters and canonical review workflow, proving it has no GitHub schema dependency or external-write path.

## 8. Verification And Archive

- [ ] 8.1 Run focused migrations, resources, adapters, runtime workers, authority, context, approvals, conversations, proposals/evidence, run projection, API, Relay UI, concurrency, query-count, and architecture tests.
- [ ] 8.2 Run strict OpenSpec validation, deterministic runtime acceptance tests, the canonical Nix-backed `mix verify` gate, and `git diff --check`.
- [ ] 8.3 Synchronize delta specs, archive `implement-internal-agent-runtime`, and confirm the final product-loop change can consume the runtime without identity/governance scope leakage.
