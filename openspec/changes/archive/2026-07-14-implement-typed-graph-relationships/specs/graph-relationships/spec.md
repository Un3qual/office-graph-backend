## ADDED Requirements

### Requirement: Relationship Mutations Use Canonical Commands
Office Graph SHALL create, supersede, archive, and restore graph relationships
only through named WorkGraph commands that reference a canonical relationship
definition.

#### Scenario: Canonical relationship is created
- **WHEN** an authorized command supplies compatible endpoints, governing
  scope, provenance, operation, and expected lifecycle data
- **THEN** Office Graph MUST create one definition-backed relationship and
  preserve its actor, operation, scope, validity, and optional run or integration
  provenance

#### Scenario: Adapter or agent requests an edge
- **WHEN** an integration or agent proposes a graph relationship
- **THEN** it MUST use a WorkGraph command or change proposal and MUST NOT insert
  the relationship resource directly

#### Scenario: Cross-workspace relationship is requested
- **WHEN** endpoints belong to different workspaces
- **THEN** Office Graph MUST require the named cross-workspace action and MUST
  record the governing relationship scope without granting target access

### Requirement: Cycle Enforcement Is Transactional
Office Graph SHALL enforce each relationship definition's cycle policy against
the committed graph and concurrent contenders.

#### Scenario: Proposed edge closes a forbidden cycle
- **WHEN** bounded traversal from the proposed target reaches the proposed
  source for a definition that forbids cycles
- **THEN** the command MUST reject the edge and preserve existing graph state

#### Scenario: Concurrent edges jointly create a cycle
- **WHEN** two individually valid concurrent commands would form a forbidden
  cycle if both committed
- **THEN** serialization MUST allow at most one command to commit

#### Scenario: Relationship family permits cycles
- **WHEN** a definition explicitly permits cycles
- **THEN** the command MUST NOT run the forbidden-cycle traversal for that
  definition

### Requirement: Relationship Lifecycle Preserves History
Office Graph SHALL retain superseded, archived, and tombstoned relationship
history with provenance sufficient for audit and revision reconstruction.

#### Scenario: Relationship is superseded
- **WHEN** a named command replaces an active relationship
- **THEN** the old relationship MUST remain addressable as superseded and link
  to the replacement and operation

#### Scenario: Incident item is restored
- **WHEN** a relationship endpoint is restored after deletion
- **THEN** the prior edge MUST remain inactive unless its definition permits
  restoration and policy authorizes an explicit restore command
