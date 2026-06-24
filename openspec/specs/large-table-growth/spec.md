# large-table-growth Specification

## Purpose
TBD - created by archiving change design-persistence-model. Update Purpose after archive.
## Requirements
### Requirement: High-Volume Tables Are Partition-Ready
Office Graph SHALL design high-volume tables so future time or tenant
partitioning can be added without redefining the product model.

#### Scenario: High-volume table is planned
- **WHEN** raw payload archives, source events, sync events, run events, audit
  logs, authorization decision records, revision/history records, model calls,
  tool-call logs, conversation messages, observability events, or check-run
  annotations are designed
- **THEN** the table MUST include organization, resource or source reference,
  created or received timestamp, lifecycle or retention metadata when
  applicable, and narrow typed envelope fields

#### Scenario: First customer data is not yet present
- **WHEN** the MVP schema is created before real customer volume exists
- **THEN** high-volume tables SHOULD be partition-ready but SHOULD NOT require
  day-one physical partitioning unless a follow-on implementation design
  proves an ingestion or retention need

### Requirement: Large Payloads Are Not Duplicated
Office Graph SHALL avoid duplicating large payloads across derived high-volume
records.

#### Scenario: Derived record references large content
- **WHEN** a run event, audit record, sync event, revision, model-call record,
  or tool-call record needs to refer to a large raw payload
- **THEN** it MUST reference the archive, artifact, render, or content record
  instead of copying the full payload into multiple tables

### Requirement: Operation Correlation Links High-Volume Concerns
Office Graph SHALL use operation correlation records to connect related
revisions, audit records, run events, domain events, external sync events, and
change proposals.

#### Scenario: Product action creates multiple records
- **WHEN** a human, agent, integration, or system job performs one meaningful
  action that creates revisions, audit records, run events, domain events, or
  sync events
- **THEN** those records MUST reference a shared operation or command
  correlation identifier rather than duplicating each other's payloads

#### Scenario: Operation correlation record is stored
- **WHEN** an operation correlation record is created
- **THEN** it MUST store organization, optional work scope, actor/delegation or
  agent-run context when present, external source when present, command key,
  idempotency key when applicable, request or trace identifiers, policy or
  authorization context version when applicable, reason, origin, and timestamps
  without becoming a generic event payload

#### Scenario: Operation needs a primary target
- **WHEN** an operation refers to a primary Office Graph target
- **THEN** it MAY reference a graph item or external reference directly, but it
  MUST NOT introduce a polymorphic local `resource_type` plus `resource_id`
  target model
