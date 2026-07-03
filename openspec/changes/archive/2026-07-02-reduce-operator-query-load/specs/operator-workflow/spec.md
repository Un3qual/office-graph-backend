## ADDED Requirements

### Requirement: Operator Workflow Projection Reads Are Bounded
Office Graph SHALL assemble operator workflow projection reads with batched
database access so query count stays bounded as inbox rows, applied operations,
graph links, packet links, runs, evidence, and verification records grow.

#### Scenario: Inbox rows batch related records
- **WHEN** GraphQL or JSON API reads an operator workflow inbox containing
  multiple normalized intake events
- **THEN** the projection MUST load proposed changes, audit records, revision
  records, typed graph resources, graph relationships, packet source links,
  packet required-check links, and linked runs through batched reads rather
  than one database query per inbox row or linked graph resource

#### Scenario: Item detail uses shared projection assembly
- **WHEN** GraphQL or JSON API reads one operator workflow item by normalized
  intake event id
- **THEN** the item detail MUST use the same projection assembly contract as
  inbox rows with a one-event input so transport parity and authorization
  filtering cannot drift

#### Scenario: Request context is not bootstrapped repeatedly
- **WHEN** an operator workflow read is handled through a server-controlled
  request path that already established a trusted session context
- **THEN** the projection read MUST use that trusted session context instead
  of re-running local owner bootstrap or accepting client-supplied session
  context maps

#### Scenario: Local owner bootstrap remains request scoped
- **WHEN** local API owner bootstrap is enabled for a request path without a
  server-installed trusted context
- **THEN** the implementation MUST run the explicit bootstrap path for that
  request rather than storing VM-lifetime authorization or session context that
  can outlive identity, tenancy, or policy row changes

#### Scenario: Authorization checks reuse trusted session facts
- **WHEN** a projection read authorizes an action whose capability is already
  present in the trusted session context for the current organization and
  workspace
- **THEN** authorization MUST evaluate the trusted session facts without
  re-querying capability, role-capability, role, and role-assignment rows for
  every projection subread

#### Scenario: Query-count regression is covered
- **WHEN** operator workflow projection tests create additional applied inbox
  rows and linked graph resources
- **THEN** the tests MUST prove the number of SQL queries does not grow by a
  per-row or per-resource N+1 pattern for the known projection hotspots

#### Scenario: Query shape remains part of ongoing review
- **WHEN** future work adds or changes operator workflow projection reads,
  transport fields, background refreshes, or linked resource traversal
- **THEN** reviewers and implementers MUST look for opportunities to batch
  related records, reuse loaded projection data, avoid repeated authorization
  or bootstrap reads, and add focused query-count coverage when the change can
  grow with rows, graph links, runs, evidence, or integration records
