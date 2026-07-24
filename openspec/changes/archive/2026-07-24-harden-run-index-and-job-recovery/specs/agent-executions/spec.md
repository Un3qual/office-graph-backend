## ADDED Requirements

### Requirement: Orphan Recovery Starts After Worker Execution Deadlines
Office Graph SHALL enforce a finite execution deadline for every production
Oban worker. The global Lifeline rescue threshold MUST be strictly greater than
the maximum worker deadline so that Lifeline cannot make a job available while
its original worker is still permitted to execute.

#### Scenario: Adapter ignores its manifest timeout
- **WHEN** an agent adapter or another worker operation remains blocked beyond
  its worker deadline
- **THEN** Oban MUST terminate that execution and apply the existing retry
  contract before Lifeline can rescue the job

#### Scenario: Worker process is lost
- **WHEN** a worker process or node disappears without completing its job
- **THEN** Lifeline MUST make the orphan eligible again only after the maximum
  live-worker deadline has elapsed
