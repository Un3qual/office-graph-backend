## ADDED Requirements

### Requirement: Software Review Resources Are Provider-Neutral
Office Graph SHALL represent repositories, refs, commits, pull requests, review
threads, review comments, and check runs in provider-neutral resources with
typed scope, lifecycle, provenance, and sync state.

#### Scenario: GitHub pull request is reconciled
- **WHEN** a GitHub adapter reconciles a pull request
- **THEN** shared title, state, repository, refs, authorship/source, provider
  version, scope, and lifecycle MUST be stored without requiring GitHub-only
  columns in the base resource

#### Scenario: GitHub-specific data is required
- **WHEN** a field or behavior has no provider-neutral meaning
- **THEN** it MUST be stored in a GitHub extension resource or raw archive and
  linked to the base resource

#### Scenario: Native record uses the same concept
- **WHEN** Office Graph later creates a native review comment or check result
- **THEN** the base resource MUST allow it without fabricating a GitHub source

### Requirement: Provider Versions Protect Reconciliation
Provider-neutral software resources SHALL retain the provider version or
ordering identity needed to prevent stale updates.

#### Scenario: Reconciliation returns an older version
- **WHEN** the incoming provider version precedes the stored version
- **THEN** the resource MUST preserve current state and record a skipped or stale
  sync outcome
