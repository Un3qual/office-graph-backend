## MODIFIED Requirements

### Requirement: Projection Clients Hide GraphQL And Realtime Shape

Office Graph SHALL keep frontend projection clients stable across GraphQL
response shapes and future socket/live realtime invalidation payloads.
Temporary JSON migration shapes MAY be supported during a transport migration,
but product frontend code MUST NOT retain a JSON adapter once an accepted
GraphQL projection path exists for that surface.

#### Scenario: Projection is exposed through migration and product transports

- **WHEN** both temporary JSON API and GraphQL expose an operator-facing
  projection during migration
- **THEN** frontend projection clients MUST normalize field naming, pagination,
  error envelopes, and relationship shapes into a single feature view model,
  with GraphQL as the desired product frontend transport

#### Scenario: Product projection is GraphQL-ready
- **WHEN** the product frontend has an accepted GraphQL projection for an
  operator-facing surface
- **THEN** the frontend projection client MUST use GraphQL as the product path
  and MUST NOT preserve temporary JSON migration support as a component-facing
  compatibility requirement

#### Scenario: Realtime update arrives

- **WHEN** realtime delivery notifies a frontend projection about changed
  workflow state
- **THEN** the frontend MUST treat the update as an invalidation, patch, or
  refetch hint defined by the projection contract and MUST NOT treat realtime
  payloads as an independent source of durable truth
