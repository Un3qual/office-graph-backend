## ADDED Requirements

### Requirement: Thin Entrypoints
Entrypoint modules SHALL stay thin by translating input, building operation
context, calling public domain APIs, and formatting output across Phoenix
controllers, Absinthe resolvers, JSON API handlers, channel handlers, Oban
workers, integration webhook handlers, provider adapters, and agent runtime
tools.

#### Scenario: A GraphQL mutation is implemented
- **WHEN** a GraphQL mutation changes durable state
- **THEN** the resolver builds or receives operation context and calls a public
  domain command rather than writing tables directly

#### Scenario: An Oban worker runs a background job
- **WHEN** a worker performs sync, replay, projection refresh, purge, or agent
  work
- **THEN** it calls public domain APIs or approved maintenance interfaces owned
  by the relevant context

### Requirement: Shared Policy And Mutation Paths
Equivalent durable actions MUST use the same authorization,
operation-correlation, revision, audit, tombstone, and proposed-change
contracts across human API requests, automatic agents, delegated agents,
provider webhooks, sync jobs, and integration adapters.

#### Scenario: An agent proposes a graph mutation
- **WHEN** an agent tool wants to change durable graph state
- **THEN** it enters through the proposed-graph-change or domain-action
  contract instead of bypassing normal validation and authorization

#### Scenario: A provider webhook changes an imported record
- **WHEN** an integration webhook updates a provider-neutral imported record
- **THEN** the update path records operation/sync context and uses the same
  lifecycle, revision, audit, and tombstone rules as other equivalent writes

### Requirement: API Surface Reuse
GraphQL and JSON API surfaces SHALL expose transport-specific shapes over the
same domain contracts rather than separate business logic implementations.

#### Scenario: A capability is exposed through both APIs
- **WHEN** a resource or command appears in both GraphQL and JSON API
- **THEN** both entrypoints call the same public domain command/query contract
  and differ only in transport mapping, validation presentation, and response
  shape

#### Scenario: A transport-specific requirement appears
- **WHEN** GraphQL or JSON API needs a transport-specific field, pagination
  shape, or error envelope
- **THEN** the transport layer adds mapping code without moving business rules
  out of the owning context

### Requirement: Projection Entrypoints
Projection and read endpoints SHALL use approved projection/read-model
interfaces that apply authorization, redaction, tombstone visibility, and
classification policy before returning data.

#### Scenario: A focused node view is requested
- **WHEN** an API entrypoint returns a focused graph neighborhood
- **THEN** it uses a projection interface that filters nodes, edges,
  conversations, artifacts, evidence, counts, and summaries through policy

#### Scenario: A restricted target is encountered
- **WHEN** a projection includes a relationship to a target the actor cannot
  see
- **THEN** the entrypoint returns the owning projection contract's approved
  hidden, placeholder, redacted-summary, or denied response
