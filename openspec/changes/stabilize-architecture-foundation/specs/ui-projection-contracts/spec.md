## ADDED Requirements

### Requirement: Projections Expose Product Semantics

Office Graph SHALL expose product-spine semantics in frontend-facing
projections rather than raw infrastructure mechanics.

#### Scenario: Projection includes mixed workflow records

- **WHEN** a projection includes signals, change proposals, work items, packets,
  runs, checks, evidence, verification results, observations, graph items, or
  audit traces
- **THEN** the projection MUST present canonical product-spine fields for the
  default UI and place infrastructure details behind explicit trace, debug, or
  audit fields

#### Scenario: UI needs to render actionability

- **WHEN** the frontend renders allowed next actions, readiness, blockers, or
  verification state
- **THEN** the projection MUST provide normalized actionability fields and MUST
  NOT require the UI to infer domain meaning from raw `type` strings,
  relationship names, or private resource state

### Requirement: Command Affordances Come From Backend Projections

Office Graph SHALL provide command affordances through projection contracts
when the UI needs to start or continue workflow actions.

#### Scenario: UI renders packet readiness or run-start affordance

- **WHEN** an operator-facing UI needs to prepare a packet, start a run, accept
  evidence, or complete verification
- **THEN** the backend projection MUST provide the required command affordance,
  stable input shape, allowed action, and blocker reasons rather than requiring
  the frontend to assemble domain command input from graph links

#### Scenario: Command input cannot be projected

- **WHEN** a command input requires operator-authored fields or local form state
- **THEN** the projection MUST still provide allowed actions, required fields,
  defaults, validation hints, and target identities so the frontend does not
  reconstruct domain relationships from raw projection internals

### Requirement: Projection Clients Hide GraphQL And Realtime Shape

Office Graph SHALL keep frontend projection clients stable across GraphQL
response shapes, temporary JSON migration shapes, and future socket/live
realtime invalidation payloads.

#### Scenario: Projection is exposed through migration and product transports

- **WHEN** both temporary JSON API and GraphQL expose an operator-facing
  projection during migration
- **THEN** frontend projection clients MUST normalize field naming, pagination,
  error envelopes, and relationship shapes into a single feature view model,
  with GraphQL as the desired product frontend transport

#### Scenario: Realtime update arrives

- **WHEN** realtime delivery notifies a frontend projection about changed
  workflow state
- **THEN** the frontend MUST treat the update as an invalidation, patch, or
  refetch hint defined by the projection contract and MUST NOT treat realtime
  payloads as an independent source of durable truth
