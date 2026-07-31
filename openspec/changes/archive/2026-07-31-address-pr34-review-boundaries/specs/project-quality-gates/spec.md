## ADDED Requirements

### Requirement: Database boundary scanning classifies repository connection ownership

The project-local database-boundary scanner SHALL classify explicit connection ownership through the Office Graph repository as direct Ecto access.

#### Scenario: Repository connection is checked out

- **WHEN** tracked Elixir source calls `OfficeGraph.Repo.checkout` directly or through an explicit repository alias
- **THEN** the canonical Credo boundary check MUST report the call as direct Ecto access requiring an inventory entry or removal

#### Scenario: Unrelated checkout function is called

- **WHEN** tracked Elixir source calls `checkout` on a receiver that does not resolve to `OfficeGraph.Repo`
- **THEN** the database-boundary scanner MUST NOT classify the call solely from its function name
