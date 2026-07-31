## ADDED Requirements

### Requirement: Exact directory identities recover after reprovisioning

Office Graph SHALL restore a retained directory identity after a newer active event only when the provider tenant, provider subject, provider identity, verified email, linked principal, and lifecycle state still identify the same accepted basis.

#### Scenario: Exact directory-created identity is reprovisioned

- **WHEN** an active directory identity is deprovisioned and a newer active event repeats the same trusted provider and identity basis without conflicts
- **THEN** Office Graph MUST reactivate the retained directory link and its directory-created human principal in place rather than creating a replacement or requiring review

#### Scenario: Reprovisioned identity basis conflicts

- **WHEN** a newer active event changes the provider identity, verified email, retained principal, or conflicts with another email-linked identity
- **THEN** Office Graph MUST retain deterministic review-required behavior and MUST NOT reactivate or relink the disabled identity
