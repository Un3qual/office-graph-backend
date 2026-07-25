## ADDED Requirements

### Requirement: Operator Console Provides A Focused Run Agent Surface
Office Graph SHALL add one run-aware conversation and agent-control surface to
the existing operator workflow.

#### Scenario: Operator views agent execution
- **WHEN** an authorized operator selects a run with agent activity
- **THEN** the UI MUST show bounded execution status, conversation messages,
  safe context rationale, pending approvals/expansions, failures, retries, and
  proposal/evidence outputs

#### Scenario: Operator invokes or cancels agent
- **WHEN** an allowed invocation or cancellation affordance is active
- **THEN** the UI MUST submit the narrow Relay command, disable only its owning
  action while pending, and authoritatively refresh execution and run state

#### Scenario: Operator resolves request
- **WHEN** an allowed approval or context-expansion request is selected
- **THEN** the UI MUST display the exact bounded request, collect required
  reason/scope data, submit a versioned resolution, and handle stale conflicts by
  refetching

### Requirement: Agent Surface Is Not General Chat Or Administration
Office Graph SHALL keep the first surface scoped to the selected run and graph
item and SHALL expose no generic agent-definition, credential, role, or
cross-workspace chat administration.

#### Scenario: Operator navigates outside selected run
- **WHEN** the selected run or graph item changes
- **THEN** drafts and subscriptions MUST bind to the new authorized context and
  MUST NOT carry prior restricted conversation or approval state across it
