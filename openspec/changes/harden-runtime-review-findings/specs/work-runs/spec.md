## MODIFIED Requirements

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
