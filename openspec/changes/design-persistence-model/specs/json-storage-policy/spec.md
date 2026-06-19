## ADDED Requirements

### Requirement: JSON Storage Boundary
Office Graph SHALL restrict JSON/JSONB storage to raw, replay, debugging,
model, tool-call, or explicitly accepted unmodeled payload use cases.

#### Scenario: Queryable product field is proposed as JSON
- **WHEN** a field is used for authorization, graph traversal, workflow state,
  revision history, filtering, reporting, integration reconciliation, agent
  context assembly, verification, or API contract behavior
- **THEN** the field MUST be modeled with typed columns, lookup tables, join
  tables, extension tables, or typed resources rather than generic JSON

#### Scenario: Raw payload archive is stored
- **WHEN** JSON is used for a webhook, provider API payload, model prompt or
  output, tool-call request or response, replay snapshot, or temporary
  unmodeled edge case
- **THEN** the row MUST include typed envelope fields for organization, source,
  received time, payload kind, digest, related resource or event, retention
  classification, and replay/debug state

### Requirement: JSON Exceptions Require Promotion Path
Office Graph SHALL require a promotion path when temporary unmodeled JSON
starts carrying product behavior.

#### Scenario: JSON archive field becomes useful
- **WHEN** data inside a JSON archive becomes needed for policy, query,
  reporting, graph traversal, agent context, integration reconciliation, or
  verification
- **THEN** a follow-on design MUST extract it into typed relational storage or
  explicitly preserve the exception with rationale and review date
