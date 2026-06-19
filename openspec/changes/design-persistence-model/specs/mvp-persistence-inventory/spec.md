## ADDED Requirements

### Requirement: MVP Resource Inventory
Office Graph SHALL define a first persistence inventory that separates
first-class product resources, nearby execution resources, software proving
resources, external-reference-only records, and raw archives.

#### Scenario: First-class product resources are selected
- **WHEN** the first database resource inventory is planned
- **THEN** it MUST include typed relational resources for organizations,
  workspaces, initiatives/projects, workstreams, graph items, graph
  relationships, signals, requirements, tasks, questions, decisions, checks,
  evidence, artifacts, conversations, conversation messages, rich text
  documents, external references, raw payload archives, and operation
  correlation records

#### Scenario: Immediate migration cut is selected
- **WHEN** the first MVP migration scope is selected
- **THEN** it MUST include the work-container, graph identity, graph
  relationship, core work-loop, conversation, rich text foundation, external
  reference, raw archive, operation correlation, external source, and software
  proving resources needed for the software review/fix/verification workflow

#### Scenario: Near-follow-up resources are reserved
- **WHEN** work packets, runs, run events, proposed graph changes, context
  expansion requests, final revision/audit/tombstone records, projection read
  models, or API/UI render caches are considered during the first migration
  cut
- **THEN** they MUST remain reserved typed concepts until their dedicated
  follow-on designs define fields, lifecycle, authorization, and operational
  behavior

#### Scenario: Nearby execution resources are reserved
- **WHEN** persistence planning accounts for agent and execution follow-ons
- **THEN** work packets, runs, run events, proposed graph changes, and context
  expansion requests MUST be reserved as typed relational concepts rather than
  generic attachments

### Requirement: Software Proving Resource Inventory
Office Graph SHALL include provider-neutral software proving resources without
making software concepts mandatory for all departments.

#### Scenario: Software workflow resources are planned
- **WHEN** the first software proving workflow is modeled
- **THEN** repositories, repository refs or branches, commits, pull requests,
  review threads, review comments, review findings, check runs, issues,
  observability issues, and observability events MUST be represented as
  first-class provider-neutral resources where Office Graph needs lifecycle,
  query, revision, verification, or agent behavior

#### Scenario: Review discussion becomes actionable
- **WHEN** an imported or native review comment contains actionable work
- **THEN** Office Graph MUST preserve the review comment as discussion context
  and MUST create or link a review finding for severity, status, waiver, fix,
  and verification behavior

#### Scenario: Observability workflow starts with Sentry
- **WHEN** the first observability integration is modeled
- **THEN** observability issues and events MUST use provider-neutral base
  resources, with Sentry-specific fields added only through justified
  extension tables

### Requirement: External Reference Inventory Boundary
Office Graph SHALL keep low-certainty or deferred workflow domains as external
references or artifacts until a workflow justifies first-class tables.

#### Scenario: Deferred department record is imported
- **WHEN** a design asset, campaign asset, social post, finance record,
  spreadsheet row, external document, external comment, or out-of-scope
  ticketing record is captured before its native workflow is selected
- **THEN** the record MUST start as an external reference or artifact unless
  accepted persistence design promotes the concept to a dedicated resource
