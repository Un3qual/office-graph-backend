## ADDED Requirements

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
proposed graph changes.

#### Scenario: Product action creates multiple records
- **WHEN** a human, agent, integration, or system job performs one meaningful
  action that creates revisions, audit records, run events, domain events, or
  sync events
- **THEN** those records MUST reference a shared operation or command
  correlation identifier rather than duplicating each other's payloads
