## ADDED Requirements

This foundation capability is framing. Canonical code organization, Boundary,
Ash/Ecto, operation contract, API entrypoint, and library-extraction
requirements are owned by `design-code-organization-and-boundaries`.

### Requirement: Modular Monolith First

Office Graph SHALL start as a modular monolith with explicit domain
boundaries, not as microservices.

#### Scenario: Application structure is chosen

- **WHEN** the initial backend is generated
- **THEN** it must organize code around bounded contexts and public domain
  interfaces rather than around controllers, schemas, or integration vendors
  alone

#### Scenario: Service split is proposed

- **WHEN** a microservice, umbrella split, or separate package is proposed
- **THEN** the proposal must identify the concrete scaling, ownership,
  deployment, reuse, or isolation requirement that justifies the split

### Requirement: Boundary And DDD Dependency Rules

Office Graph SHALL use the Boundary library and DDD-style context rules to
control dependencies in the large backend.

#### Scenario: Domain depends on another domain

- **WHEN** one context needs behavior from another context
- **THEN** the dependency must go through declared public APIs, actions,
  policies, events, queries, or behaviours rather than reaching into internal
  modules

#### Scenario: Lateral coupling appears

- **WHEN** two product domains begin sharing internal schemas or implementation
  details
- **THEN** the design must introduce an explicit interface or move the shared
  concern into a better bounded context

### Requirement: Ash Owns Domain Actions And Policies

Ash SHALL be used for stable resources, business actions, validation, state
transitions, and policy-facing domain boundaries.

#### Scenario: API mutation writes product state

- **WHEN** GraphQL, JSON API, webhook, Oban job, integration adapter, or agent
  runtime code needs to change product state
- **THEN** it must call declared domain actions or services rather than
  embedding business logic in resolvers, controllers, jobs, or adapters

#### Scenario: Graph or bulk operation exceeds normal Ash ergonomics

- **WHEN** graph traversal, replay, analytics, ingestion, or bulk operations
  are better served by direct Ecto or SQL
- **THEN** direct database access may be used behind a domain boundary with
  authorization, validation, telemetry, and tests

### Requirement: Shared API Authorization Boundary

GraphQL and JSON API SHALL share domain actions and authorization semantics.

#### Scenario: API endpoint is added

- **WHEN** a GraphQL resolver or JSON API endpoint is implemented
- **THEN** it must use the same authorization context and domain action
  semantics as other interfaces for the same operation

#### Scenario: Product UI endpoint is planned

- **WHEN** frontend-facing API behavior is planned
- **THEN** the design must preserve React as the product UI client and must not
  add LiveView product UI dependencies

### Requirement: OTP, Oban, PubSub, And Realtime Boundaries

Office Graph SHALL use OTP and Phoenix realtime primitives deliberately.

#### Scenario: Durable async work is needed

- **WHEN** external event processing, agent runs, integration sync, work packet
  compilation, or verification jobs need durability
- **THEN** the design should use Oban or another explicit durable job mechanism
  backed by Postgres

#### Scenario: Realtime updates are needed

- **WHEN** clients need updates for graph changes, conversations, questions,
  runs, or verification state
- **THEN** the design should use Phoenix PubSub with Absinthe subscriptions or
  Phoenix Channels as appropriate, while keeping Postgres as durable state and
  not the app-level realtime bus

### Requirement: Library-Ready Internal Boundaries

Selected domains SHALL be designed so they can later be extracted into reusable
libraries without premature package splitting.

#### Scenario: Reusable domain is implemented

- **WHEN** authentication/identity, authorization, agent runtime, integration
  primitives, revision/audit primitives, or similar reusable domains are
  implemented
- **THEN** their dependencies, configuration, storage assumptions, behaviours,
  and public APIs must be kept clean enough that future extraction remains
  practical

### Requirement: Integration Package Boundary

Integration and connection code SHALL be isolated behind adapter contracts and
package-ready boundaries.

#### Scenario: Integration is added

- **WHEN** a provider integration is implemented
- **THEN** it must register capabilities, credentials, webhook handlers,
  normalized events, external references, actions, and handoff targets through
  an explicit adapter contract rather than reaching directly into core
  internals
