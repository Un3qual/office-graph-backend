# product-concept-simplification Specification

## Purpose
Define the product words used by the first Office Graph workflows.
## Requirements
### Requirement: Canonical MVP Product Spine

Office Graph SHALL use a small canonical MVP product spine for user-facing
workflow vocabulary.

#### Scenario: Product UI or API names workflow concepts

- **WHEN** an API contract, UI projection, UI label, product spec, or operator
  workflow names first-spine concepts
- **THEN** it MUST use the canonical concepts Signal, Work Item, Work Packet,
  Run, Check, Evidence, and Verification unless an accepted spec introduces a
  more specific user-facing concept, and it MUST NOT introduce ChangeProposal as
  current MVP vocabulary until proposed mutation review is a real workflow for
  typed domain commands

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

- **WHEN** an authorized audit, debug, or compliance page or API needs
  infrastructure detail
- **THEN** the page or API MAY expose infrastructure records with clear labels,
  authorization filtering, and trace context, but it MUST remain distinct from
  the default operator workflow contract

### Requirement: Deprecated Product Terms Do Not Spread

Office Graph SHALL prevent retired or overlapping terms from spreading into new
API, UI, or spec contracts.

#### Scenario: Current contract describes proposed mutation

- **WHEN** a new product contract, UI label, or API field describes a proposed
  mutation before a real proposed-mutation review workflow exists
- **THEN** it MUST NOT introduce ChangeProposal, `GraphPatch`,
  `proposed_graph_change`, or equivalent product language, and it MUST model the
  workflow as a normal domain command, Signal, draft Work Item, triage record,
  or Evidence state as appropriate

#### Scenario: Old storage name remains

- **WHEN** old code or storage still uses a retired term
- **THEN** new API and UI layers MUST translate it to the canonical product
  term and MUST include a migration or retirement task if the old name would
  otherwise become durable public vocabulary

#### Scenario: Normal domain command is modeled

- **WHEN** a human or trusted backend workflow performs a normal domain command
- **THEN** the design MUST NOT force that command through a Change Proposal
  record unless the workflow requires pending review, rejection, approval,
  untrusted generated input, or pre-application audit semantics

#### Scenario: Future proposal workflow is introduced

- **WHEN** a later accepted spec introduces full proposal functionality
- **THEN** ChangeProposal MUST propose typed domain command input, MUST validate
  against the owning domain command before approval/application, MUST apply by
  invoking the owning domain command, and MUST NOT mutate the graph projection
  as the source of truth

#### Scenario: Old proposed graph change storage remains

- **WHEN** old `proposed_graph_changes` storage remains during migration
- **THEN** new API endpoints and UI MUST treat it as temporary migration data
  or raw suggestion input, MUST NOT expose it as generic graph mutation product
  state, and MUST include retirement or replacement work

### Requirement: Evidence Candidate Is Internal Unless Promoted

Office Graph SHALL model suggested, accepted, rejected, stale, and missing
evidence as Evidence states in product-facing contracts.

#### Scenario: Operator reviews evidence

- **WHEN** an operator page presents possible evidence
- **THEN** it MUST present the concept as Evidence with a clear state such as
  suggested, accepted, rejected, stale, or missing rather than exposing
  EvidenceCandidate as the default product noun

#### Scenario: Backend records evidence derivation

- **WHEN** backend workflow records observations, candidates, accepted
  evidence, and verification decisions
- **THEN** it MAY preserve distinct durable records for audit and idempotency,
  but API and UI projections MUST expose the simpler Evidence and Verification
  product concepts by default

#### Scenario: Evidence acceptance rules are modeled

- **WHEN** evidence is suggested, accepted, rejected, marked stale, or used to
  satisfy or fail a check
- **THEN** Verification MUST own evidence acceptance, check satisfaction,
  verification-result recording, and recomputation rules, while Runs owns run
  lifecycle state updates through explicit commands

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
