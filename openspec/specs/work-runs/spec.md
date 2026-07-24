# work-runs Specification

## Purpose
Define Office Graph-managed executions of selected work and their governed lifecycle.
## Requirements
### Requirement: Work Runs Represent Selected Work Execution

Office Graph SHALL represent execution of selected work as a work run, distinct
from individual agent executions, provider check runs, integration jobs, and
human handoff observations.

#### Scenario: Work run starts from a packet

- **WHEN** a work packet version is accepted for execution
- **THEN** Office Graph MUST be able to create a work run that records the
  selected packet version, objective, owning organization and scope, initiating
  principal or trigger, authority posture, operation context, required checks,
  and initial lifecycle state

#### Scenario: Work run starts from selected graph work

- **WHEN** a user, policy, integration, or agent starts execution for a task,
  requirement, change proposal, graph item set, conversation request, incident,
  campaign artifact, or another bounded objective without a packet version
- **THEN** Office Graph MUST be able to create a work run that records the
  selected work target, reason for execution, source surface, scope, authority
  posture, operation context, and verification expectations

### Requirement: Work Runs Coordinate Child Execution Records

Office Graph SHALL let a work run coordinate multiple child records without
collapsing their distinct ownership and lifecycle semantics.

#### Scenario: Work run has multiple agent executions

- **WHEN** execution of selected work requires several internal agent
  invocations
- **THEN** the work run MUST preserve links to each child agent execution and
  MUST expose aggregate status without treating any single agent execution as
  the whole run

#### Scenario: Work run has mixed child activity

- **WHEN** execution includes agent executions, human handoffs, provider check
  observations, change proposals, approval gates, evidence candidates, or
  waivers
- **THEN** the work run MUST preserve typed child references and MUST NOT store
  all child payloads in one generic run-event record

### Requirement: Work Run Status Is Aggregate And Explainable

Office Graph SHALL compute work-run status from parent lifecycle, child
execution state, observations, approval gates, evidence, checks, waivers, and
staleness.

#### Scenario: Child execution succeeds but verification is incomplete

- **WHEN** all child agent executions finish successfully but required checks
  still lack accepted evidence or approved waivers
- **THEN** the work run MUST NOT be represented as verified complete and MUST
  explain which checks, evidence, approval gates, observations, or waivers are
  still blocking completion

#### Scenario: Child execution fails

- **WHEN** an agent execution, human handoff, provider observation, change
  proposal, or verification step fails inside a work run
- **THEN** Office Graph MUST preserve the child failure and MUST update the
  work-run aggregate status to blocked, failed, partial, retryable, or another
  policy-defined state with traceable reasons

### Requirement: Work Runs Preserve Parent Execution Traceability

Office Graph SHALL preserve parent-level operation, authority, evidence, audit,
and revision traceability for work runs.

#### Scenario: Work run changes product state

- **WHEN** execution inside a work run applies an accepted change proposal
  through its owning domain action, creates evidence, satisfies verification,
  records a waiver, or changes a related product record
- **THEN** the resulting records MUST preserve references to the work run and
  operation correlation where applicable

#### Scenario: Work run is superseded

- **WHEN** a packet version, selected work target, authority posture, required
  check, or material context changes after a work run starts
- **THEN** Office Graph MUST be able to mark the work run stale, superseded,
  blocked, or requiring re-evaluation while preserving its execution history

### Requirement: Initial Work Run Starts From A Packet Version

Office Graph SHALL implement work-run creation from a selected packet version
as the first execution path.

#### Scenario: Work run starts

- **WHEN** an authorized actor starts execution from a ready packet version
- **THEN** Office Graph MUST create a work run that records organization,
  workspace, packet, packet version, objective, initiator, authority posture,
  operation correlation, required checks, aggregate state, and timestamps

#### Scenario: Work run create lifecycle is derived by the domain

- **WHEN** a work run row is created directly or through the work-run start
  command
- **THEN** Office Graph MUST derive the initial running, pending, and
  unverified lifecycle fields and MUST NOT accept caller-supplied verified,
  failed, completed, or completed-at lifecycle state at create time

#### Scenario: Packet version is not ready

- **WHEN** an actor attempts to start a work run from a draft, stale,
  superseded, not-ready, malformed-ready, unauthorized, or missing packet
  version
