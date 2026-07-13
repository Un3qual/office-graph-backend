# change-proposal-authorization Specification

## Purpose
Define authorization checks for creating, reviewing, approving, and applying change proposals.
## Requirements
### Requirement: Change Proposal Authorization
Office Graph SHALL authorize proposing, approving, and applying change
proposals separately.

#### Scenario: Agent proposes a change
- **WHEN** an agent proposes a graph or domain mutation
- **THEN** authorization MUST evaluate agent principal, delegator or trigger
  authority, work packet autonomy policy, tool or integration scope, target
  scope, sensitivity labels, organization policy, context expansion, and any
  temporary grants

#### Scenario: Change proposal requires approval
- **WHEN** a change proposal affects sensitive data, external writes,
  credentials, destructive state, cross-scope access, waivers, approvals, or
  high-risk lifecycle transitions
- **THEN** Office Graph MUST keep the change unapplied until required approval
  gates and separation-of-duties rules are satisfied

#### Scenario: Human applies a change
- **WHEN** a human applies or rejects a change proposal
- **THEN** Office Graph MUST evaluate the human principal's capability,
  target scope, sensitivity policy, approval eligibility, and any conflict with
  author/delegator/requester separation-of-duties rules
