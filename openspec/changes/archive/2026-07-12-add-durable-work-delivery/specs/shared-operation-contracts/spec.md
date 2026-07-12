## ADDED Requirements

### Requirement: Durable Delivery Preserves Operation And Causation

Office Graph SHALL correlate domain events and durable jobs with the operation
that requested them and with a causal event when one exists.

#### Scenario: Command records an event and job

- **WHEN** a meaningful operation commits product state that requires durable
  delivery
- **THEN** its event and job MUST reference that operation, use the same tenant
  scope, and commit or roll back atomically with the owning transaction

#### Scenario: Event causes later work

- **WHEN** a dispatched event requests another operation or durable job
- **THEN** the later record MUST preserve the causation event identity without
  merging separate operations or duplicating their data

