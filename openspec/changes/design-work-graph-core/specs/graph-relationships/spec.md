## ADDED Requirements

### Requirement: Typed Relationship Definitions
Office Graph SHALL define graph relationships as typed edges with explicit
semantics and validation rules.

#### Scenario: Edge type is introduced
- **WHEN** a new edge type is introduced
- **THEN** its definition MUST include direction, meaning, allowed source item
  types, allowed target item types, lifecycle behavior, provenance
  requirements, authorization implications, and cycle rules

#### Scenario: Invalid edge is proposed
- **WHEN** a relationship is proposed between disallowed source and target
  types or violates the edge type lifecycle or cycle rules
- **THEN** the graph model MUST reject the relationship or require a validated
  domain action that transforms it into a valid relationship

### Requirement: Initial Relationship Families
Office Graph SHALL support relationship families needed for planning,
execution, review, verification, provenance, and external context.

#### Scenario: Core relationship families are defined
- **WHEN** the first graph relationship vocabulary is designed
- **THEN** it MUST include families for containment, decomposition,
  dependency, blocking, provenance, requirement satisfaction, verification,
  evidence, review, duplication, discussion, generated-from, produced-by,
  affected-scope, and external-reference links or explicitly defer any family
  with rationale

#### Scenario: Relationship family is specialized
- **WHEN** a department or integration needs a more specific relationship
  within a supported family
- **THEN** the relationship MUST retain the family semantics needed for common
  traversal and projection while allowing typed specialization where accepted
  by the domain model

### Requirement: Edges Do Not Grant Access
Office Graph SHALL NOT treat graph relationships as automatic access grants.

This capability is the canonical owner for the "edges do not grant access"
rule, in coordination with `design-enterprise-governance/specs/tenancy` for
tenant and scope policy.

#### Scenario: Traversal crosses scope boundary
- **WHEN** graph traversal follows an edge to an item outside the actor's
  authorized scope
- **THEN** the edge MUST NOT grant access to the target item, target details,
  artifacts, conversations, revisions, or external references

#### Scenario: Actor can view relationship but not target
- **WHEN** an actor can view that a relationship exists but cannot view the
  target item
- **THEN** the projection MUST hide the target, expose a restricted
  placeholder, or expose a policy-approved redacted summary according to
  authorization policy

### Requirement: Edge Metadata Is Narrow And Typed
Office Graph SHALL keep edge metadata narrow, typed, and focused on
relationship semantics.

#### Scenario: Relationship has metadata
- **WHEN** a graph edge needs metadata
- **THEN** the metadata MAY include typed state, confidence, asserting
  principal, source, related run, related integration event, valid time window,
  or provenance references needed to interpret the relationship

#### Scenario: Substantive fact is attached to edge
- **WHEN** an explanation, approval, finding, artifact, proof, decision, check,
  or payload would make edge metadata the primary record of a substantive fact
- **THEN** the fact MUST be represented as a graph item, domain resource,
  artifact, or evidence record linked by a typed edge

### Requirement: Relationship Lifecycle And Provenance
Office Graph SHALL preserve lifecycle and provenance expectations for created,
changed, superseded, archived, and deleted relationships.

#### Scenario: Relationship changes
- **WHEN** a graph relationship is created, changed, superseded, archived, or
  deleted
- **THEN** the graph model MUST preserve source, actor or principal when
  available, related run or integration event when available, reason when
  available, and lifecycle state sufficient for later revision and audit
  designs

#### Scenario: Related item is removed
- **WHEN** a source or target graph item is archived, deleted, merged, split,
  or superseded
- **THEN** relationship lifecycle behavior MUST remain defined so projections
  do not expose dangling or misleading edges
