# provider-adapter-contract Specification

## Purpose
TBD - created by archiving change design-ingestion-and-integrations. Update Purpose after archive.
## Requirements
### Requirement: Provider Adapter Output Contract
Office Graph provider adapters SHALL output typed provider-neutral envelopes
instead of writing Office Graph domain tables directly.

#### Scenario: Adapter normalizes input
- **WHEN** a manual, webhook, API, model, or tool adapter processes input
- **THEN** it MUST output source identity, normalized event kind, raw archive
  reference, idempotency basis, intended domain action, affected external
  references, required credential or webhook principal, and operation context
  input

#### Scenario: Adapter sees provider resource
- **WHEN** an adapter recognizes a repository, pull request, review comment,
  check run, observability issue, document, asset, or other provider object
- **THEN** it MUST identify the provider-neutral resource kind and external
  reference information without deciding final Office Graph truth by itself

### Requirement: Adapter Credentials Are Explicit
Provider adapters SHALL identify the principal and credential basis for reads,
writes, and webhooks.

#### Scenario: Adapter needs credentialed access
- **WHEN** an adapter reads provider state, receives a webhook, or writes to an
  external provider
- **THEN** the adapter output MUST identify the service account, integration
  installation, webhook source, credential metadata, or actor principal basis
  required for authorization and audit
