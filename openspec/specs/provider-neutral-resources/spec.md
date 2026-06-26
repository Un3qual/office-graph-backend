# provider-neutral-resources Specification

## Purpose
TBD - created by archiving change design-persistence-model. Update Purpose after archive.
## Requirements
### Requirement: Provider-Neutral Base Resources
Office Graph SHALL use provider-neutral base resources for concepts that can
come from multiple providers, departments, or native Office Graph workflows.

#### Scenario: Shared external concept is modeled
- **WHEN** a resource concept such as repository, branch/ref, commit, pull
  request, review thread, review comment, check run, issue, observability
  issue, document, or source event is introduced
- **THEN** the base table MUST model the shared identity, state, scope,
  provenance, sync, and lifecycle fields without requiring provider-specific
  columns for unrelated providers

### Requirement: Provider Identity Is Explicit
Provider-neutral resources SHALL retain explicit provider and external-source
identity when they originate outside Office Graph.

#### Scenario: Provider-backed record is stored
- **WHEN** a provider-neutral row represents data from GitHub, GitLab, Sentry,
  a design system, a finance system, or another external source
- **THEN** it MUST reference the organization, integration or external source,
  provider object type, provider identifier when available, sync state, and
  source provenance needed for reconciliation

### Requirement: Native Office Graph Resources Use Same Base Model
Office Graph SHALL allow native Office Graph workflows to use the same
provider-neutral base resources as imported workflows where the domain concept
is shared.

#### Scenario: Native review comment is created
- **WHEN** Office Graph creates a native review comment, finding, check result,
  or observability note
- **THEN** it MUST be representable without pretending to come from GitHub,
  GitLab, Sentry, or another external provider
