## ADDED Requirements

### Requirement: Database boundary scanning resolves explicit aliases

The project-local database-boundary scanner SHALL recognize explicitly aliased
repository receivers before classifying raw SQL and direct Ecto calls.

#### Scenario: Repository is renamed with an alias

- **WHEN** tracked Elixir source aliases `OfficeGraph.Repo` to another valid
  module name and invokes a prohibited repository operation through that alias
- **THEN** the canonical Credo boundary check MUST report the same raw-SQL or
  direct-Ecto occurrence it would report for `Repo`

#### Scenario: Unrelated receiver has a database-like function name

- **WHEN** source calls `query`, `query!`, or another classified operation on a
  receiver that is not `OfficeGraph.Repo` or its explicit alias
- **THEN** the scanner MUST NOT classify that call as repository database
  access solely from the function name
