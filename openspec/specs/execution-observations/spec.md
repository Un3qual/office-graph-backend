# execution-observations Specification

## Purpose
Define durable observations of externally owned execution without treating them as Office Graph runs.
## Requirements
### Requirement: Observations Record Externally Owned Execution Activity

Office Graph SHALL represent provider-owned, integration-owned, external-agent,
and human-owned execution-like activity as execution observations rather than
as work runs or agent executions.

#### Scenario: Provider check is imported

- **WHEN** Office Graph imports a CI check, deployment status, provider check
  run, external review-bot result, or integration job status
- **THEN** Office Graph MUST create or update an execution observation that
  records source identity, observed status, source timestamp, ingestion
  timestamp, external reference, replay or idempotency basis, and related graph
  or work-run links

#### Scenario: Human handoff is recorded

- **WHEN** a human marks a handoff milestone, review activity, completion note,
  exception note, or manual execution status that Office Graph did not
  supervise directly
- **THEN** Office Graph MUST represent that activity as a human-sourced
  execution observation or another typed human-owned record rather than as an
  internal agent execution

### Requirement: Observations Preserve Source Freshness And Trust

Office Graph SHALL preserve enough source, freshness, and trust information to
decide whether an observation can support verification.

#### Scenario: Observation is normalized

- **WHEN** a source observation is normalized for cross-provider verification
- **THEN** Office Graph MUST preserve provider/source identity, actor mapping
  when available, original source status, normalized status, source time,
  ingestion time, freshness state, trust level, and raw archive or
  provider-specific extension references when applicable

#### Scenario: Observation becomes stale

- **WHEN** source commit, artifact version, packet version, graph target,
  provider status, policy, or relevant context changes after an observation is
  recorded
- **THEN** Office Graph MUST be able to mark the observation stale,
  superseded, disputed, or requiring refresh before it is used for
  verification

### Requirement: Observations Are Not Accepted Evidence By Default

Office Graph SHALL require an explicit evidence-acceptance step before an
execution observation satisfies a verification check.

#### Scenario: Observation is relevant to a check

- **WHEN** a provider check, human note, integration job, or external agent
  result appears relevant to a verification check
- **THEN** Office Graph MUST treat it as an evidence candidate until policy or
  an authorized principal accepts it for a specific check, claim, or result

#### Scenario: Observation is insufficient

- **WHEN** an observation is stale, untrusted, unauthenticated, unrelated to the
  selected target, missing actor mapping, or insufficient under policy
- **THEN** Office Graph MUST NOT let the observation satisfy verification and
  MUST preserve the rejection, stale state, or missing requirement reason

### Requirement: Provider Detail Remains Outside The Common Observation Core

Office Graph SHALL keep provider-specific and large raw details in provider
extension records or raw archives while storing common verification facts in
execution observations.

#### Scenario: Provider payload has extra detail

- **WHEN** a provider check, review bot, deployment, or integration event
  contains source-specific fields, logs, annotations, payloads, or artifacts
- **THEN** the execution observation MUST store only common source,
  freshness, status, trust, and linkage facts while referencing provider
  extension records, artifacts, or raw archives for the detailed payload

### Requirement: Initial Execution Observations Preserve Source And Trust

Office Graph SHALL persist human/manual and simple provider-like execution
observations with enough source, freshness, and trust information for
verification decisions.

#### Scenario: Observation is recorded

- **WHEN** an authorized actor records a human note, manual status, test
  result, provider check status, or integration job status for selected work
- **THEN** Office Graph MUST record source kind, source identity, observed
  status, normalized status, source timestamp, ingestion timestamp, freshness
  state, trust basis, operation correlation, and related work-run or graph
  references

#### Scenario: Observation links stay in scope

- **WHEN** an observation create supplies a work run, operation correlation,
  verification check, or graph item reference
- **THEN** Office Graph MUST reject missing or cross-scope references before
  recording the observation and MUST exclude malformed cross-scope child rows
  from scoped work-run summaries

#### Scenario: Observation links match the target run contract

- **WHEN** an observation create supplies a verification check or graph item
  for a packet-backed work run
- **THEN** Office Graph MUST reject same-scope references that are not part of
  the selected packet sources or required-check targets before recording the
  observation and before those rows can influence run summaries or lifecycle
  recomputation

#### Scenario: Observation source is duplicated

- **WHEN** the same source identity and replay or idempotency key is recorded
  more than once in the same organization and workspace
- **THEN** Office Graph MUST return the existing observation or reject the
  duplicate according to the owning command's idempotency rules

#### Scenario: Observation source is duplicated concurrently

- **WHEN** multiple observation record commands concurrently use the same
  source identity and replay or idempotency key in the same organization and
  workspace
- **THEN** Office Graph MUST serialize the source replay lookup and insert so
  exactly one source observation is created and competing commands return the
  existing observation or a domain idempotency conflict instead of a database
  unique-key error

#### Scenario: Observation source has no replay key

- **WHEN** an observation is recorded without a replay or idempotency key, or
  with a blank key that normalizes to no key
- **THEN** Office Graph MUST treat the observation as non-idempotent input so
  repeated same-source observations create distinct records rather than being
  blocked by source-idempotency uniqueness

#### Scenario: Observation replay trust facts change

- **WHEN** the same source identity and replay or idempotency key is reused
  with different freshness state, trust basis, status, work-run, check, or graph
  linkage
- **THEN** Office Graph MUST reject the replay as an idempotency conflict
  instead of returning an observation recorded with different evidence facts

#### Scenario: Observation operation replay facts change

- **WHEN** the same observation-record operation idempotency key is reused with
  different source, idempotency key, status, freshness, trust, rationale, or
  work-run/check/graph linkage
- **THEN** Office Graph MUST reject the replay as an operation conflict instead
  of returning an observation recorded for different execution facts

### Requirement: Initial Observations Can Become Evidence Candidates

Office Graph SHALL allow an execution observation to produce an evidence
candidate without treating the observation as accepted evidence by default.

#### Scenario: Observation is relevant to a check

- **WHEN** an observation is linked to a required verification check or work
  run evidence expectation
- **THEN** Office Graph MUST be able to create an evidence candidate that
  references the observation, target check, claim, trust basis, freshness
  state, source, and operation correlation

#### Scenario: Graph-only observation targets a check graph item

- **WHEN** an observation for a work run omits a verification check id but links
  to the graph item for a required verification check
- **THEN** Office Graph MUST allow an evidence candidate for that same required
  check to reference the observation while still rejecting unrelated graph-only
  observations

#### Scenario: Observation is stale or untrusted

- **WHEN** an observation is stale, untrusted, unauthenticated, unrelated to
  the target, or outside the actor's authorized scope
- **THEN** Office Graph MUST NOT accept it as evidence and MUST preserve the
  rejection or missing-requirement reason

### Requirement: Execution Observation Recording Has Supported Product Commands

Office Graph SHALL expose run observation recording through authenticated
GraphQL and JSON API commands over the Runs domain boundary.

#### Scenario: Operator records an observation

- **WHEN** an authorized operator submits run, check, source graph item,
  provider/source identity, observed and normalized status, freshness, trust,
  rationale, and idempotency data
- **THEN** the command MUST preserve run-contract validation, source replay,
  operation replay, lifecycle updates, and typed observation provenance

#### Scenario: Observation conflicts with its run

- **WHEN** the submitted check, graph item, source identity, or replay input is
  outside the run packet contract or conflicts with an existing observation
- **THEN** the command MUST fail without changing run execution state
