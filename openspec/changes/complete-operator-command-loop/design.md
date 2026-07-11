## Context

The domain layer already implements the proving workflow as separate public
functions, but the only product write transport composes packet creation, run
start, observation, candidate creation, and acceptance into one
`executePacketRunVerification` mutation. React renders command affordances but
does not execute them. Manual intake and proposed-change application are used
only by internal code and tests.

The change must preserve current Ash authorization, operation correlation,
scope validation, idempotent replay, transaction boundaries, audit/revision
records, Relay ownership, dual GraphQL/JSON API support, bounded query shape,
and the unreleased-product policy. It must not introduce background execution,
provider integrations, or the agent runtime owned by later program PRs.

This PR is stacked on `codex/close-completed-changes` and targets that branch.
After the parent merges, the PR will be retargeted to `main`.

## Goals / Non-Goals

**Goals:**

- Let an operator execute every current manual-intake-to-verification step
  through supported APIs and React UI.
- Make every write one named, retry-safe, authorization-aware domain command.
- Add immutable packet version creation with optimistic current-version checks.
- Add explicit, auditable waiver of a pending run-required check.
- Remove the unreleased one-shot workflow mutation after replacement coverage.
- Preserve current list/read performance and route context during mutations.

**Non-Goals:**

- Do not add GitHub, Sentry, CI, webhook, or provider synchronization.
- Do not add Oban, Channels, subscriptions, or background execution.
- Do not add a generic question queue, decision system, agent runtime, or node
  chat. Packet fields capture the clarification needed by this workflow.
- Do not add authentication or replace the current request-session mechanism.
- Do not add search, filters, reports, a full graph editor, or packet deletion.
- Do not preserve the one-shot mutation as a compatibility alias.

## Decisions

### 1. Transport commands start operations server-side

Each mutation/action accepts an `idempotencyKey` plus command-specific input.
The transport resolves `RequestSession`, then calls a thin command function
that starts the matching `OfficeGraph.Operations` action and invokes exactly one
owning domain function. Clients never construct or choose operation records,
principal ids, tenant ids, or capability names.

This is preferred over accepting operation ids from the browser because the
server owns actor/session correlation and can consistently prevent cross-actor
operation spoofing. It is preferred over one transaction for the whole loop
because operators must see, review, retry, and stop between steps.

Operation metadata stores a normalized command-input digest. Existing domain
replay checks remain authoritative where present. New packet-version and waiver
commands compare their normalized digest on operation replay and return a
stable idempotency conflict for changed or reordered input.

### 2. One GraphQL mutation namespace and one JSON command controller family

GraphQL adds an `operator_commands` mutation module split into input parsing,
result types, and bounded-context resolver modules. JSON adds explicit command
routes under `/api/v1/commands/...` with one thin controller per owning domain
group and shared request-session/error serialization.

Generated Ash CRUD routes are not used for these orchestration commands. A
generic command bus is also rejected: every resolver/controller names its
domain function, required operation action, input shape, and result mapping.

Both transports return the command identity, operation id, affected Relay node
ids, and typed step result. They share safe error normalization but need not
share transport envelopes.

### 3. Packet updates always create immutable versions

`WorkPackets.create_version/4` takes session context, operation, packet, and
attrs including `expected_current_version_id`. Inside one database transaction
it locks the packet, reloads it in scope, compares the expected version, assigns
the next version number, bulk-creates ordered source/check links, and updates
`work_packets.current_version_id` and derived lifecycle state.

The existing `work_packet_versions.operation_id` is sufficient provenance, so
no packet-version schema migration is needed. An operation may create only one
version. Replay returns that version only when packet id, expected version,
content fields, and ordered link ids match.

Replacing version rows or updating current version content in place is rejected
because it would break packet reproducibility and historical run explanation.

### 4. Waiver is a verification result without evidence

