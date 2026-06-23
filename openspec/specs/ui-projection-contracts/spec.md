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
- **THEN** the projection MUST distinguish draft, suggestion, proposed change,
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
