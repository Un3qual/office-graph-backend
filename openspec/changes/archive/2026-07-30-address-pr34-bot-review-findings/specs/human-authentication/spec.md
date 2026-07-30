## ADDED Requirements

### Requirement: Canonical principal identity lookup is declaratively indexed

Office Graph SHALL persist principal email in the canonical form used for
verified-email reconciliation and SHALL index that typed attribute through an
AshPostgres identity.

#### Scenario: Principal email is stored

- **WHEN** Office Graph creates a principal from an email containing case or
  surrounding whitespace
- **THEN** it MUST store the lowercase trimmed email and make reconciliation
  query the indexed canonical attribute

#### Scenario: Equivalent emails are written concurrently

- **WHEN** concurrent writes supply case or whitespace variants of the same
  email
- **THEN** canonicalization and the identity index MUST retain one principal
  identity rather than creating ambiguous variants
