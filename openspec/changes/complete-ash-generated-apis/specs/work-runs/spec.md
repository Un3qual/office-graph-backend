## MODIFIED Requirements

### Requirement: Work Run Index Has A Read-Only Relay Connection

Office Graph SHALL expose the bounded run index through AshGraphql's generated
forward `listWorkRuns(first:, after:, sort:)` Relay connection with generated
`WorkRun` Node objects and a generated `workPacket` relationship. It SHALL use
the actor supplied by the shared GraphQL request pipeline, including the
intentionally deferred bootstrap posture, and SHALL NOT create a route-specific
actor, session, fallback, manual summary object, or manual list resolver.

#### Scenario: Client reads a run page

- **WHEN** an authorized client requests `listWorkRuns` with a valid forward
  page input and descending insertion-time sort
- **THEN** GraphQL MUST return ordered `WorkRun` edges, opaque global node
  identities, opaque cursors, page information, and generated packet
  relationships

#### Scenario: Client requests a subsequent page

- **WHEN** an authorized client supplies the generated connection's end cursor
  as `after`
- **THEN** GraphQL MUST return the next stable page using the Ash read action's
  keyset semantics

#### Scenario: Contract is extended

- **WHEN** the all-runs index is implemented
- **THEN** it MUST add no run mutation, hidden compatibility query, manual
  `OperatorRunSummary` object, or second detailed-run projection;
  `operatorRunState` remains the accepted mixed detail and activity source

#### Scenario: Shared actor context resolves the read

- **WHEN** `listWorkRuns` or its selected `operatorRunState` detail read
  resolves an actor
- **THEN** it MUST consume the actor loaded by the shared GraphQL pipeline and
  MUST NOT create a route-specific actor, session, bootstrap, or fallback
