## ADDED Requirements

### Requirement: Durable OIDC Identity Link State

Office Graph SHALL persist provider-neutral OIDC reconciliation state keyed by
provider, provider tenant or issuer, and provider subject.

#### Scenario: Known OIDC subject returns

- **WHEN** a validated OIDC subject matches an active external identity link
  whose principal is active
- **THEN** Office Graph MUST resolve the same durable principal, MUST update
  bounded last-authenticated identity metadata, and MUST NOT relink the subject
  based only on a changed display identifier

#### Scenario: Unknown verified identifier cannot be linked

- **WHEN** a validated OIDC subject has no exact link and its verified
  identifier names no eligible principal
- **THEN** Office Graph MUST persist a deterministic `review_required` link
  state with a bounded reason and MUST refuse a session

#### Scenario: Verified identifier conflicts

- **WHEN** a new OIDC subject's verified identifier conflicts with an
  incompatible external link or principal
- **THEN** Office Graph MUST persist or return a deterministic conflict/review
  outcome and MUST NOT silently attach either identity

### Requirement: External Lifecycle Revalidation

Office Graph SHALL re-check external identity lifecycle state at login and
while loading a linked human session.

#### Scenario: External link is disabled before login

- **WHEN** a known external identity link is disabled or marked for review
- **THEN** future login MUST fail closed without changing historical principal
  or link provenance

#### Scenario: External link is disabled during a session

- **WHEN** an external identity link is disabled after a human session was
  issued
- **THEN** the next use of that session MUST fail closed even when the cookie
  and session row are otherwise unexpired and unrevoked
