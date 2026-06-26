## ADDED Requirements

### Requirement: Transport Helpers Do Not Own Domain Behavior

Office Graph SHALL keep lifecycle, authorization, validation, operation
correlation, idempotency, audit, and revision behavior in owning domains rather
than transport-adjacent helper modules.

#### Scenario: API helper coordinates product state

- **WHEN** an API helper, resolver, controller, serializer, or frontend-facing
  adapter coordinates product state changes
- **THEN** it MUST delegate to an owning public domain command or approved Ash
  action and MUST NOT become the owner of transaction choreography or domain
  lifecycle rules

#### Scenario: Existing helper owns orchestration

- **WHEN** existing behavior is found in a transport-adjacent helper such as an
  API support module
- **THEN** stabilization work MUST either move the behavior into an owning
  domain command or document the helper as a temporary compatibility exception
  with retirement criteria

### Requirement: Composite Command Owner Is Explicit

Office Graph SHALL assign one owning command boundary for composite workflows
that cross WorkPackets, Runs, Verification, WorkGraph, Operations, and
Authorization.

#### Scenario: Packet-run-verification command is refactored

- **WHEN** the packet-run-verification flow is migrated out of transport support
  code
- **THEN** the accepted design MUST name the owning boundary and keep all
  transport surfaces calling that boundary instead of duplicating the command
  sequence

#### Scenario: New cross-domain workflow is introduced

- **WHEN** a new workflow coordinates records across multiple bounded contexts
- **THEN** the proposal MUST name the command owner, allowed dependencies,
  transaction boundary, idempotency basis, authorization contract, and
  projection read contract before implementation

### Requirement: Domain Actions Own Lifecycle Transitions

Office Graph SHALL express stable lifecycle transitions through Ash actions or
public domain commands instead of scattered internal update helpers.

#### Scenario: Lifecycle state changes

- **WHEN** a task, review finding, verification check, work packet, run,
  required check, evidence item, evidence candidate, or verification state
  changes
- **THEN** the transition MUST pass through an owning Ash action or public
  command that validates allowed state, actor authority, scope, operation
  context, and audit/revision side effects

#### Scenario: Lifecycle write requires private action

- **WHEN** a lifecycle transition must remain private to a composite command
- **THEN** the private Ash action MUST be invoked only by the owning domain
  boundary and MUST not be exposed directly through generated API surfaces

### Requirement: Domain Read Contracts Are Projection-Aware

Office Graph SHALL separate plain resource reads from policy-filtered
projection reads.

#### Scenario: Mixed projection is needed

- **WHEN** a caller needs mixed workflow state such as inbox rows, packet
  readiness, run state, evidence state, or verification outcome
- **THEN** the caller MUST use a projection contract owned by the relevant
  domain or projection boundary rather than assembling semantics from raw Ash
  reads in a transport or frontend layer
