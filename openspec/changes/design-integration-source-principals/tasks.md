## 1. Review And Acceptance

- [x] 1.1 Confirm this change is design-only and does not start Phoenix, Ash,
  Ecto, migration, API, frontend, webhook, Oban, SecretStore, provider adapter,
  or runtime integration code.
- [x] 1.2 Review the current ingestion adapter contracts for source identity,
  idempotency, replay, provider-neutral envelopes, credential basis, and sync
  state.
- [x] 1.3 Review identity/authentication and identity/authorization ownership
  for principals, webhook sources, integration installations, service accounts,
  external executors, and credential metadata.
- [x] 1.4 Review revision/audit ownership for operation correlation,
  authorization decisions, audit records, external sync events, and raw archive
  separation.

## 2. Capability Spec Review

- [x] 2.1 Review `integration-source-principals` requirements for source,
  installation, credential, actor, delegated, system-job, and executor
  principal roles.
- [x] 2.2 Review `source-verification-scope-policy` requirements for source
  verification, allowed provider/event/resource scopes, credential metadata,
  and quarantine/failure states.
- [x] 2.3 Review `integration-principal-operation-linkage` requirements for
  operation correlation, idempotency, replay, external sync events,
  authorization decisions, and audit linkage.
- [x] 2.4 Review `provider-adapter-principal-consumption` requirements for
  provider adapters consuming verified source-principal context without owning
  final authorization or product truth.

## 3. Future Implementation Planning Handoffs

- [x] 3.1 Feed source-principal context into future webhook handler,
  integration installation, and provider API implementation plans.
- [x] 3.2 Feed credential metadata, allowed scope, allowed capability, rotation,
  revocation, and SecretStore access requirements into future integration
  credential implementation plans.
- [x] 3.3 Feed source verification, event/provider/resource scope enforcement,
  failure, and quarantine states into future sync, support, and admin planning.
- [x] 3.4 Feed source principal context, credential basis, operation
  correlation, replay identity, and duplicate/conflict behavior into future
  idempotency and replay implementation plans.
- [x] 3.5 Feed provider adapter consumption rules into future adapter package
  planning so adapters emit provider-neutral envelopes and hints without
  bypassing authorization or domain actions.

## 4. Validation

- [x] 4.1 Run `openspec validate design-integration-source-principals --strict`.
- [x] 4.2 Run `openspec validate --changes --strict`.
- [x] 4.3 Fix any schema, delta, task-formatting, or validation issues
  reported by OpenSpec.
