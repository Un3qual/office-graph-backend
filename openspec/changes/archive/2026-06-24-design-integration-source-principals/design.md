## Context

The ingestion design already requires provider adapters to emit source
identity, idempotency basis, credential or webhook principal basis, and
operation context input. The identity designs already define principals for
humans, agents, service accounts, integration installations, webhook sources,
external executors, and system jobs, and they define secret-free credential
metadata. The revision/audit design already separates operation correlation,
external sync events, authorization decision records, durable audit records,
raw archives, and revisions.

The remaining planning gap is how future integration implementation work ties
these contracts together for webhooks and provider APIs. Without a shared
source-principal contract, provider adapters could each invent different
rules for webhook verification, installation authority, credential selection,
allowed event scopes, replay, quarantine, and audit linkage.

## Goals / Non-Goals

**Goals:**

- Define the source-principal contract future webhook handlers and provider
  adapters must consume.
- Distinguish webhook source principal, integration installation principal,
  service account principal, actor principal, delegated principal, system job,
  and external executor roles in one integration operation.
- Require credential metadata and allowed scope/capability rows to be the
  product-data basis for credential authorization without exposing secrets.
- Require source verification, allowed event/provider/resource scopes,
  failure/quarantine states, idempotency, replay, external sync events,
  operation correlation, authorization decisions, and audit records to link
  coherently.
- Preserve provider-neutral adapter output and domain-action routing.

**Non-Goals:**

- No product code, migrations, webhook handlers, Oban jobs, provider adapters,
  API endpoints, UI, SecretStore provider, local identity-lab fixture, or
  runtime credential implementation.
- No final column list for integration installation, webhook source,
  credential metadata, sync event, audit, or operation tables.
- No final provider-specific GitHub, Sentry, Slack, Teams, Jira, Figma,
  finance, document, or CI adapter behavior.
- No broad changes to existing active change directories.

## Decisions

### 1. Treat source principals as an operation context, not a single actor

Future integration implementation plans should model source principal context
as a set of related roles for one operation:

- source principal: the verified inbound webhook source, polling source,
  manual source, provider API source, system job, or external executor
- installation principal: the integration installation authorized to receive
  events or call provider APIs for an organization or scope
- credential principal: the service account or installation principal whose
  credential metadata authorizes secret access or provider calls
- actor principal: the human, agent, system job, or provider actor associated
  with the event when known
- delegated principal or authority basis: the delegator, work packet, run,
  approval, policy, or provider trust relationship that explains why the
  source may act

This avoids pretending that a webhook delivery, integration installation,
provider user, and Office Graph service account are one actor. Operation
correlation, authorization decisions, sync events, and audit records can then
reference the correct role without duplicating payloads.

Alternatives considered:

- **Single integration actor:** simpler, but loses who sent the event, which
  installation was authorized, which credential was used, and which provider
  actor caused the change.
- **Provider-specific actor models only:** flexible per adapter, but prevents
  shared authorization, replay, audit, and support behavior.

### 2. Use credential metadata as the authorization input, not raw secret data

Future implementation plans should require adapters and handlers to work with
credential metadata references, lifecycle state, owner principal, allowed
scopes, allowed capabilities, provider, fingerprint, rotation/revocation
state, last-use linkage, sensitivity, and operation/audit references. Secret
values remain behind the SecretStore boundary and are retrieved only after
authorization succeeds.

Credential metadata should describe whether a credential supports inbound
verification, provider reads, provider writes, webhook signing, API polling,
external executor callbacks, or model/tool calls. The same credential may be
usable by multiple source roles only when normalized allowed scope/capability
facts make that explicit.

Alternatives considered:

- **Adapter-local credential config:** fast per provider, but weak for
  customer administration, audit, rotation, revocation, and external write
  controls.
- **Store scopes in opaque credential metadata JSON:** flexible, but conflicts
  with queryable authorization, audit, and export requirements.

### 3. Verify source, event, provider, and resource scope before normalization

