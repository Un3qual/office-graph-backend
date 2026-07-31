## ADDED Requirements

### Requirement: Database boundary scanning classifies Ecto.Multi database operations

The project-local database-boundary scanner SHALL classify database-reading and
database-changing operations composed through `Ecto.Multi` as direct Ecto
access while resolving the operation receiver before classification.

#### Scenario: Ecto.Multi composes database reads

- **WHEN** tracked Elixir source calls `Ecto.Multi.all`, `Ecto.Multi.one`, or
  `Ecto.Multi.exists?` through a fully qualified or explicitly aliased receiver
- **THEN** the canonical Credo boundary check MUST report each call as direct
  Ecto access requiring an inventory entry or removal

#### Scenario: Unrelated multi-like receiver reads data

- **WHEN** tracked Elixir source calls `all`, `one`, or `exists?` on a receiver
  that does not resolve to `Ecto.Multi`
- **THEN** the database-boundary scanner MUST NOT classify the call solely from
  its function name
