## ADDED Requirements

### Requirement: External Reference Identity
Office Graph SHALL model external references as durable links between Office
Graph resources and provider records.

#### Scenario: External reference is stored
- **WHEN** an Office Graph record links to an external provider object
- **THEN** the external reference MUST store organization, external source or
  integration, provider, provider object type, external identifier, URL when
  available, sync state, source provenance, and related Office Graph resource

### Requirement: External References Are Not Domain Substitutes
Office Graph SHALL promote external references to typed resources when the
local product needs lifecycle, authorization, validation, query, approval,
revision, verification, or domain actions.

#### Scenario: Referenced external record becomes product-active
- **WHEN** an imported provider record needs Office Graph status, assignment,
  ownership, review, fix, verification, approval, or agent behavior
- **THEN** it MUST be represented by a typed local resource linked to the
  external reference

### Requirement: Raw Payload Archives Are Separate
Office Graph SHALL keep raw provider payloads separate from external reference
identity and typed resource state.

#### Scenario: Provider payload is archived
- **WHEN** a webhook, provider API response, model payload, or tool-call
  payload is kept for replay, debugging, provenance, or retention
- **THEN** it MUST be stored in a raw archive with typed envelope fields and
  MUST NOT become the normal query surface for product behavior
