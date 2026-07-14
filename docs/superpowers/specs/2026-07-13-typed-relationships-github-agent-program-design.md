# Typed Relationships, GitHub Integration, And Agent Runtime Program Design

date: 2026-07-13
status: approved

## Outcome

Plan three dependency-ordered OpenSpec changes that advance Office Graph from
its manual operator loop toward the accepted software review, agent execution,
and verification workflow:

1. `implement-typed-graph-relationships`
2. `add-github-review-integration`
3. `implement-internal-agent-runtime`

The changes remain independently reviewable and reversible. Shared
infrastructure travels with its first real product consumer rather than landing
as an unused horizontal platform.

## Identity And Governance Deferral

Identity and governance administration is deferred, not deleted from the final
release boundary. These changes do not implement:

- browser login or logout;
- OIDC, SAML, SCIM, or external human identity reconciliation;
- custom-role, group-mapping, or temporary-grant administration;
- installation, credential, or governance settings UI; or
- a replacement for the current local-owner development session.

The GitHub and agent changes may create and use the minimum backend-only
service, webhook-source, and agent principals and credential metadata needed to
authenticate and authorize their own work. Secret values remain outside product
records. The final product loop remains blocked on restoring the deferred human
identity and governance slice.

## Dependency Structure

```text
origin/main
  |
  +-- implement-typed-graph-relationships
        |
        +-- add-github-review-integration
              extends shared operations for the first system-job consumer
              |
              +-- implement-internal-agent-runtime
                    consumes typed relationships and shared system operations
```

The GitHub and agent OpenSpec artifacts may be prepared in parallel after the
typed relationship contract is accepted. Agent implementation targets the
GitHub branch or waits for it to merge because it must consume the generic
system-operation contract introduced by GitHub without changing that contract's
schema. If the system-operation migration or authorization contract becomes too
large to review alongside GitHub behavior, it must be split into its own
OpenSpec change before implementation continues.

## Change 1: Implement Typed Graph Relationships

### Purpose

Replace free-form relationship strings with an explicit relational vocabulary
that can validate graph structure, preserve provenance and lifecycle, and serve
provider integrations and agents without granting access through edges.

### Registry And Storage

Use migration-owned relational definitions rather than a hard-coded enum or a
user-editable type builder. Relationship definitions record:

- stable key, family, direction, and meaning;
- allowed source and target graph-item kinds;
- lifecycle and restoration behavior;
- provenance requirements;
- authorization posture;
- cycle policy; and
- whether specialization is permitted.

Endpoint compatibility belongs in typed rule rows rather than JSON metadata.
The first migration installs the canonical MVP vocabulary. Normal environments
must not depend on application seeds.

Graph relationship rows retain concrete source and target graph-item foreign
keys and add explicit organization and governing-workspace scope, lifecycle
state, asserting principal, operation correlation, optional run or integration
event provenance, validity dates, and supersession or tombstone references.
Metadata remains narrow and typed. Explanations, approvals, findings, evidence,
and other substantive facts remain in their owning resources.

### Commands And Validation

Creation, supersession, archival, and eligible restoration use named WorkGraph
commands. Integrations and agents may propose relationships but cannot insert
them directly.

Commands validate endpoint kinds, organization ownership, governing scope,
lifecycle, provenance, uniqueness, and type-specific cycle policy in the same
transaction as the write. Cross-workspace relationships require a named
authorized action. An edge never grants access to its target; traversal applies
the target's own authorization and redaction policy.

Cycle checks run only for relationship definitions that prohibit cycles and use
a bounded traversal inside the creation transaction. Concurrency protection
must prevent two individually valid concurrent writes from committing a
forbidden cycle.

### Migration

Because Office Graph is unreleased, migrate to the canonical vocabulary instead
of retaining aliases:

- `has_review_finding` becomes `review_finding_for`, reversing endpoints where
  needed to match the canonical direction.
- `requires_verification` becomes `requires_check`.
- Unknown persisted relationship values fail the migration with a bounded
  diagnostic instead of silently becoming generic types.

The migration must preserve identifiers or provide an explicit replacement map,
retain insertion provenance where available, and be reversible without
reintroducing ambiguous vocabulary.

