## ADDED Requirements

### Requirement: Generated Relay node domains match the GraphQL schema

Office Graph SHALL make every AshGraphql resource domain registered by the
GraphQL schema available to the root Relay node resolver.

#### Scenario: Generated resource ID is refetched

- **WHEN** a generated GraphQL resource in any registered domain returns an
  opaque Relay ID
- **THEN** the root `node(id:)` field MUST decode the ID and perform the
  authorized Ash read through that resource's owning domain

#### Scenario: Domain is added to the generated schema

- **WHEN** a domain that contributes AshGraphql resources is registered in the
  GraphQL schema
- **THEN** verification MUST fail if the shared node resolver cannot resolve
  those resource types
