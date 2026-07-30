## ADDED Requirements

### Requirement: Unreleased migration history is replaced only as a verified baseline

Office Graph SHALL permit migration-history replacement before its first
supported release only through an accepted OpenSpec rebaseline that names the
reset boundary, rebuilds the current schema, and verifies all required
application behavior from an empty database.

#### Scenario: Old migration is individually edited

- **WHEN** a change proposes piecemeal edits to an old migration without
  replacing the logical unreleased baseline
- **THEN** verification MUST reject the edit or require the change to define
  the complete rebaseline and empty-database proof

#### Scenario: Rebaseline is accepted

- **WHEN** an accepted rebaseline replaces old migration files
- **THEN** the change MUST preserve the old history in Git, document the local
  reset requirement, remove obsolete migration-specific behavior, and prove
  current migrations plus setup from an empty database
