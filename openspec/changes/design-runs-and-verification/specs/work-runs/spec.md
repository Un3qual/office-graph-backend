# Work Runs

## ADDED Requirements

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
  requirement, proposed change, graph item set, conversation request, incident,
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
  observations, proposed graph changes, approval gates, evidence candidates, or
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

- **WHEN** an agent execution, human handoff, provider observation, proposed
  change, or verification step fails inside a work run
- **THEN** Office Graph MUST preserve the child failure and MUST update the
  work-run aggregate status to blocked, failed, partial, retryable, or another
  policy-defined state with traceable reasons

### Requirement: Work Runs Preserve Parent Execution Traceability

Office Graph SHALL preserve parent-level operation, authority, evidence, audit,
and revision traceability for work runs.

#### Scenario: Work run changes product state

- **WHEN** execution inside a work run applies a proposed graph change, creates
  evidence, satisfies verification, records a waiver, or changes a related
  product record
- **THEN** the resulting records MUST preserve references to the work run and
  operation correlation where applicable

#### Scenario: Work run is superseded

- **WHEN** a packet version, selected work target, authority posture, required
  check, or material context changes after a work run starts
- **THEN** Office Graph MUST be able to mark the work run stale, superseded,
  blocked, or requiring re-evaluation while preserving its execution history