- **THEN** Office Graph MUST reject the command without creating a work run
  and MUST return an explainable validation or authorization error

#### Scenario: Run authority stays within the packet autonomy envelope

- **WHEN** an actor attempts to start or replay a work run with an authority
  posture outside the selected packet version's allowed autonomy posture
- **THEN** Office Graph MUST reject the command without creating or returning a
  work run for that authority

#### Scenario: Work run start replay input changes

- **WHEN** a work-run start operation idempotency key is replayed after a work
  run exists with a different packet version, source surface, reason, or
  authority posture
- **THEN** Office Graph MUST reject the replay as an operation conflict instead
  of returning the work run created for different start input

#### Scenario: Run required checks match the selected packet contract

- **WHEN** a run required-check link is created directly or copied from a
  packet version
- **THEN** Office Graph MUST keep the link in the target scope, derive the
  initial pending state, and reject verification checks that are not required
  by the run's selected packet version

### Requirement: Initial Work Run Coordinates Typed Child Observations

Office Graph SHALL link execution observations to work runs as typed child
activity in the first slice.

#### Scenario: Human or provider observation is recorded

- **WHEN** a human handoff note, manual execution status, provider check, test
  result, or integration job status is recorded for a work run
- **THEN** Office Graph MUST create an execution observation or typed link to
  an existing observation and MUST include it in the work run's aggregate
  status inputs

#### Scenario: Child activity is stored

- **WHEN** child activity is added to a work run
- **THEN** Office Graph MUST preserve typed child references and MUST NOT store
  the child activity only as an opaque generic run-event payload

#### Scenario: Observation references graph item without check

- **WHEN** an execution observation supplies a graph item without a verification
  check for a packet-backed work run
- **THEN** Office Graph MUST accept the observation only when the graph item is
  part of the selected packet sources or required-check targets and MUST reject
  unrelated same-scope graph items before recording the observation

#### Scenario: Observation references a check for a packet-backed run

- **WHEN** an execution observation supplies a verification check for a
  packet-backed work run
- **THEN** Office Graph MUST accept the observation only when the check belongs
  to the run's selected packet required checks and MUST reject unrelated
  same-scope checks before recording the observation

### Requirement: Initial Work Run Status Separates Execution From Verification

Office Graph SHALL compute the first work-run aggregate status separately from
verification completion.

#### Scenario: Execution succeeds without accepted evidence

- **WHEN** all recorded child execution observations are successful but a
  required verification check lacks accepted evidence or a valid result
- **THEN** Office Graph MUST expose the work run as execution-complete or
  awaiting-verification rather than verified-complete

#### Scenario: Required check is satisfied

- **WHEN** all required checks for the selected packet version have accepted
  evidence and passing verification results
- **THEN** Office Graph MUST be able to expose the work run as verified while
  preserving the evidence and result records that explain the status

#### Scenario: Successful observation arrives after verification

- **WHEN** a work run is already verified and a later successful child
  observation is recorded without an explicit stale, failed, or re-verification
  signal
- **THEN** Office Graph MUST preserve the verified aggregate and verification
  state while still recording the later observation

### Requirement: Work Run Start Has Supported Product Commands

Office Graph SHALL expose packet-backed work-run start through authenticated
GraphQL and JSON API commands over the Runs domain boundary.

#### Scenario: Operator starts a work run

- **WHEN** an authorized operator submits a ready packet-version id, source
  surface, reason, authority posture, and idempotency key
- **THEN** both API families MUST preserve current readiness, scope, autonomy,
  required-check, operation, and replay rules and return the run and ordered
  required checks

#### Scenario: Packet version is no longer runnable

- **WHEN** the packet version is stale, draft, cross-scope, malformed, or refers
  only to checks already satisfied
- **THEN** run start MUST fail without creating a run

### Requirement: Agent Execution State Does Not Verify Parent Runs
Office Graph SHALL project child agent execution state into the parent run
without treating agent completion or output as verification completion.

#### Scenario: Agent execution completes successfully
- **WHEN** all steps in a child agent execution complete
- **THEN** the parent run MAY show successful agent activity but MUST remain
  governed by its required checks, observations, accepted evidence, and
  verification results

