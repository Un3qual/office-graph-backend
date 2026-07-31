## ADDED Requirements

### Requirement: Context folders are grouped by responsibility
Internal files in a crowded bounded context SHALL be grouped into
responsibility-based subfolders while public context modules remain at
`lib/office_graph/<context>.ex` and public module names remain stable.

#### Scenario: Context folder becomes crowded
- **WHEN** one context contains resources, commands, changes, adapters, workers, projections, and value objects at the same physical level
- **THEN** those files MUST be moved into clear responsibility-based subfolders without adding delegation layers or changing domain ownership

#### Scenario: File is moved for navigation
- **WHEN** implementation changes only a module's physical path
- **THEN** its public module name, owning context, API behavior, and dependency direction MUST remain unchanged

#### Scenario: Other backend folder is reviewed
- **WHEN** the resource-normalization pass identifies another crowded backend or web folder
- **THEN** the same responsibility and stable-module-name rule MUST be applied when grouping materially improves navigation
