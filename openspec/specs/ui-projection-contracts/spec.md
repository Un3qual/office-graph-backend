# ui-projection-contracts Specification

## Purpose

Define the rules for frontend-facing data views, derived render caches, and
generated content.
## Requirements
### Requirement: Product UI Reads Through Projection Contracts

Office Graph SHALL define frontend-facing product data as authorization-filtered
read functions rather than ad hoc controller or resolver reads.

#### Scenario: Initial product UI is designed

- **WHEN** the product adds inbox, question queue, work packet context, focused
  node view, blocker view, workstream board, review view, evidence chain,
  verification view, or agent runtime status UI
- **THEN** the UI MUST define its read owner, input parameters,
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

### Requirement: Agent Markdown And Generated Content Use Safe Rendering

Office Graph SHALL render agent Markdown, generated summaries, model outputs,
tool observations, and external-provider snippets through explicit content rules
and frontend read functions.

#### Scenario: Agent-generated content appears in UI

- **WHEN** agent output appears in a node conversation, review surface,
  evidence chain, verification view, or work packet context
- **THEN** the frontend data MUST distinguish draft, suggestion, change proposal,
  accepted graph state, evidence candidate, verified evidence, raw observation,
  and rejected output

#### Scenario: Generated content includes links or embedded references

- **WHEN** generated content references graph items, external references,
  artifacts, raw archives, tool output, code snippets, credentials, or
  restricted context
- **THEN** rendering MUST use typed references and authorization-filtered link
  expansion rather than trusting inline text or raw Markdown to grant access

### Requirement: UI Data Shares API And Realtime Rules

Office Graph SHALL design UI data APIs and realtime updates together so
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

### Requirement: UI Data Exposes Product Meaning

Office Graph SHALL expose product meaning in frontend-facing data rather than
raw infrastructure mechanics.

#### Scenario: Projection includes mixed workflow records

- **WHEN** a projection includes signals, change proposals, work items, packets,
  runs, checks, evidence, verification results, observations, graph items, or
  audit traces
- **THEN** the frontend data MUST present named product fields for the default
  UI and place infrastructure details behind explicit trace, debug, or audit
  fields

#### Scenario: UI needs to render actionability

- **WHEN** the frontend renders allowed next actions, readiness, blockers, or
  verification state
- **THEN** the projection MUST provide normalized actionability fields and MUST
  NOT require the UI to infer domain meaning from raw `type` strings,
  relationship names, or private resource state

### Requirement: Allowed Commands Come From Backend Reads

Office Graph SHALL provide allowed commands through backend reads when the UI
needs to start or continue workflow actions.

#### Scenario: UI renders packet readiness or run-start action

- **WHEN** an operator-facing UI needs to prepare a packet, start a run, accept
  evidence, or complete verification
- **THEN** the backend read MUST provide the required command, stable input
  shape, allowed action, and blocker reasons rather than requiring the frontend
  to assemble domain command input from graph links

#### Scenario: Command input cannot be projected

- **WHEN** a command input requires operator-authored fields or local form state
- **THEN** the backend read MUST still provide allowed actions, required fields,
  defaults, validation hints, and target identities so the frontend does not
  reconstruct domain relationships from raw projection internals

### Requirement: Frontend Data Hooks Hide GraphQL And Realtime Shape

Office Graph SHALL keep frontend data hooks stable across GraphQL response
shapes and future socket/live realtime invalidation payloads.

#### Scenario: Old JSON migration adapter has no current caller

- **WHEN** GraphQL is the accepted product frontend path and an old JSON adapter
  has no current caller
- **THEN** the frontend MUST delete the JSON adapter instead of preserving a
  migration shape

#### Scenario: Realtime update arrives

- **WHEN** realtime delivery notifies a frontend projection about changed
  workflow state
- **THEN** the frontend MUST treat the update as an invalidation, patch, or
  refetch hint defined by the projection contract and MUST NOT treat realtime
  payloads as an independent source of durable truth
