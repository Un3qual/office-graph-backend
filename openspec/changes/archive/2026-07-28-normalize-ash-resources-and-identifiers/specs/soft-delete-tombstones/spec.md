## MODIFIED Requirements

### Requirement: Tombstone Metadata
Office Graph SHALL keep common deletion metadata on the mutable resource that
owns the lifecycle and SHALL use a domain-specific one-to-one deleted-state
resource only when richer metadata cannot reasonably live on that resource.
A generic polymorphic tombstone table keyed by resource type and resource
identifier is prohibited.

#### Scenario: Mutable record is soft-deleted
- **WHEN** a mutable owning resource is removed from normal use
- **THEN** its own table MUST preserve deletion time, deletion actor or source, operation correlation, reason when available, lifecycle state, and restore or purge eligibility

#### Scenario: Deleted record needs rich deletion state
- **WHEN** deletion needs legal-hold state, redaction status, external-provider reconciliation, restore-as-new linkage, purge state, or detailed rationale beyond the owning row's common fields
- **THEN** the owning context MUST use typed columns or a domain-specific related resource with a concrete foreign key

#### Scenario: Generic tombstone relationship is proposed
- **WHEN** a design proposes `resource_type` and `resource_id` polymorphism for deletion state
- **THEN** verification MUST reject it and require lifecycle ownership by the concrete resource or owning context

#### Scenario: Graph relationship is deleted
- **WHEN** a graph relationship is tombstoned
- **THEN** `graph_relationships` MUST preserve its deletion metadata directly and projections MUST derive deletion state without a generic tombstone join
