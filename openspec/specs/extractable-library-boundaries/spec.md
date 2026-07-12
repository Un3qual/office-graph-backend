# extractable-library-boundaries Specification

## Purpose
Identify reusable context boundaries while preventing premature package extraction.
## Requirements
### Requirement: Library Candidate Identification
Future library candidates SHALL be identified during code organization,
including identity/authentication, authorization/policy decisions, integration
primitives, revision/audit primitives, agent runtime primitives, rich text, and
ordered placement.

#### Scenario: A candidate domain is implemented
- **WHEN** implementation adds modules for a library-candidate domain
- **THEN** the module design avoids unnecessary dependencies on Phoenix
  controllers, product UI concepts, provider-specific adapters, or unrelated
  Office Graph contexts

#### Scenario: A product-specific concept is needed
- **WHEN** a reusable primitive needs Office Graph-specific behavior
- **THEN** the primitive receives it through configuration, behaviours,
  callbacks, typed inputs, or adapter modules rather than importing product
  internals directly

### Requirement: Extraction Gate
Future library candidates MUST remain internal bounded contexts until their
public API, tests, configuration surface, and data contracts are stable enough
to support extraction.

#### Scenario: Early package extraction is proposed
- **WHEN** a future plan proposes splitting a candidate into a separate Hex
  package or umbrella app during MVP
- **THEN** the plan records the second consumer, operational requirement, or
  stability evidence that justifies the split

#### Scenario: A boundary is not stable
- **WHEN** a candidate domain's API is still changing with product semantics
- **THEN** it remains an internal Boundary context rather than becoming a
  separate package

### Requirement: Product Assumption Isolation
Library-ready code SHALL isolate Office Graph product assumptions from generic
primitive logic.

#### Scenario: Rich text references graph items
- **WHEN** rich text needs live references to graph items, external references,
  or artifacts
- **THEN** the rich text primitive stores generic reference structures and uses
  Office Graph adapters for graph-specific resolution and authorization

#### Scenario: Authorization records policy decisions
- **WHEN** authorization logic records a decision for Office Graph resources
- **THEN** the reusable policy/decision primitive accepts typed target and
  context inputs rather than depending on GraphQL, controller, or UI modules

### Requirement: Extraction Readiness Tests
Library-candidate domains SHALL have tests that exercise public APIs and
document the assumptions that would matter during future extraction.

#### Scenario: A candidate domain adds behavior
- **WHEN** new behavior is added to authorization, integrations, revisions,
  audit, agent runtime, rich text, or ordered placement primitives
- **THEN** tests cover the public contract without relying on private modules
  from unrelated Office Graph contexts

#### Scenario: A candidate uses a callback
- **WHEN** a candidate domain relies on an adapter or callback
- **THEN** tests include a local fake or contract test for the callback
  behavior