Inbound events should enter a narrow pre-normalization path that can archive
the raw payload or delivery metadata, identify the claimed source, verify the
signature/token/secret/fingerprint or provider proof, and check allowed event
types and scopes. Only verified and allowed inputs can proceed into provider
adapter normalization. Unverified or unauthorized inputs must not be silently
accepted as normal events.

Verification failures should preserve enough traceability for operations and
security review while respecting secret and payload visibility. The shared
failure vocabulary should cover unverified source, unknown source, disabled
source, revoked credential, expired credential, invalid signature, replay
window violation, provider mismatch, tenant mismatch, event type denied,
scope mismatch, sensitivity-policy denial, conflict, retryable failure,
terminal failure, and quarantine.

Alternatives considered:

- **Let adapters verify after normalization:** adapters get full flexibility,
  but unsafe payloads can reach provider-neutral domain logic before source
  authority is known.
- **Drop failed events without records:** reduces storage, but breaks replay,
  support, incident investigation, and customer-facing audit posture.

### 4. Link replay and idempotency to source principal context

Idempotency keys and replay identities must include source identity plus the
source-principal context relevant to the operation. A provider delivery id is
not enough when the same provider event can arrive through different
installations, credentials, tenants, scopes, or replay jobs.

Future implementation plans should preserve:

- raw archive or delivery reference
- source principal and installation principal
- credential metadata reference when credentialed verification or provider
  access was used
- source event id, delivery id, cursor, digest, sequence, timestamp, and
  replay identity when available
- operation correlation identifier
- external sync event identifier and state
- duplicate, skipped, applied, pending, failed, or quarantined outcome

This lets retries avoid duplicate truth-table mutations and lets replay
explain whether it was driven by debugging, recovery, adapter upgrade, support,
or security review.

Alternatives considered:

- **Provider idempotency only:** works for some webhook providers, but misses
  Office Graph scope, credential, replay, and operation authority.
- **Operation idempotency only:** deduplicates commands, but cannot explain
  source-level delivery, provider cursor, or replay behavior.

### 5. Keep adapters principal-aware but not policy-owning

Provider adapters should consume a verified source-principal context and emit
typed provider-neutral envelopes. The envelope should identify the principal
and credential basis required for downstream authorization and audit, but the
adapter should not decide final Office Graph truth, bypass authorization, or
write graph truth tables directly.

Adapters may provide provider-specific validation hints, conflict hints,
resource references, event scopes, actor hints, and credential requirements.
Domain actions, authorization policy, change proposal validation, sync state,
and audit boundaries decide what becomes durable product truth.

Alternatives considered:

- **Adapters write domain records directly:** reduces plumbing in the first
  adapter, but duplicates policy and makes replay unsafe.
- **Adapters ignore principal context:** keeps envelopes small, but forces
  downstream code to reconstruct provenance and credential authority later.

## Risks / Trade-offs

- Source principal context may feel verbose for the first webhook provider ->
  keep the required contract small but explicit, and let provider-specific
  details live behind adapter-local typed extensions that still map back to the
  shared fields.
- Quarantining failed events creates operational records for malicious or noisy
  traffic -> record only the minimum traceable metadata needed for security,
  support, replay, and policy, with payload retention and redaction controlled
  by existing raw archive and audit rules.
- Provider APIs expose inconsistent event, actor, installation, and credential
  concepts -> normalize only the shared authority and traceability fields,
  and keep provider-specific facts as hints until promoted into typed product
  records.
- Adding operation/audit linkage too early can overconstrain migrations ->
  keep this change at the contract and planning level; implementation changes
  can choose concrete table shapes owned by the identity, audit, ingestion,
  and persistence designs.

## Open Questions

- Which initial provider integration should prove the full source-principal
  path after manual intake: GitHub, Sentry, Slack/Teams, CI, or another source?
- Which failure/quarantine states require customer-visible admin UI in the
  first integration implementation versus internal support/operator visibility?
- Which credential-use actions are durable audit events by default versus
  authorization decision records only?
