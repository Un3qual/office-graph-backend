## ADDED Requirements

### Requirement: Operation Correlation Record
Office Graph SHALL represent each meaningful command or externally observed
action with a narrow operation correlation record.

#### Scenario: Operation is created
- **WHEN** a human, agent, integration, webhook source, service account, or
  system job performs a meaningful command or externally observed action
- **THEN** Office Graph MUST be able to record organization, optional
  workspace scope, optional initiative scope, optional workstream scope, actor
  principal when present, delegated principal when present, agent run when
  present, service account or external source when present, command key,
  idempotency key when applicable, request or trace identifiers, authority
  basis, reason, source surface, primary graph item or external reference when
  present, and timestamps

#### Scenario: Operation has a primary target
- **WHEN** an operation has a primary Office Graph target
- **THEN** the operation MAY reference a graph item or external reference
  directly but MUST NOT introduce a polymorphic local `resource_type` plus
  `resource_id` target model

### Requirement: Correlated Records Reference Operations
Office Graph SHALL link related revisions, audit records, authorization
decisions, run events, external sync events, domain events, approvals, and
change proposals through operation correlation.

#### Scenario: One action writes several record families
- **WHEN** one action changes product state, requires audit, evaluates policy,
  records runtime execution, syncs provider state, or creates a change proposal
- **THEN** the related typed records MUST be able to reference the same
  operation correlation identifier without duplicating each other's payloads

### Requirement: Operation Idempotency And Causation
Office Graph SHALL support idempotency and causal tracing for commands,
webhooks, sync replay, and agent actions.

#### Scenario: Idempotent command is retried
- **WHEN** a command, webhook, sync event, or agent action is retried with the
  same idempotency basis
- **THEN** Office Graph MUST be able to identify the existing operation or
  safely reject the duplicate according to the owning domain's rules

#### Scenario: Operation is caused by another operation
- **WHEN** an operation is triggered by a previous run event, sync event,
  approval, change proposal, or domain event
- **THEN** Office Graph MUST be able to preserve causal references without
  merging the two operations into one payload
