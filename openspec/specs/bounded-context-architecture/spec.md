# bounded-context-architecture Specification

## Purpose
TBD - created by archiving change design-code-organization-and-boundaries. Update Purpose after archive.
## Requirements
### Requirement: Modular Monolith Baseline
The backend SHALL begin as one Phoenix API application organized as a modular
monolith with explicit bounded contexts rather than as an umbrella application,
multiple services, or separate Hex packages.

#### Scenario: New backend application is planned
- **WHEN** implementation planning defines the first backend application shape
- **THEN** the plan uses one Phoenix API application with internal bounded
  contexts as the default structure

#### Scenario: Early service split is proposed
- **WHEN** a design proposes an umbrella app, microservice split, or separate
  package split for MVP
- **THEN** the design records the specific requirement that overrides the
  modular-monolith baseline

### Requirement: Context Ownership
Every durable resource SHALL have one owning bounded context, and the same
ownership rule applies to commands, queries, domain events, operation
contracts, and policy surfaces.

#### Scenario: A new resource is added
- **WHEN** a future implementation plan introduces a durable resource
- **THEN** the plan identifies the owning context and the public APIs other
  contexts may use

#### Scenario: A workflow crosses contexts
- **WHEN** a command mutates or reads records owned by multiple contexts
- **THEN** the command is represented as orchestration over public context
  interfaces rather than direct access to private modules

### Requirement: Context Dependency Direction
Bounded contexts MUST avoid cyclic dependencies and MUST depend on narrower
public contracts rather than private modules from peer contexts.

#### Scenario: A context imports another context
- **WHEN** a module in one context calls another context
- **THEN** the dependency targets an exported public module, behaviour, query
  interface, or event contract

#### Scenario: A dependency cycle appears
- **WHEN** Boundary or dependency checks detect a cycle between contexts
- **THEN** the implementation must introduce a narrower shared contract,
  orchestration module, or domain event boundary before the change is accepted

### Requirement: Initial Context Map
The code organization SHALL preserve ownership areas for identity, tenancy,
authorization, audit, operation correlation, work containers, work graph,
content, ordered placement, revisions, tombstones, external references, raw
archives, integrations, software proving records, work packets, runs,
verification, change proposals, agent runtime, entrypoints, and
projections.

#### Scenario: First module layout is proposed
- **WHEN** the first implementation plan groups or splits module folders
- **THEN** it explains how the initial context map's ownership areas remain
  represented

#### Scenario: First namespace map is generated
- **WHEN** the first Phoenix backend code cut is generated
- **THEN** it MUST use the `OfficeGraph` and `OfficeGraphWeb` top-level
  namespaces with explicit contexts for Foundation, Identity, Tenancy,
  Authorization, Operations, Audit, Revisions, WorkContainers, WorkGraph,
  Content, ExternalRefs, Integrations, SoftwareProving, WorkPackets, Runs,
  Verification, ProposedChanges, AgentRuntime, and Projections unless the
  implementation plan explicitly justifies a narrower temporary grouping

#### Scenario: Public and private modules are placed
- **WHEN** context modules are created
- **THEN** public context modules live at `lib/office_graph/<context>.ex`,
  internal implementation lives under `lib/office_graph/<context>/`, and
  web/API entrypoints live under `lib/office_graph_web/`

#### Scenario: A context is merged for MVP
- **WHEN** two ownership areas share a folder or Ash domain in the first code
  cut
- **THEN** their public contracts and resource ownership remain distinct enough
  to split later without changing product semantics
