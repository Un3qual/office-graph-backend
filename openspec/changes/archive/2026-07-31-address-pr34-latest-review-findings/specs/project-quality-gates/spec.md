## ADDED Requirements

### Requirement: Database boundary scanning classifies Ecto query fragments

The project-local database-boundary scanner SHALL classify repository-authored Ecto query fragments as raw SQL regardless of whether the fragment macro is called locally, fully qualified, or through an explicit alias.

#### Scenario: Ecto query fragment is fully qualified

- **WHEN** tracked Elixir source calls `Ecto.Query.API.fragment`, `Ecto.Query.API.unsafe_fragment`, or the same operation through an explicit alias
- **THEN** the canonical Credo boundary check MUST report a raw-SQL occurrence requiring the same exact approval as a locally imported fragment

#### Scenario: Unrelated module defines a fragment function

- **WHEN** tracked source calls `fragment` on a receiver that does not resolve to the Ecto query API
- **THEN** the scanner MUST NOT classify the call solely from the operation name
