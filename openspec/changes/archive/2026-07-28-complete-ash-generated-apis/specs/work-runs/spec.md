## MODIFIED Requirements

### Requirement: Work Run Index Has A Read-Only Relay Connection

Office Graph SHALL expose the bounded run index through AshGraphql's generated
forward `listWorkRuns(first:, after:, sort:)` Relay connection with generated
`WorkRun` Node objects and generated `workPacket`, `workPacketVersion`,
`requiredChecks`, `executionObservations`, `evidenceCandidates`,
`evidenceItems`, and `verificationResults` relationships. Growing child
relationships SHALL be keyset-backed Relay connections. It SHALL use the actor
supplied by the shared GraphQL request pipeline, including the intentionally
deferred bootstrap posture, and SHALL NOT create a route-specific actor,
session, fallback, manual summary object, or manual resource loader.

#### Scenario: Client reads a run page

- **WHEN** an authorized client requests `listWorkRuns` with a valid forward
  page input and descending insertion-time sort
- **THEN** GraphQL MUST return ordered `WorkRun` edges, opaque global node
  identities, opaque cursors, page information, and generated packet
  relationships

#### Scenario: Client reads run resource detail

- **WHEN** an authorized client requests `getWorkRun` with the opaque identity
  returned by the run connection
- **THEN** GraphQL MUST return generated run, packet, packet-version,
  required-check, observation, evidence, and verification resource objects
  with opaque Node identities and Relay connections for growing child lists

#### Scenario: External client reads run child resources

- **WHEN** an authorized JSON API client reads a run required check, execution
  observation, evidence candidate, evidence item, or verification result
- **THEN** the owning AshJsonApi domain MUST expose the generated resource route
  with actor-scoped authorization and no run-detail controller or serializer

#### Scenario: Client requests a subsequent page

- **WHEN** an authorized client supplies the generated connection's end cursor
  as `after`
- **THEN** GraphQL MUST return the next stable page using the Ash read action's
  keyset semantics

#### Scenario: Contract is extended

- **WHEN** the all-runs index is implemented
- **THEN** it MUST add no run mutation, hidden compatibility query, manual
  `OperatorRunSummary` object, or second detailed-run projection;
  `operatorRunState` remains only the accepted derived status, command,
  child-summary, activity, missing-evidence, and source-watermark projection

#### Scenario: Shared actor context resolves the read

- **WHEN** `listWorkRuns`, `getWorkRun`, or the selected
  `operatorRunState` projection
  resolves an actor
- **THEN** it MUST consume the actor loaded by the shared GraphQL pipeline and
  MUST NOT create a route-specific actor, session, bootstrap, or fallback
