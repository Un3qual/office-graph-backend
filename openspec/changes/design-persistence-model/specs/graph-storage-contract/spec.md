## ADDED Requirements

### Requirement: Graph Identity With Typed Resources
Office Graph SHALL use shared graph identity for addressability while keeping
business meaning in typed resources.

#### Scenario: Addressable domain record is stored
- **WHEN** a signal, task, question, decision, check, evidence item, artifact,
  run, work packet, conversation, document section, or plan section becomes
  graph-addressable
- **THEN** it MUST have a graph identity record for traversal and projection
  and a typed resource record for fields, validations, lifecycle, and domain
  actions when the concept has business behavior

### Requirement: Typed Relationships
Office Graph SHALL persist graph edges as typed relationship records rather
than opaque edge payloads.

#### Scenario: Relationship is created
- **WHEN** two graph-addressable resources are linked for dependency,
  blocking, evidence, provenance, review, conversation, or verification
- **THEN** the relationship MUST store source, target, relationship type,
  organization scope, lifecycle state, provenance, and narrow typed metadata
  sufficient for authorization-filtered traversal

#### Scenario: Relationship needs substantive facts
- **WHEN** an edge would need to store an explanation, approval, finding,
  artifact, decision, evidence, or large payload
- **THEN** Office Graph MUST model that fact as a typed graph item, artifact,
  evidence record, or external reference linked by a typed relationship

### Requirement: Graph Projections Are Query Results
Office Graph SHALL treat graph projections as authorization-filtered query
results over scoped graph data, not as tenants or access-granting containers.

#### Scenario: Projection spans graph context
- **WHEN** a projection includes nodes, edges, artifacts, conversations,
  external references, revisions, summaries, or counts
- **THEN** every included record MUST remain governed by its own tenant, scope,
  classification, and authorization facts
