# json-storage-policy Specification

## Purpose
Constrain JSON storage to appropriate opaque or evolving data while keeping core domain facts relational.
## Requirements
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

### Requirement: Native Form-Like Schemas Use Typed Versions
Office Graph SHALL model native configurable intake, form, survey,
questionnaire, approval, and field-builder behavior with versioned typed
definitions once the data affects product behavior.

#### Scenario: Native form definition affects product behavior
- **WHEN** an Office Graph-native form, intake template, approval
  questionnaire, configurable field set, or survey-like workflow drives
  authorization, routing, reporting, workflow state, agent context,
  verification, or API contract behavior
- **THEN** the design MUST use typed relational resources for definition
  versions, questions/fields, options, branching or condition rules,
  submissions, answers, and typed answer values instead of treating the
  definition and answers as opaque JSON

#### Scenario: External form payload is imported
- **WHEN** Office Graph receives a Typeform, Google Forms, Airtable,
  spreadsheet, customer survey, or other third-party form payload before a
  native model exists
- **THEN** the raw payload MAY be stored as JSON in a raw archive or external
  reference, but any extracted product behavior MUST follow the normal
  promotion path into typed storage

#### Scenario: Presentation metadata is unmodeled
- **WHEN** form layout, theme, display hints, conditional UI text, or
  third-party rendering metadata is not used for policy, routing, reporting,
  workflow state, or verification
- **THEN** it MAY remain JSON with an explicit envelope and review path until a
  later design promotes it
