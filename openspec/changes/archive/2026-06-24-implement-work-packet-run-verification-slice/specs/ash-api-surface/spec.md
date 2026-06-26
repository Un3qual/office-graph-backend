## ADDED Requirements

### Requirement: Packet Run Verification Slice Uses Shared Domain APIs

Office Graph SHALL expose the first packet-run-verification slice through
shared domain actions and Ash-owned API surfaces.

#### Scenario: Resource surface is exposed

- **WHEN** packet versions, work runs, execution observations, evidence
  candidates, accepted evidence, or verification results are exposed for API
  reads or simple resource mutations
- **THEN** the implementation MUST use AshGraphql and AshJsonApi declarations
  on the owning domain/resource or document a narrow custom transport
  exception

#### Scenario: Orchestration command spans domains

- **WHEN** an API command creates a packet, starts a work run, records an
  observation, accepts evidence, or records verification across multiple
  bounded contexts
- **THEN** the transport code MUST stay thin, build or receive session and
  operation context, call public context actions, and avoid owning lifecycle,
  authorization, validation, or evidence-acceptance rules

### Requirement: Packet Run Verification APIs Have Parity

Office Graph SHALL test equivalent GraphQL and JSON API behavior for the first
packet-run-verification flow.

#### Scenario: GraphQL and JSON API execute the flow

- **WHEN** both API surfaces create a packet, start a work run, record an
  observation, accept evidence, and read the summary projection
- **THEN** both surfaces MUST produce equivalent durable state, authorization
  decisions, operation correlation, validation errors, verification results,
  and response semantics

#### Scenario: API request is invalid

- **WHEN** either API surface receives invalid packet, run, observation,
  evidence, authorization, lifecycle, scope, or idempotency input
- **THEN** it MUST return a structured error with a stable code and safe
  explanatory detail equivalent to the other API surface
