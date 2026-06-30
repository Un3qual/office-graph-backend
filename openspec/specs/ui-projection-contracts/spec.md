# ui-projection-contracts Specification

## Purpose

Define frontend-facing projection contract rules for Office Graph product
surfaces, derived render caches, and generated content boundaries.
## Requirements
### Requirement: Product UI Reads Through Projection Contracts

Office Graph SHALL define frontend-facing product surfaces as authorization
filtered projection contracts rather than ad hoc controller or resolver reads.

#### Scenario: Initial product surface is designed

- **WHEN** the product adds inbox, question queue, work packet context, focused
  node view, blocker view, workstream board, review surface, evidence chain,
  verification view, or agent runtime status UI
- **THEN** the surface MUST define its projection owner, input parameters,
  included graph items, related typed records, redaction behavior, status
  fields, empty states, realtime needs, and API transport exposure before UI
  implementation begins

#### Scenario: Projection includes mixed resource types

- **WHEN** a projection returns mixed graph items such as tasks, questions,
  decisions, review findings, checks, evidence, documents, runs, or external
  references
- **THEN** it MUST preserve typed resource identity, graph identity,
  authorization rationale, and enough status normalization for the UI to render
  without inferring business semantics from raw type strings

### Requirement: Render Caches Are Derived State

Office Graph SHALL treat render caches, frontend projections, count rollups,
status summaries, and agent-context render outputs as derived state that can be
invalidated and rebuilt from durable records.

#### Scenario: Render cache is introduced

- **WHEN** a projection, rich text render, markdown render, graph neighborhood,
  inbox count, blocker count, or review surface cache is introduced
- **THEN** the design MUST identify source records, cache key, invalidation
  events, authorization inputs, sensitivity labels, staleness behavior, and
  rebuild path

#### Scenario: Cached content crosses policy boundary

- **WHEN** cached projection or render output contains sensitive, redacted,
  restricted, agent-generated, or external-provider-derived content
- **THEN** the cache MUST either be scoped to the authorized viewer/policy
  context or store only safe derived metadata that cannot leak restricted data

### Requirement: Agent Markdown And Generated Content Are Boundaried

Office Graph SHALL render agent Markdown, generated summaries, model outputs,
tool observations, and external-provider snippets through explicit content and
projection boundaries.

#### Scenario: Agent-generated content appears in UI

- **WHEN** agent output appears in a node conversation, review surface,
  evidence chain, verification view, or work packet context
- **THEN** the projection MUST distinguish draft, suggestion, change proposal,
  accepted graph state, evidence candidate, verified evidence, raw observation,
  and rejected output

#### Scenario: Generated content includes links or embedded references

- **WHEN** generated content references graph items, external references,
  artifacts, raw archives, tool output, code snippets, credentials, or
  restricted context
- **THEN** rendering MUST use typed references and authorization-filtered link
  expansion rather than trusting inline text or raw Markdown to grant access

### Requirement: UI Projections Share API And Realtime Contracts

Office Graph SHALL design UI projection APIs and realtime updates together so
the frontend can reconcile state without transport-specific business logic.

#### Scenario: Projection has realtime updates

- **WHEN** a UI projection receives realtime updates
- **THEN** the projection API MUST define how the realtime event maps to the
  projection row, node, edge, section, count, stale marker, or refetch trigger

#### Scenario: Projection is exposed through GraphQL and JSON API

- **WHEN** both GraphQL and JSON API expose a projection or projection-backed
  command
- **THEN** both transports MUST use the same projection contract and differ
  only in transport shape, pagination, filtering syntax, or error envelope

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
