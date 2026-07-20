## Context

Manual intake already proves archive, normalization, proposal, packet, run,
evidence, and verification behavior. DurableDelivery owns typed domain events,
Oban jobs, retry classification, and projection invalidations, but current event
and operation requests require a workspace, human principal/session, and
subject version. GitHub webhooks and reconciliation jobs need authenticated
system authority that is not a human session.

The change depends on canonical typed relationships. Identity/governance
administration is deferred; only provider service/webhook principals and
credential metadata required by this integration may be added.

## Goals / Non-Goals

**Goals:**

- Verify and ingest GitHub App webhooks with replay-safe durable processing.
- Reconcile provider-neutral software resources from authoritative GitHub state.
- Produce Office Graph signals, external references, and typed relationships.
- Support narrow authorized review replies and status/check updates.
- Expose safe integration health and terminal/configuration states.
- Generalize system operations for later AgentRuntime use without weakening
  human-session commands.

**Non-Goals:**

- No commits, branch writes, merges, code execution, or general GitHub bot.
- No human login, OIDC/SAML/SCIM, role administration, or settings UI.
- No secret values in product resources or API payloads.
- No provider-generic plugin marketplace.
- No dependency on live GitHub for normal tests or verification.

## Decisions

### 1. GitHub is an adapter over provider-neutral software resources

Add provider-neutral repository, ref, commit, pull request, review thread,
review comment, and check run resources. GitHub extension resources retain
provider-only state, while external references own GitHub object identity and
URLs.

Storing GitHub payloads directly as graph truth was rejected because it blocks
future GitLab/native records and weakens typed lifecycle and authorization.

### 2. Valid webhooks enqueue reconciliation instead of trusting partial payloads

The webhook controller verifies the signature, resolves an installation
binding, creates a system operation, archives the valid body, and enqueues a
unique delivery job before returning. Normalization may create immediate
receipts, but authoritative resource updates use adapter reads when the webhook
is partial or out of order.

Applying every webhook payload directly was rejected because event shapes and
ordering differ and can overwrite newer provider state.

### 3. Installation binding is a narrow authorized backend command

GraphQL and JSON commands bind installation ID, organization, optional
workspace, service principal, permission snapshot, and credential references.
The current local owner may invoke them within its assigned scope during
development; an organization-scoped binding requires an organization-scoped
capability assignment. No unauthenticated callback or settings UI creates
product authority.

Automatic installation acceptance was rejected because an external installation
event cannot choose an Office Graph tenant or credential authority safely.

### 4. Secrets resolve through a narrow SecretStore behavior

Credential resources store reference, kind, lifecycle, scope, and rotation
metadata only. A `SecretStore` behavior resolves webhook and private-key material
through a deterministic test adapter and environment-backed development adapter.

Putting secrets in Ash resources was rejected. Selecting a managed production
secret vendor was deferred with identity/governance administration.

### 5. System operations are generic and fail closed

Introduce a separate system-operation request authenticated by a service or
webhook principal. Organization is required; workspace and subject/version are
optional only for declared organization-scoped job kinds. Authority basis,
credential reference, causation, and idempotency scope are required.

Human operation constructors retain principal, session, workspace, and normal
subject requirements. A single permissive request struct was rejected because
it would make browser/API validation fail open.

### 6. Provider delivery and object identity are separate

GitHub delivery ID deduplicates webhook receipt. Installation and provider
object IDs/versions deduplicate reconciliation. Outbound action keys deduplicate
external writes. Sync state records received, archived, normalized, reconciled,
duplicate, skipped, retryable, terminal, and replayed outcomes.

One global idempotency key was rejected because deliveries, objects, and
commands have different replay semantics.

### 7. Outbound actions are explicit commands

Review reply and status/check update commands validate authorization,
installation permissions, credential scope, expected provider version, and
idempotency before enqueue. Workers record provider response identity and
classified outcome.

Exposing the GitHub client to agents or resolvers was rejected because it would
bypass operation, authorization, credential, and retry contracts.

### 8. Health is a bounded projection, not raw job/payload access

Health reads show installation lifecycle, permission/configuration posture,
last successful sync, bounded retry/terminal summaries, and safe remediation
codes. They omit secrets, raw payloads, exception strings, and cross-tenant
existence.

## Risks / Trade-offs

- GitHub's webhook and API schemas can drift → isolate decoding in the adapter,
  retain valid raw archives, and use contract fixtures.
- Reconciliation increases API usage → coalesce jobs by installation/object,
  honor rate-limit reset, and batch reads.
- System-operation nullability can weaken invariants → use a distinct request
  type and table constraints keyed by operation kind.
- Installation binding without settings UI is operationally awkward → provide
  narrow supported commands and deterministic local setup documentation.
- A GitHub-first implementation can leak provider assumptions → prove a
  non-GitHub system job and keep shared modules free of GitHub names/types.

## Migration Plan

1. Add generic system-operation fields/constraints and migrate existing human
   operations/events without changing their required data.
2. Add provider-neutral software and GitHub installation/extension resources.
3. Add secret-store behavior, installation binding, and service principals.
4. Add verified webhook receipt, durable delivery, normalization, and
   reconciliation in event-family slices.
5. Add external references, typed relationships, signals, outbound commands,
   health reads, and realtime invalidations.

Rollback disables webhook/outbound routes and workers first, waits for or
terminalizes owned jobs, removes GitHub/provider resources only when no retained
history depends on them, and restores strict system-operation constraints only
after proving no organization-scoped operation remains.

## Open Questions

None. Hosted secret infrastructure and human installation UI remain explicitly
deferred rather than unresolved.
