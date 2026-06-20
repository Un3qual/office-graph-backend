## ADDED Requirements

### Requirement: Operation Context Propagation
Meaningful durable actions SHALL receive or create an operation context,
including writes, external syncs, agent actions, approvals, denials, revisions,
audit events, run events, domain events, tombstones, raw archive links, and
proposed graph changes.

#### Scenario: A human submits a command
- **WHEN** an API request performs a durable write
- **THEN** the entrypoint builds an operation context with organization, scope,
  actor, command key, request/trace identifiers, authority basis, and source
  before calling domain code

#### Scenario: An agent performs an action
- **WHEN** an agent runtime tool performs a durable write or external action
- **THEN** the operation context includes the agent run, delegator or authority
  basis, tool/integration scope, and autonomy-policy context when applicable

### Requirement: Concern Separation
Historical and trace records MUST remain separate typed record families linked
by operation correlation where appropriate, including revisions, audit records,
authorization decisions, domain events, run events, external sync events, raw
archives, tombstones, and operation correlation records.

#### Scenario: A sensitive write changes product state
- **WHEN** one command changes product state and requires audit
- **THEN** it may create a typed revision, audit event, authorization decision,
  domain event, and operation record without using any one record family as a
  substitute for the others

#### Scenario: A raw provider payload is archived
- **WHEN** a webhook or provider API response is stored for replay or
  provenance
- **THEN** the raw archive stores the original payload and typed extracted
  product records store queryable domain fields separately

### Requirement: Concrete References
Shared operation contracts MUST use concrete local references, typed target
rows, or typed envelopes rather than polymorphic local `type` plus `id` links
for Office Graph-owned resources.

#### Scenario: An audit event references targets
- **WHEN** an audit event records affected resources
- **THEN** target rows use allowed concrete target references or typed target
  envelopes defined by the audit boundary

#### Scenario: An operation references a primary object
- **WHEN** an operation correlation record identifies its primary graph or
  domain object
- **THEN** it uses the approved graph identity or concrete domain reference
  instead of an unbounded local polymorphic reference

### Requirement: Shared Contract Ownership
Cross-context operation contracts SHALL be owned by explicit shared contexts or
library-ready primitives and SHALL expose stable functions, structs,
behaviours, or event APIs for callers.

#### Scenario: A new context needs revisions
- **WHEN** a product context introduces a mutable aggregate with revision
  requirements
- **THEN** it uses the approved revision contract instead of inventing an
  unrelated history table pattern

#### Scenario: A new context emits domain events
- **WHEN** a context emits events consumed by other contexts
- **THEN** it uses the approved domain-event contract and includes operation
  correlation when the event comes from a meaningful command
