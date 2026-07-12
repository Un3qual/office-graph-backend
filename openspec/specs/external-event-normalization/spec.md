# external-event-normalization Specification

## Purpose
Define the boundary that converts verified provider events into typed internal signals.
## Requirements
### Requirement: External Event Normalization Boundary
Office Graph SHALL distinguish raw payload archives, normalized events,
signals, provider-neutral resources, review findings, evidence, and sync
events.

#### Scenario: Provider or manual payload is received
- **WHEN** Office Graph receives a pasted manual input, webhook event, provider
  API payload, model output, or tool output
- **THEN** it MUST preserve the raw payload or text as an archive reference and
  derive a normalized event envelope before creating Office Graph domain
  records

#### Scenario: Normalized event becomes product state
- **WHEN** a normalized event implies work, evidence, or provider resource
  state
- **THEN** domain actions MUST decide whether to create or update a signal,
  provider-neutral resource, review finding, evidence item, external
  reference, sync event, or change proposal

### Requirement: Queryable Fields Are Extracted
Office Graph SHALL extract queryable ingestion fields into typed columns or
resources.

#### Scenario: Raw archive contains queryable data
- **WHEN** a raw payload includes provider id, source id, external URL, author,
  timestamps, state, severity, check result, evidence result, or affected
  resource references
- **THEN** queryable fields needed for authorization, replay, filtering,
  graph traversal, or verification MUST be extracted into typed records rather
  than queried from opaque raw payload JSON
