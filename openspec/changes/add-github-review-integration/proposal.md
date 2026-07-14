## Why

Office Graph can accept manual intake and deliver durable background work, but
it cannot receive or act on the GitHub review and check signals that define the
first proving workflow. The integration must add real provider behavior without
coupling shared operations, graph storage, or software records to GitHub.

## What Changes

- Add a GitHub App adapter with installation binding, signature verification,
  raw archive ownership, durable normalization/reconciliation, replay, and
  provider failure classification.
- Add provider-neutral repositories, refs, commits, pull requests, review
  threads, review comments, and check runs with GitHub extension records and
  external references.
- Convert supported GitHub review/check events into authorized operator signals
  and typed graph relationships after authoritative reconciliation.
- Add narrow authorized outbound commands for review replies and status/check
  updates; code, branch, merge, and general automation writes remain forbidden.
- Add bounded integration-health, sync-state, and terminal-job API projections.
- Extend shared operations and durable delivery for authenticated webhook or
  service principals, organization-scoped jobs, optional governing workspace,
  and optional subject/version only for declared system operations.
- Add only the backend installation/service principals and credential metadata
  required by this adapter. Human login, SSO/SCIM, identity administration, and
  integration settings UI remain deferred.

## Capabilities

### New Capabilities

- `github-review-integration`: Owns GitHub App installation binding, webhook
  processing, reconciliation, supported review/check mappings, outbound actions,
  and provider-specific failure behavior.
- `integration-health`: Defines bounded provider sync, credential,
  installation, retry, and terminal-state projections for operator and API use.

### Modified Capabilities

- `provider-neutral-resources`: Adds concrete software proving resources shared
  by GitHub, future providers, and native Office Graph workflows.
- `durable-work-delivery`: Supports organization-scoped system jobs and optional
  subject/workspace data without weakening human-session work.
- `shared-operation-contracts`: Adds a generic authenticated system-operation
  envelope and idempotency scope used by webhooks and future agents.

## Impact

- Depends on `implement-typed-graph-relationships`.
- Adds migrations, Ash resources, a GitHub adapter package boundary, webhook and
  command routes, Oban workers, a `SecretStore` behavior, GraphQL/JSON reads and
  commands, and deterministic provider fakes.
- Satisfies the existing external-reference, adapter, sync, principal,
  credential, realtime, API, and backend-ownership requirements without changing
  their general contracts.
- Changes Operations and DurableDelivery request/resource nullability and
  authorization rules for declared system work, with backfill and isolation
  coverage.
- Adds no human identity or governance UI and does not make Office Graph a code
  execution or repository write platform.
