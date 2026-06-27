## ADDED Requirements

### Requirement: Canonical MVP Product Spine

Office Graph SHALL use a small canonical MVP product spine for user-facing
workflow vocabulary.

#### Scenario: Product surface names workflow concepts

- **WHEN** an API contract, UI projection, UI label, product spec, or operator
  workflow names first-spine concepts
- **THEN** it MUST use the canonical concepts Signal, Work Item, Work Packet,
  Run, Check, Evidence, and Verification unless an accepted spec introduces a
  more specific user-facing concept, and it MUST use Change Proposal only when
  proposed mutation review is a real workflow

#### Scenario: Work is prepared for execution

- **WHEN** a human or agent receives a bounded execution contract
- **THEN** the product concept MUST be Work Packet, while readiness, handoff,
  execution package generation, and context compilation remain states or events
  of the packet flow rather than separate default product nouns

### Requirement: Infrastructure Concepts Are Hidden By Default

Office Graph SHALL keep infrastructure concepts out of default operator-facing
contracts unless the operator must act on them.

#### Scenario: Projection includes backend infrastructure records

- **WHEN** a projection depends on graph identity, graph relationships,
  operation correlation, raw archives, execution observations, evidence
  candidates, verification results, policy bundles, audit records, or revisions
- **THEN** the projection MUST map those records into canonical product-spine
  fields or explicit debug/audit fields rather than making infrastructure
  records the primary user-facing nouns

#### Scenario: Audit detail is requested

- **WHEN** an authorized audit, debug, or compliance surface needs
  infrastructure detail
- **THEN** the surface MAY expose infrastructure records with clear labels,
  authorization filtering, and trace context, but it MUST remain distinct from
  the default operator workflow contract

### Requirement: Deprecated Product Terms Do Not Spread

Office Graph SHALL prevent retired or overlapping terms from spreading into new
API, UI, or spec contracts.

#### Scenario: New contract describes proposed mutation

- **WHEN** a new product contract, UI label, or API field describes a proposed
  mutation to graph or domain state
- **THEN** it MUST use Change Proposal terminology and MUST NOT introduce
  `GraphPatch`, `proposed_graph_change`, or equivalent legacy product language

#### Scenario: Legacy storage name remains

- **WHEN** legacy code or storage still uses a retired term for compatibility
- **THEN** new API and UI layers MUST translate it to the canonical product
  term and MUST include a migration or retirement task if the legacy name would
  otherwise become durable public vocabulary

#### Scenario: Normal domain command is modeled

- **WHEN** a human or trusted backend workflow performs a normal domain command
- **THEN** the design MUST NOT force that command through a Change Proposal
  record unless the workflow requires pending review, rejection, approval,
  untrusted generated input, or pre-application audit semantics

#### Scenario: Change Proposal storage is retained

- **WHEN** a Change Proposal or legacy `proposed_graph_changes` storage object
  remains in the implementation
- **THEN** it MUST be treated as a narrow safety/audit mechanism for proposed
  mutations rather than a generic product-facing mutation layer

### Requirement: Evidence Candidate Is Internal Unless Promoted

Office Graph SHALL model evidence candidate mechanics as backend
infrastructure unless an accepted workflow requires operators to review
suggested evidence directly.

#### Scenario: Operator reviews evidence

- **WHEN** an operator-facing surface presents possible evidence
- **THEN** it MUST present the concept as Evidence with a clear state such as
  suggested, accepted, rejected, stale, or missing rather than exposing
  EvidenceCandidate as the default product noun

#### Scenario: Backend records evidence derivation

- **WHEN** backend workflow records observations, candidates, accepted
  evidence, and verification decisions
- **THEN** it MAY preserve distinct durable records for audit and idempotency,
  but API and UI projections MUST expose the simpler Evidence and Verification
  product concepts by default

### Requirement: Expansion Concepts Require Workflow Justification

Office Graph SHALL defer broad concept expansion until a workflow requires the
concept to be user-facing.

#### Scenario: Planned MVP concept is promoted

- **WHEN** a planned concept such as questions, decisions, rich text quote
  snapshots, SCIM group mapping, explicit grants, agent executions, graph node
  conversations, or provider-specific review objects is promoted into
  user-facing scope
- **THEN** the proposal MUST identify the workflow, operator action, projection
  contract, authorization behavior, and reason the canonical product spine is
  insufficient without that concept
