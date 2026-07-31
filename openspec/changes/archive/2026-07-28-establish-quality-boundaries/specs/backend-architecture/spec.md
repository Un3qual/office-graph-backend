## MODIFIED Requirements

### Requirement: Ash Owns Domain Actions And Policies

Ash SHALL be used for stable resources, business actions, validation, state
transitions, policy-facing domain boundaries, database transactions, and
API-facing orchestration whenever built-in Ash or AshPostgres behavior can
express the requirement safely.

#### Scenario: API mutation writes product state

- **WHEN** GraphQL, JSON API, webhook, Oban job, integration adapter, or agent runtime code needs to change product state
- **THEN** it must call declared domain actions or services rather than embedding business logic in resolvers, controllers, jobs, or adapters

#### Scenario: Multi-resource mutation is planned

- **WHEN** a command coordinates multiple resources transactionally
- **THEN** the design MUST first use Ash action hooks, generic actions with action-managed transactions, managed relationships, bulk actions, identities, atomic changes, and optimistic locking rather than wrapping hand-built writes in `Repo.transaction`

#### Scenario: Complex read or mutation exceeds normal Ash ergonomics

- **WHEN** graph traversal, replay, analytics, ingestion, projection, or bulk behavior appears to require direct Ecto or raw SQL
- **THEN** the design MUST identify the exact missing Ash capability, use typed domain boundaries, and obtain explicit user approval through OpenSpec before adding any repository-authored raw SQL

#### Scenario: Ash behavior is customized

- **WHEN** a custom validation, change, action, relationship, resolver, or data-layer escape hatch is proposed
- **THEN** the design MUST consult the documentation for the project-pinned Ash and plugin versions and explain why the corresponding built-in feature is insufficient