### Verification

Cover registry installation, backfill and reversal, unknown legacy values,
endpoint compatibility, same-organization enforcement, authorized cross-scope
creation, forbidden cycles under concurrency, duplicate creation, lifecycle and
restoration, provenance, authorization-filtered traversal, and bounded query
shape. Update API and projection contracts to expose canonical relationship
identity and lifecycle without exposing registry administration.

## Change 2: Add GitHub Review Integration

### Purpose

Turn signed GitHub review and check activity into replay-safe Office Graph
signals and provider-neutral software records, then support narrow authorized
review replies and status updates.

### Provider Boundary And Data Model

Implement GitHub as an adapter package over shared integration contracts.
Provider-neutral resources own repositories, refs, commits, pull requests,
review threads, review comments, and check runs. GitHub-specific identifiers,
installation behavior, and payload interpretation remain in extension
resources. External references connect provider records to Office Graph graph
items and typed relationships.

Store GitHub App installation and permission metadata plus credential
references. Product tables never store secret values. A narrow `SecretStore`
adapter resolves webhook secrets and installation private-key material, with a
deterministic test implementation and an environment-backed development
implementation.

The change may create backend-only installation, webhook-source, and service
principals. It does not add human identity flows or an integration-management
UI. A narrow authorized GraphQL and JSON command binds a GitHub installation,
Office Graph organization, optional governing workspace, service principal, and
credential references. The current authorized local owner may invoke that
command during development; it does not become a public unauthenticated setup
path.

### Inbound Flow

```text
signed webhook
  -> verify signature and installation
  -> create system operation
  -> archive the valid payload
  -> idempotently enqueue normalization and reconciliation
  -> update provider-neutral resources and external references
  -> create typed graph relationships
  -> emit an operator signal and projection invalidation
```

Support pull-request state, review and review-comment activity, check runs and
check suites, installation lifecycle, and repository-access changes required by
the proving workflow. Webhooks are change notifications rather than complete
truth: partial or out-of-order events schedule an authoritative provider
reconciliation before newer local state can be overwritten.

### Shared System Operations

Extend Operations and DurableDelivery with a provider-neutral system-operation
contract. It supports authenticated service or webhook-source principals without
a human session and organization-scoped work with an optional governing
workspace. Subject identity and subject version are optional only for declared
organization-scoped system jobs. The contract records authority basis,
causation, idempotency scope, credential reference, and operation correlation.

Existing human commands retain their session requirements. System-operation
support must not create a fallback that lets browser or API traffic omit a
session. GitHub delivery IDs, installation IDs, provider object identities and
versions, and action-specific keys provide replay identity.

### Outbound Flow

Outbound commands are limited to review replies and status or check updates.
They require explicit authorization, installation permission, scoped credential
resolution, operation correlation, and idempotency. Each attempt records the
provider response identity and classified outcome. The change does not push
commits, write branches, merge pull requests, or become a general GitHub
automation platform.

### Failure Handling And Health

Invalid signatures and unknown installations fail before product payload
archival. Duplicate deliveries return success without duplicate effects.
Transient provider failures and rate limits retry with bounded backoff. Revoked
installations, missing permissions, invalid credentials, and provider validation
failures become visible terminal or configuration states. Out-of-order provider
versions are skipped or reconciled rather than overwriting newer state.

Expose bounded integration-health, sync-state, and terminal-job projections
through supported APIs. A finished settings surface remains owned by the later
product-loop change.

### Verification

Use a deterministic fake GitHub client/server and webhook signer with no network
dependency. Cover signature verification, installation lookup, replay,
out-of-order delivery, reconciliation, installation revocation, permissions,
rate limits, credential failure, cross-tenant isolation, system-operation
authorization, provider-neutral mapping, typed relationship creation, query
bounds, external-write idempotency, and health projections.

Also prove a non-GitHub system job can use the shared operation contract so the
foundation cannot drift into a GitHub-specific abstraction.

## Change 3: Implement Internal Agent Runtime

### Purpose

Implement a governed orchestrating runtime that can inspect authorized graph
context, execute model and tool steps durably, create proposals and evidence
candidates through owning domains, and explain what the agent could see and do.

