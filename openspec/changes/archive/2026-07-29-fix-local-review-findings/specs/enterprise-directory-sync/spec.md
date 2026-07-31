## ADDED Requirements

### Requirement: Present directory fields are validated strictly

Office Graph SHALL distinguish an absent optional WorkOS directory field from
a present field whose type, length, or normalized value is invalid.

#### Scenario: Optional directory field is absent

- **WHEN** a supported directory event omits an optional bounded profile field
- **THEN** normalization MUST accept the field as absent

#### Scenario: Optional directory field is malformed

- **WHEN** a supported directory event supplies an optional field with the
  wrong type, a blank normalized value, or a value beyond its byte limit
- **THEN** Office Graph MUST reject the delivery before persistence or enqueue

### Requirement: Organization mappings inherit into workspace authorization

Office Graph SHALL treat an active external group-role mapping with no
workspace as organization-wide authority.

#### Scenario: Organization-wide mapped member selects login scope

- **WHEN** an active mapped member has an active organization-wide mapping
- **THEN** login-scope discovery MUST include the organization with a nil
  workspace

#### Scenario: Organization-wide mapped member acts in a workspace

- **WHEN** an active mapped member requests a mapped capability in a workspace
  belonging to the mapping's organization
- **THEN** the organization-wide mapping MUST contribute the mapped role in
  that workspace

#### Scenario: Workspace mapping targets another workspace

- **WHEN** an active mapping names a different non-nil workspace
- **THEN** it MUST NOT grant authority in the requested workspace
