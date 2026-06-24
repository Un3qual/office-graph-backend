# walking-skeleton-domain-loop Specification

## Purpose

Define the first executable Office Graph domain loop from local owner
bootstrap through manual intake, change proposals, state progression,
authorization context, and adapter-safe mutation boundaries.

## Requirements

### Requirement: First Organization Bootstrap

Office Graph SHALL provide a controlled bootstrap path for the first local
organization and owner.

#### Scenario: Backend is started for local development or tests

- **WHEN** the bootstrap command or fixture setup runs against an empty
  database
- **THEN** it MUST create the first organization, workspace, initiative, owner
  principal, role assignment, policy anchor, and authenticated session context
  required to execute the walking skeleton

### Requirement: Manual Intake Starts The Loop

Office Graph SHALL begin the first executable loop from manual intake.

#### Scenario: User submits manual intake

- **WHEN** an authenticated principal submits pasted or manually entered input
- **THEN** Office Graph MUST archive the input, normalize it into an intake
  event, create or propose a signal, and preserve idempotency and replay
  identity for duplicate handling

### Requirement: Change Proposals Guard Graph Mutation

Office Graph SHALL route generated or adapter-derived mutations through
change proposals before applying them to truth tables.

#### Scenario: Intake suggests durable graph changes

- **WHEN** manual intake normalization identifies a task, review finding,
  verification check, evidence item, artifact, or relationship to create
- **THEN** Office Graph MUST represent the intended mutation as a change proposal and apply it only through authorized domain actions

#### Scenario: Change proposal is invalid or unauthorized

- **WHEN** change proposal validation or authorization fails
- **THEN** Office Graph MUST leave product truth tables unchanged and preserve
  enough trace information for review, correction, or rejection

### Requirement: Walking Skeleton State Progression

Office Graph SHALL support the first end-to-end product state progression.

#### Scenario: Work item reaches verified completion

- **WHEN** the manual intake signal has produced a task, review finding,
  required verification check, and evidence item
- **THEN** an authorized action MUST be able to mark the verification check
  satisfied, link the evidence, produce a verification result, and mark the
  task or finding as verified complete according to type-specific lifecycle
  rules

### Requirement: Authorization Context On Domain Actions

Office Graph SHALL execute walking-skeleton actions with authenticated
principal and operation context.

#### Scenario: Domain action is invoked

- **WHEN** an API entrypoint, test helper, bootstrap command, or adapter path
  invokes a walking-skeleton domain action
- **THEN** it MUST pass authenticated principal/session context, tenant/scope
  context, and operation correlation context to the owning domain action before
  authorization or mutation occurs

#### Scenario: Local API owner bootstrap is disabled

- **WHEN** a JSON or GraphQL API mutation is invoked without authenticated
  principal/session context and local API owner bootstrap is not explicitly
  enabled
- **THEN** Office Graph MUST reject the mutation before creating operation
  correlation, intake, change-proposal, verification, or graph truth records

### Requirement: Adapter Paths Do Not Write Truth Tables Directly

Office Graph SHALL keep ingestion and generated mutation paths behind domain
actions.

#### Scenario: Manual adapter recognizes graph content

- **WHEN** the manual intake adapter recognizes content that maps to graph
  resources or relationships
- **THEN** the adapter MUST output typed envelopes or change proposals rather
  than directly inserting graph items, typed resources, relationships, checks,
  evidence, or verification results
