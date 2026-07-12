# verification Specification

## Purpose
Define the separation and lifecycle of checks, evidence, and verified outcomes.
## Requirements
### Requirement: Checks And Evidence Are Distinct

Office Graph SHALL model checks separately from evidence.

#### Scenario: Completion criteria are defined

- **WHEN** a task, packet, requirement, review, or workflow defines what must
  be true
- **THEN** the desired condition must be represented as a check rather than as
  an unstructured note

#### Scenario: Proof is received

- **WHEN** a PR merge, CI result, Sentry quiet period, human approval, review
  decision, design approval, campaign result, finance reconciliation, or other
  proof arrives
- **THEN** it must be represented as evidence linked to the relevant checks and
  graph items

### Requirement: Verification Requires Evidence

Office Graph SHALL treat verification as evidence-based, not as an agent or
human status claim alone.

#### Scenario: Agent reports work complete

- **WHEN** an agent marks work complete
- **THEN** the system must keep the work unverified until required checks are
  satisfied, waived, or moved into monitoring according to policy

#### Scenario: Required evidence is missing

- **WHEN** any required check lacks passing evidence or an authorized waiver
- **THEN** the graph item must not be considered verified

### Requirement: Verification Traceability

Verification SHALL preserve traceability across signals, decisions, packets,
runs, artifacts, external references, and future failures.

#### Scenario: Future failure occurs

- **WHEN** a later Sentry event, CI failure, review regression, support
  escalation, campaign issue, finance exception, or other signal relates to
  prior work
- **THEN** the system must be able to link the failure back to relevant
  signals, decisions, work packets, runs, review findings, commits, checks,
  evidence, waivers, and revisions

### Requirement: Waivers Are Governed

Office Graph SHALL allow check waivers only through explicit authorization and
recorded reason.

#### Scenario: User waives a check

- **WHEN** a human waives a required check
- **THEN** the system must record the principal, permission basis, reason,
  affected check, affected graph item, time, and whether the waiver is
  temporary, permanent, or review-required

### Requirement: Monitoring State

Verification SHALL support monitoring states when proof requires time or
future signals.

#### Scenario: Outcome cannot be known immediately

- **WHEN** evidence depends on a future time window or external observation
  such as a Sentry quiet period, campaign performance, incident recurrence, or
  finance reconciliation
- **THEN** the graph item may enter monitoring with explicit required evidence,
  time window, owner, and failure conditions
