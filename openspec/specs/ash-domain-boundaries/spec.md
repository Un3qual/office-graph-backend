# ash-domain-boundaries Specification

## Purpose
TBD - created by archiving change design-code-organization-and-boundaries. Update Purpose after archive.
## Requirements
### Requirement: Ash Domain Ownership
Each Ash domain and Ash resource SHALL belong to the bounded context that owns
the corresponding business lifecycle, validations, policies, and durable
records.

#### Scenario: A graph-addressable typed resource is added
- **WHEN** a typed resource participates in the work graph
- **THEN** the typed resource remains in its owning context and uses the graph
  context's public contract for graph identity and relationships

#### Scenario: A provider-neutral record is added
- **WHEN** a shared external concept such as a repository, pull request, check,
  review comment, or observability issue becomes first-class
- **THEN** its Ash resource is placed under the provider-neutral context that
  owns the concept rather than under a provider adapter

### Requirement: Public Ash Access
Cross-context callers and entrypoints MUST use exported domain commands,
queries, Ash actions, or read interfaces approved by the owning context.

#### Scenario: A resolver writes a resource
- **WHEN** a GraphQL resolver or JSON API handler performs a domain mutation
- **THEN** it calls the owning context's public command or approved Ash action
  rather than private resource internals

#### Scenario: A worker needs domain data
- **WHEN** an Oban worker, sync job, or agent task needs records from another
  context
- **THEN** it uses that context's exported query or read-model interface

### Requirement: Ash Policy Integration
Ash resources SHALL integrate with the authorization boundary for policy
decisions instead of duplicating authorization rules locally.

#### Scenario: A protected action is evaluated
- **WHEN** an Ash action requires authorization
- **THEN** the resource policy asks the authorization boundary for an
  explainable decision using actor, scope, classification, capability, and
  operation context

#### Scenario: A decision must be durable
- **WHEN** policy requires a denied, redacted, escalated, approval-gated, or
  sensitive-read decision to be durable
- **THEN** the Ash action path preserves the authorization decision reference
  for audit and operation correlation

### Requirement: Ash Mutation Side Effects
Ash changes, preparations, and notifiers MUST use shared contracts for
operation correlation, revisions, audit, domain events, tombstones, and raw
archives rather than writing another context's private tables directly.

#### Scenario: A task title is edited
- **WHEN** a mutable product record changes through an Ash action
- **THEN** the action path can record operation correlation and a typed
  revision through the approved shared contract

#### Scenario: A delete action is performed
- **WHEN** an Ash action soft-deletes a mutable product record
- **THEN** the action path uses the tombstone/soft-delete contract owned by the
  appropriate context and does not hard-delete normal product data
