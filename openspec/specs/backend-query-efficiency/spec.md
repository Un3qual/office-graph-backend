# backend-query-efficiency Specification

## Purpose

Define bounded database query shapes, Ash-native collection writes,
batch-equivalent validation, stable collection ordering, and focused query
regression coverage for cardinality-sensitive backend paths.

## Requirements

### Requirement: Cardinality-Sensitive Reads Have Bounded Query Shape
Office Graph SHALL execute backend reads whose result relationships can grow with a query shape bounded by resource or relationship type rather than by returned row or child record.

#### Scenario: Projection reads scale without per-row queries
- **WHEN** an operator projection returns additional inbox rows, run-state children, or linked graph resources
- **THEN** the projection MUST batch related database reads and MUST NOT issue one query per returned row or linked resource

#### Scenario: Generated API lists scale without per-parent queries
- **WHEN** a generated GraphQL list returns multiple packets or runs
- **THEN** each resource list MUST use a bounded read and MUST NOT issue one query per returned parent record

### Requirement: Collection Writes Use Ash-Native Bulk Actions
Office Graph SHALL create packet source references, packet required checks, and run required checks with Ash-native bulk actions rather than one create action per input item.

#### Scenario: Packet links are created in bulk

- **WHEN** packet creation receives multiple source graph item IDs and verification check IDs
- **THEN** source references and packet required checks MUST be inserted in resource-level bulk batches while preserving input order in the packet command result and idempotent replay

#### Scenario: Run checks are created in bulk

- **WHEN** a packet-backed run starts with multiple required verification checks
- **THEN** run required checks MUST be inserted in a resource-level bulk batch while preserving their input order in the command result and idempotent replay

#### Scenario: Persisted packet and run child ordering survives reads and replay

- **WHEN** packet source references, packet required checks, or run required checks are read after creation or returned by an idempotent replay
- **THEN** Office Graph MUST order them by persisted input position and MUST use inserted-at and id tie-breakers when positions match, including deterministic ordering for legacy rows whose position is zero

#### Scenario: Empty collections remain valid

- **WHEN** an allowed collection write has no input records
- **THEN** the bulk helper MUST return an empty result without issuing an insert

### Requirement: Bulk Validation Is Batched And Equivalent
Office Graph SHALL preserve existing Ash action validation while batching reference lookups across records in the same bulk action.

#### Scenario: Same-scope references are loaded once per resource batch
- **WHEN** a bulk create action validates the same configured reference field across multiple changesets
- **THEN** the validator MUST load the referenced resource IDs in a batched query and MUST apply the existing existence, scope, and resource-identity checks to each changeset

#### Scenario: Run required-check contracts are loaded in batches
- **WHEN** multiple run required checks are created for one or more packet-backed runs
- **THEN** the validator MUST batch-load runs and packet required-check rows and MUST preserve the existing missing, cross-scope, non-packet-backed, and packet-mismatch errors

#### Scenario: Invalid bulk member rolls back the command
- **WHEN** any member of a packet-link or run-check bulk create fails validation or persistence
- **THEN** the enclosing domain command MUST fail without persisting a partial collection

### Requirement: Query Efficiency Has Scaling Regression Coverage
Office Graph SHALL enforce query efficiency with focused telemetry-backed tests that distinguish fixed-cost queries from cardinality-driven growth.

#### Scenario: Read scaling is regression tested
- **WHEN** a query-count test increases rows, parents, or relationship children on a guarded read surface
- **THEN** the test MUST assert that database queries do not grow by one per added record for the relevant sources

#### Scenario: Write scaling is regression tested
- **WHEN** a query-count test increases packet or run collection inputs within one bulk batch
- **THEN** the test MUST assert bounded validation reads and bulk inserts for the relevant sources

#### Scenario: Tests avoid brittle global totals
- **WHEN** fixed-cost framework, transaction, or authorization queries change
- **THEN** query-efficiency tests MUST use per-source ceilings or scaling deltas unless an exact total is itself part of the contract
