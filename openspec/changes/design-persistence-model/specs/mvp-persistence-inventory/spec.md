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

### Requirement: External Reference Inventory Boundary
Office Graph SHALL keep low-certainty or deferred workflow domains as external
references or artifacts until a workflow justifies first-class tables.

#### Scenario: Deferred department record is imported
- **WHEN** a design asset, campaign asset, social post, finance record,
  spreadsheet row, external document, external comment, or out-of-scope
  ticketing record is captured before its native workflow is selected
- **THEN** the record MUST start as an external reference or artifact unless
  accepted persistence design promotes the concept to a dedicated resource
