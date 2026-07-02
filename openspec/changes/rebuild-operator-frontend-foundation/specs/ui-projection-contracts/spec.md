## MODIFIED Requirements

### Requirement: Frontend Data Hooks Hide GraphQL And Realtime Shape

Office Graph SHALL keep frontend data hooks stable across GraphQL response
shapes and future socket/live realtime invalidation payloads.

#### Scenario: Old JSON migration adapter has no current caller

- **WHEN** GraphQL is the accepted product frontend path and an old JSON adapter
  has no current caller
- **THEN** the frontend MUST delete the JSON adapter instead of preserving a
  migration shape

#### Scenario: Product data path is GraphQL-ready
- **WHEN** the product frontend has an accepted GraphQL read for an
  operator-facing UI
- **THEN** the frontend data hook MUST use GraphQL as the product path and MUST
  NOT preserve JSON migration support as a component-facing compatibility
  requirement

#### Scenario: Realtime update arrives

- **WHEN** realtime delivery notifies a frontend projection about changed
  workflow state
- **THEN** the frontend MUST treat the update as an invalidation, patch, or
  refetch hint defined by the projection contract and MUST NOT treat realtime
  payloads as an independent source of durable truth