Verification waiver uses a new `verification.waive` capability and
`verification_waive` operation action. The migration makes
`verification_results.evidence_item_id` nullable. The resource change requires
an evidence item for `passed` or `failed` results and requires no evidence item
for `waived`; all result types still require operation, check, run when
run-scoped, actor, policy basis, reason, and recorded time.

`Verification.waive_required_check/5` locks the run and its required checks,
verifies the expected run execution and verification states, verifies the check
is pending and belongs to the run packet contract, authorizes the separate
capability, inserts one waived result, marks only that run-required check
waived, and recomputes aggregate run verification.

Using fabricated evidence for a waiver is rejected because a governance
decision is not proof. Reusing `verification.complete` is rejected because
waiver authority must be grantable and auditable separately.

### 5. Relay mutations refresh authoritative projections

Route-owned mutation hooks use `commitMutation` and generated types. A mutation
disables only its owning action while pending. On success it invalidates or
refetches the current operator, packet, or run query using the returned ids;
mutation payloads do not become a second client-side workflow store.

Forms keep draft input in local React state. Packet current-version id and run
state supplied by Relay are sent as optimistic concurrency inputs. Conflict
responses show safe copy, reset the form's submission state, and trigger an
authoritative refetch before another explicit submit.

A global mutation coordinator or form framework is rejected because there are
only two routes and route ownership is an accepted frontend constraint.

### 6. Remove the one-shot path only after replacement tests are green

Implementation first adds domain and transport tests for each separate command,
then frontend tests for the operator and packet actions. The old mutation and
`OfficeGraph.PacketRunVerification` stay temporarily while tests are migrated.
After the replacement sequence covers its behavior, delete the custom mutation,
input, transport result types, schema import, API tests, and domain coordinator.

Shared domain functions, resources, and tests remain. No deprecated alias or
hidden compatibility route is retained because Office Graph is unreleased.

## Risks / Trade-offs

- **Many small commands increase transport surface** -> Keep input/result
  modules grouped by bounded context and enforce thin-transport architecture
  tests.
- **A loop can stop between steps** -> This is intentional; projections expose
  current allowed actions and all completed steps remain durable and replayable.
- **Concurrent packet edits can race** -> Lock the packet and require the
  expected current-version id.
- **Waiver can weaken verification** -> Use a separate capability, require
  reason and policy basis, audit the decision, and allow waiver only for a
  pending check in the current run contract.
- **Relay refetches can be chatty** -> Refetch only route queries affected by
  the returned ids; realtime invalidation belongs to the later delivery PR.
- **JSON and GraphQL can drift** -> Share domain command functions and safe
  error mapping, and add parity tests for authorization, validation,
  idempotency, and conflict semantics.
- **The PR can become too large** -> Commit by independently testable command
  families: intake/proposals, packets, runs/observations, evidence/waiver,
  GraphQL/JSON retirement, operator UI, packet UI.

## Migration Plan

1. Add failing domain tests for packet version creation and waiver, then add
   the migration and domain behavior.
2. Add step-specific GraphQL and JSON command tests and thin transports while
   the one-shot path still exists.
3. Add Relay mutation documents and operator actions for intake, proposal,
   packet, run, observation, evidence, and waiver.
4. Add packet workspace creation, versioning, and run-start actions.
5. Migrate one-shot behavior tests to the step-specific sequence, delete the
   old transport and coordinator, regenerate schema/Relay artifacts, and run
   caller audits.
6. Run focused tests after every slice, then strict OpenSpec validation and the
   full `mix verify` gate.

Rollback reverts the PR and its nullable evidence reference migration. Because
the product is unreleased and the migration only relaxes a null constraint,
rollback must first confirm no waived verification result exists; otherwise the
rollback is blocked rather than deleting governance history.

## Open Questions

None. Generic questions/decisions, richer approval workflows, background work,
realtime invalidation, provider integrations, and agent execution are assigned
to later feature-completion PRs.
