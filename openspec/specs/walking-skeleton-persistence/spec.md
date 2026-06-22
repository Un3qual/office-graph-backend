# walking-skeleton-persistence Specification

## Purpose
TBD - created by archiving change first-backend-walking-skeleton. Update Purpose after archive.
## Requirements
### Requirement: Minimal Walking Skeleton Schema
Office Graph SHALL persist the smallest relational schema that can prove the
first executable work loop.

#### Scenario: First migrations are created
- **WHEN** the first backend migrations are implemented
- **THEN** they MUST include only the organization, workspace, initiative,
  principal, role assignment, graph identity, graph relationship, raw archive,
  signal, task, review finding, verification check, evidence, artifact,
  operation correlation, revision, audit, proposed change, work packet, run,
  run event, and verification result records needed to execute and trace the
  walking skeleton

#### Scenario: Deferred schema is encountered
- **WHEN** a table family is useful but not required for the walking skeleton
- **THEN** it MUST remain deferred or skeletal rather than becoming a full
  implementation of work packets, runs, provider integrations, projections,
  rich text editor internals, or agent runtime behavior

### Requirement: Graph Identity Transaction Invariant
Office Graph SHALL create graph identity and typed domain records atomically.

#### Scenario: Graph-addressable record is created
- **WHEN** a signal, task, review finding, verification check, evidence item,
  artifact, work packet, or other graph-addressable resource is created
- **THEN** the graph identity record and typed resource record MUST be created
  in the same database transaction so neither becomes visible without the
  other

### Requirement: Identity And Authorization Seed Records
Office Graph SHALL create enough identity and authorization data to run the
walking skeleton safely.

#### Scenario: Empty development or test system is bootstrapped
- **WHEN** the local bootstrap path runs against an empty system
- **THEN** it MUST create one organization, one workspace, one initiative, one
  owner principal/profile, one initial role assignment, an initial policy
  version or policy anchor, and enough capability records to authorize the
  walking-skeleton actions

### Requirement: Rich Text V1 Persistence In Skeleton
Office Graph SHALL use the narrowed portable rich text model for skeleton body
fields.

#### Scenario: Skeleton body text is stored
- **WHEN** task descriptions, review finding bodies, evidence notes, or
  verification check descriptions are persisted
- **THEN** canonical content MUST use normalized rich text documents, current
  blocks, basic marks/references, whole-document semantic revisions, and
  derived plain text where needed rather than canonical Lexical JSON, HTML, or
  Markdown payloads

### Requirement: Operation, Revision, And Audit Spine
Office Graph SHALL link meaningful walking-skeleton writes through operation
correlation, typed revision records, and audit records where required.

#### Scenario: Sensitive or state-changing action occurs
- **WHEN** bootstrap, proposed-change application, verification completion, or
  another policy-sensitive walking-skeleton action changes product state
- **THEN** the action MUST record operation correlation and the relevant typed
  revision, authorization decision, or audit record needed to explain the
  change without duplicating large payloads across record families

### Requirement: Raw Archive And Idempotency Storage
Office Graph SHALL persist manual intake inputs through the future adapter
storage shape.

#### Scenario: Manual intake is received
- **WHEN** a user submits pasted or manually entered intake content
- **THEN** Office Graph MUST store a raw archive reference, normalized event
  identity, source identity, replay/idempotency key, operation correlation,
  and duplicate-handling outcome before applying durable graph changes

### Requirement: Ash Resource Ownership For Stable Loop Resources
Office Graph SHALL model stable walking-loop product records as Ash resources
owned by the WorkGraph bounded context.

#### Scenario: Stable graph-backed loop resource is implemented
- **WHEN** signal, task, review finding, verification check, artifact, evidence
  item, or verification result persistence is implemented
- **THEN** the typed product record MUST have an Ash resource backed by its
  owning Postgres table, registered in the WorkGraph Ash domain, and covered by
  authorization-aware Ash actions

