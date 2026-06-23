# domain-attachments Specification

## Purpose

Define how domain-specific records, provider records, and external references
attach to the shared Office Graph without redefining core graph, tenancy, or
authorization semantics.

## Requirements

### Requirement: Typed Domain Attachments

Office Graph SHALL attach domain-specific records to the shared work graph
through typed graph participation.

#### Scenario: Domain record needs graph behavior

- **WHEN** a pull request, commit, review comment, CI annotation, Sentry event,
  design annotation, campaign brief, social post, finance exception, document,
  spreadsheet row, or operations event needs conversation, review, provenance,
  relationships, evidence, or agent context
- **THEN** it MUST be attachable to an addressable graph item with domain
  resource type, owning scope, source system when applicable, and provenance

#### Scenario: Domain record remains outside graph

- **WHEN** a domain record is stored only as raw imported context and does not
  need conversation, review, provenance, relationships, evidence, or agent
  context
- **THEN** it MAY remain outside the addressable graph until a domain action or
  accepted design promotes it into graph participation

### Requirement: Provider-Neutral Base Concepts

Office Graph SHALL prefer provider-neutral typed concepts for shared external
and departmental records.

#### Scenario: Shared concept is modeled

- **WHEN** concepts such as repositories, branches, commits, pull requests,
  issues, review comments, checks, design assets, campaign assets, documents,
  finance records, or social posts are modeled
- **THEN** the model MUST prefer provider-neutral typed resources before
  adding provider-specific extension resources

#### Scenario: Provider-specific behavior is needed

- **WHEN** GitHub, GitLab, Figma, Google Drive, Slack, Sentry, finance tools,
  social platforms, or other providers expose source-specific data or behavior
  that cannot fit the provider-neutral resource cleanly
- **THEN** a provider-specific extension resource MAY be added without
  replacing the provider-neutral base concept

### Requirement: External References

Office Graph SHALL represent links to external systems through typed external
references with source provenance.

#### Scenario: External object is linked

- **WHEN** an Office Graph record links to a provider object
- **THEN** the external reference MUST identify provider, source identifier,
  URL when available, sync state, source provenance, owning organization, and
  related Office Graph item or domain resource

#### Scenario: Provider object changes

- **WHEN** an external provider object is updated, deleted, moved, renamed, or
  becomes inaccessible
- **THEN** the external reference MUST be able to represent sync state and
  source provenance without treating the external provider as the sole source
  of Office Graph truth

### Requirement: Product-Level Promotion To Dedicated Resource

Office Graph SHALL allow categories of attached or imported data to become
dedicated typed resources when product behavior requires domain semantics.

#### Scenario: Attached data category gains behavior

- **WHEN** a category of attached or imported data needs its own lifecycle,
  authorization rules, validation rules, query patterns, revision history,
  approvals, or domain actions
- **THEN** the product model MUST represent that category as a dedicated typed
  resource that participates in the graph

#### Scenario: Individual record becomes typed resource instance

- **WHEN** an individual attachment or imported provider record is converted or
  linked to a dedicated typed resource instance
- **THEN** the conversion MUST use an existing accepted resource type and an
  explicit domain action rather than creating arbitrary per-record schema

#### Scenario: Product-level promotion preserves provenance

- **WHEN** a category of attachments or imported records is promoted into a
  dedicated typed resource
- **THEN** Office Graph MUST preserve provenance from original attachments or
  external references to the new resource instances

### Requirement: Attachments Do Not Override Core Semantics

Office Graph SHALL prevent domain attachments from redefining core graph,
tenancy, and authorization semantics.

#### Scenario: Attachment crosses scope boundary

- **WHEN** a domain attachment links items across teams, departments,
  repositories, workspaces, initiatives, providers, or external systems
- **THEN** the attachment MUST NOT grant access by itself and MUST remain
  filtered by the same authorization and classification rules as graph
  projections

#### Scenario: Department-specific model is introduced

- **WHEN** a department-specific model is introduced for engineering, design,
  marketing, social, finance, operations, or leadership
- **THEN** it MUST attach through shared graph semantics rather than creating a
  separate product ontology for that department
