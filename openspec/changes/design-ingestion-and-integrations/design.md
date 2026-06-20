## Context

The first backend walking skeleton starts with a manual intake signal. That is
intentional: manual pasted intake proves the same archive, normalization,
idempotency, signal creation, review finding, and evidence path that future
webhooks use without making the first demo depend on GitHub, Sentry, Slack, or
another provider integration.

## Goals / Non-Goals

**Goals:**

- Define manual pasted intake as the first adapter.
- Separate raw payload archive, normalized event, Office Graph signal,
  provider-neutral resource, review finding, evidence, and sync event.
- Define idempotency, replay, duplicate handling, retry, and out-of-order
  behavior.
- Define provider-neutral adapter output.
- Preserve future provider package boundaries.

**Non-Goals:**

- No Phoenix, Ash, Ecto, Oban, API, UI, webhook, or provider implementation.
- No final GitHub, Sentry, Slack, Teams, Jira, Figma, finance, or document
  adapter.
- No direct graph mutation from adapters.
- No credential secret storage implementation.

## Decisions

### 1. Start with manual pasted intake

Manual intake is the first adapter. A user can paste a messy report, review
comment, bug description, meeting note, CI excerpt, or external text into
Office Graph. The adapter archives the submitted input, normalizes it into an
internal event envelope, and routes it through the same signal/domain-action
path that future webhooks will use.

Manual intake should still have source identity, idempotency basis, operation
context, actor principal, raw archive reference, normalized event kind, and
intended domain action. It is not an ungoverned shortcut.

### 2. Keep archive, event, signal, resource, finding, evidence, and sync separate

The ingestion path distinguishes:

- raw payload archive: original pasted, webhook, API, model, or tool payload
- normalized external event: provider-neutral envelope derived from the raw
  payload
- signal: Office Graph work signal that can enter the graph
- provider-neutral resource: durable product/resource record when the concept
  deserves first-class lifecycle
- review finding: actionable work item from a review or analysis signal
- evidence: proof or counterproof attached to checks, tasks, runs, or findings
- sync event: durable trace of ingestion/replay state and provider interaction

Adapters produce typed outputs. Domain actions decide what becomes truth.

### 3. Require idempotency and replay from the start

Every adapter output needs a replay identity and source identity. Duplicate
handling must be deterministic: reject exact duplicates, merge compatible
updates through domain actions, or create a conflict/review state when the
event cannot be safely applied. Retries must not create duplicate truth-table
mutations.

Out-of-order events should be accepted only when the owning domain can merge
them safely. Otherwise they remain pending, skipped, or failed with an
explainable sync state.

### 4. Define provider adapter output

Adapters output typed provider-neutral envelopes containing:

- source identity
- normalized event kind
- raw archive reference
- idempotency basis
- intended domain action
- affected external references
- affected provider-neutral resources when known
- required credential, webhook source, service account, or actor principal
- operation context input
- validation warnings or conflict hints

Adapters do not write graph truth tables directly and do not bypass
authorization or proposed-change validation.

### 5. Use a small sync state machine

The first sync state vocabulary should cover received, archived, normalized,
validated, applied, duplicate, skipped, pending dependency, failed retryable,
failed terminal, and replayed. Future provider packages may add provider-local
states only when they map back to this shared vocabulary for operations and
support.

## Handoff To Other Changes

- `design-persistence-model` owns raw archive and external reference storage
  rules.
- `design-proposed-graph-changes` owns proposed mutation validation and
  application.
- `design-code-organization-and-boundaries` owns adapter module and behaviour
  placement.
- `design-identity-and-authentication` owns webhook/source principal and
  integration credential mechanics.
