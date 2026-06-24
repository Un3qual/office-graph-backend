## Why

`design-ingestion-and-integrations` requires adapters to name credential and
principal inputs, but future webhook and provider implementation plans still
need a concrete source-principal contract. This change bridges ingestion,
identity, authorization, credentials, replay, and audit planning before any
integration code or migrations are generated.

## What Changes

- Define how webhook source principals, integration installation principals,
  service account principals, actor principals, and delegated authority basis
  are mapped for future integration implementation plans.
- Define how provider adapters consume principal context, credential metadata,
  source verification, allowed event/provider/resource scopes, and quarantine
  outcomes without writing graph truth tables directly.
- Define how source principal verification links to idempotency, replay,
  external sync events, operation correlation, audit records, and authorization
  decision records.
- Define planning requirements for failure states, including unverified,
  unauthorized, disabled, revoked, scope-mismatched, conflict, retryable
  failure, terminal failure, and quarantine states.
- Keep this change design-only. It does not implement Phoenix, Ash, Ecto,
  migrations, Oban jobs, provider adapters, webhook handlers, API endpoints,
  UI, SecretStore backends, or runtime integration behavior.

## Capabilities

### New Capabilities

- `integration-source-principals`: source-principal taxonomy and mapping for
  webhook sources, integration installations, service accounts, human actors,
  delegated actors, system jobs, and external executors.
- `source-verification-scope-policy`: verification, allowed source/provider
  scopes, allowed event types, credential metadata use, and quarantine/failure
  states for inbound events and provider access.
- `integration-principal-operation-linkage`: linkage between source
  principals, credential use, idempotency, replay, external sync events,
  operation correlation, authorization decisions, and audit records.
- `provider-adapter-principal-consumption`: how provider adapters consume
  source-principal contracts and emit typed provider-neutral envelopes.

### Modified Capabilities

- None. This change adds planning capabilities and cross-contract requirements
  without modifying accepted durable specs or other active change directories.

## Impact

- Affects OpenSpec planning for future webhook handlers, provider adapters,
  integration installation resources, source verification, credential-use
  authorization, replay/idempotency, sync operations, and audit evidence.
- Depends on existing identity/authentication, identity/authorization schema,
  revision/audit/soft-delete, credential-security, enterprise integration,
  and ingestion design contracts.
- Creates no application code, runtime dependencies, migrations, adapters, or
  handlers.