### Ownership And Resources

AgentRuntime coordinates existing domains but does not own graph truth, work
packets, runs, verification results, credentials, authorization facts, audit
records, or revisions.

Agent definitions record lifecycle, agent principal, supported modes, requested
capabilities, model adapter, tool allowlist, and default autonomy envelope.
Every MVP execution belongs to a work run and records origin, selected graph
context, delegator or trigger authority, effective scope, agent principal,
operation, and immutable authority snapshot.

The first OpenSpec-review agent definition is migration-owned and can be bound
to an organization through a narrow authorized backend command. Generic agent
definition administration and its UI remain deferred.

Context packages contain typed authorized references and inclusion, omission,
redaction, or restriction rationale. They do not copy graph truth or preload
unrestricted raw archives. Model requests and classified outputs remain
provider-neutral. Tool adapters declare typed inputs and outputs, capability and
credential needs, external-write posture, timeout and budget limits, and output
classification.

Approval requests and context-expansion requests are explicit durable records
resolved through narrow GraphQL and JSON commands. The existing authorized
local owner can resolve them while identity and governance administration is
deferred.

Add node-scoped conversations and messages attached to the selected graph item
and run, preserving author or source, visibility, operation, execution, and
provenance. Provide one focused run-aware conversation surface inside the
existing operator workflow rather than a general chat route.

### Execution Flow

```text
explicit invocation
  -> create run-linked execution and authority snapshot
  -> assemble authorized context package
  -> enqueue durable model step
  -> validate and classify structured output
  -> request tool, approval, or context expansion when required
  -> route accepted output to proposal or evidence commands
  -> record provenance and update run and conversation projections
```

The first automatic agent is the repo's OpenSpec and specification review
agent. It exercises graph context, read-only repository/OpenSpec tooling,
findings, proposals, checks, and evidence candidates without depending on the
GitHub schema. GitHub review tools become optional adapters after the integration
change.

### Authority And Mutation Safety

Effective authority is the intersection of delegator or trigger authority,
agent capabilities, autonomy envelope, scope, tool permissions, credential
scope, sensitivity policy, organization policy, and temporary grants. Missing
authority causes denial, an approval request, a context-expansion request, or
proposal-only behavior.

Model output is untrusted structured output. The first runtime is
proposal-first: it cannot directly perform business mutations or external
writes. Agent-produced verification material begins as an evidence candidate
and cannot mark work verified.

### Durability, Failure, And Retention

Execution states include queued, running, waiting for approval, waiting for
context, retry scheduled, completed, failed, and cancelled. Oban owns durable
steps, leases, bounded retries, timeout recovery, restart survival, and
idempotent dispatch. Repeated model, tool, or domain effects are prevented by
step-specific idempotency identities.

Raw prompts, model responses, tool payloads, and secrets are not retained by
default. Retain typed metadata, hashes, classifications, accepted structured
output, context and operation references, and product-relevant provenance.
Revoked principals, credentials, tools, or grants fail closed before the next
step without erasing historical execution records.

The runtime includes a deterministic executable model adapter and deterministic
tool adapters for normal tests and local development. Hosted model adapters
remain replaceable extensions and are not required by the normal verification
gate.

### Verification

Cover deterministic model and tool behavior, restart and retry, concurrent
dispatch, idempotency, authority snapshots, context redaction, approval and
expansion flows, credential denial, revoked authority, malformed model output,
proposal and evidence routing, verification isolation, conversation provenance,
realtime invalidation, cross-tenant isolation, bounded query shape, and the
focused operator conversation experience.

The agent change must consume the shared system-operation contract without a
schema change. A required schema rewrite triggers the split threshold and a
separate foundation change rather than coupling agent semantics to GitHub.

## Program Completion Boundary

These three changes do not by themselves make Office Graph feature complete.
The final product-loop change still owns dedicated run and entity surfaces,
integration and credential health UI, end-to-end webhook-to-agent-to-verification
acceptance, authorized GitHub follow-up, and completion instrumentation.
Restoring the deferred identity and governance work remains necessary before a
non-bootstrap user can satisfy the final release gate.