#### Scenario: Agent execution fails
- **WHEN** a child execution reaches terminal failure
- **THEN** the run timeline MUST retain the failure, and that failure MUST block
  parent verification only when it is mapped to a required check or accepted
  evidence/result; an unrelated optional child failure MUST NOT invalidate an
  otherwise valid verification decision

### Requirement: Run Timeline Shows Product-Relevant Agent Events
Office Graph SHALL expose bounded execution, approval, context, tool, proposal,
evidence, retry, cancellation, and completion summaries in run projections.

#### Scenario: Low-level runtime trace exists
- **WHEN** token, prompt-debug, or provider-internal traces are produced
- **THEN** the run timeline MUST omit them unless a separate authorized debug
  projection explicitly requests them

### Requirement: Work Runs Have An Authorized Bounded Index Projection

Office Graph SHALL provide a read-only work-run index projection that returns
only this safe output for the resolved session's authorized organization and
workspace: run id, objective, aggregate state, execution state, verification
state, insertion time, and stable source watermark; packet id, title, and
state; and packet-version id, version number, lifecycle state, and objective.
The GraphQL layer SHALL derive an opaque packet Relay id from the projected
packet id for canonical product deep links; that Relay id is not an additional
projection field. The projection SHALL require the existing skeleton-read
capability and use one actor-authorized run-page read plus two actor-authorized,
scope-filtered, page-batched enrichment reads for packets and packet versions.
It SHALL NOT load enrichment per row, duplicate `operatorRunState` detail
assembly, or own a command.

#### Scenario: Authorized scope receives only its runs

- **WHEN** an authorized session reads the work-run index
- **THEN** it MUST receive only summaries from its resolved organization and
  workspace, and no row, packet label, packet-version label, or watermark from
  another tenant or workspace may appear

#### Scenario: Read authorization is denied

- **WHEN** the resolved session lacks the skeleton-read capability
- **THEN** the index MUST reject the read using the existing safe authorization
  shape and MUST NOT return a partial or unscoped row set

#### Scenario: Index uses stable newest-first keyset pagination

- **WHEN** an authorized reader requests a forward page and then requests its
  next page after newer runs are inserted
- **THEN** the index MUST order rows by `inserted_at DESC, id DESC`, encode
  that total order in its opaque cursor, and return the original continuation
  without skipping or duplicating preexisting rows

#### Scenario: Cursor or page limit is invalid

- **WHEN** a caller supplies a malformed, stale, unsupported, or invalid cursor
  or a limit outside the supported connection bounds
- **THEN** the index MUST return the existing safe validation shape and MUST
  NOT issue an unbounded or ambiguously ordered read

#### Scenario: Index size grows

- **WHEN** the number of runs in the authorized scope grows while the requested
  page size stays fixed
- **THEN** the index MUST retain its constant bound of one actor-authorized
  run-page read plus two actor-authorized, scope-filtered, page-batched
  enrichment reads and MUST NOT load packet or packet-version data one row at a
  time

### Requirement: Work Run Index Has A Read-Only Relay Connection

Office Graph SHALL expose the bounded index as the forward `operatorRuns(first:, after:)`
Relay connection with `OperatorRunSummary` nodes and existing connection
validation, cursor, and safe-error conventions. It SHALL use the existing
shared `OfficeGraphWeb.RequestSession` resolution unchanged, including the
intentionally deferred bootstrap posture, and SHALL NOT create a route-specific
actor, session, or fallback.

#### Scenario: Client reads a run page

- **WHEN** an authorized client requests `operatorRuns` with a valid forward
  page input
- **THEN** GraphQL MUST return ordered edges, opaque cursors, page information,
  and only the summary fields defined by the index projection

#### Scenario: Client requests a subsequent page

- **WHEN** an authorized client supplies the connection's end cursor as `after`
- **THEN** GraphQL MUST return the next stable page using the projection's
  keyset semantics

#### Scenario: Contract is extended

- **WHEN** the all-runs index is implemented
- **THEN** it MUST add no run mutation, hidden compatibility query, or second
  detailed-run projection; `operatorRunState` remains the detail and activity
  source

#### Scenario: Shared request session resolves the read

- **WHEN** `operatorRuns` or its selected `operatorRunState` detail read
  resolves an actor
- **THEN** it MUST consume the existing shared `RequestSession` resolution
  unchanged and MUST NOT create a route-specific actor, session, bootstrap, or
  fallback
