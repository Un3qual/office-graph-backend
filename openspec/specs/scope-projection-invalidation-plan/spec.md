# scope-projection-invalidation-plan Specification

## Purpose
Define how scope changes invalidate cached authorization explanations and projections.
## Requirements
### Requirement: Authorization Explanation Invalidation Planning
Office Graph SHALL plan invalidation for authorization explanations that
depend on scope hierarchy, closure rows, inheritance modes, sensitivity
inheritance, or related authorization facts.

#### Scenario: Scope hierarchy changes inherited authority
- **WHEN** a scope move, inheritance-mode change, closure repair, or scope
  lifecycle change can alter inherited authority or sensitivity inheritance
- **THEN** the implementation plan MUST invalidate, supersede, or recompute
  affected authorization explanation caches before those caches can support
  new authorization decisions

#### Scenario: Historical decision is reviewed after a move
- **WHEN** an auditor reviews an authorization decision recorded before a scope
  hierarchy change
- **THEN** Office Graph MUST preserve the policy bundle version and fact or
  closure-path anchors that explain the original decision without rewriting it
  to match the current hierarchy

#### Scenario: New decision is evaluated after a move
- **WHEN** a new authorization decision is evaluated after a scope hierarchy
  change commits
- **THEN** the authorization boundary MUST use the current applicable hierarchy
  version or fact state rather than stale explanation cache entries

### Requirement: Graph Projection Invalidation Planning
Office Graph SHALL plan graph projection invalidation for scope hierarchy
changes that can affect visibility, redaction, projection membership, counts,
rollups, or restricted placeholders.

#### Scenario: Scope move affects projection membership
- **WHEN** a scope move or repair changes effective scope visibility,
  inherited sensitivity, or authorization facts for any projected node, edge,
  artifact, conversation, external reference, revision summary, count, or
  preview
- **THEN** the owning projection layer MUST receive or derive an invalidation
  hint sufficient to refetch, rebuild, or mark stale the affected
  authorization-filtered projection

#### Scenario: Persisted projection read model is planned
- **WHEN** implementation introduces a persisted read model for inboxes,
  focused node neighborhoods, review surfaces, evidence chains, blocker views,
  work packet context, agent context, counts, rollups, or another graph
  projection
- **THEN** the plan MUST identify scope hierarchy source records,
  authorization inputs, sensitivity labels, cache key, invalidation event or
  stale marker, staleness contract, rebuild path, and operation correlation
  before the read model becomes durable MVP storage

#### Scenario: Projection spans multiple scopes
- **WHEN** a projection spans workspaces, initiatives, workstreams, teams,
  components, repositories, departments, integrations, external sources, or
  resource scopes
- **THEN** invalidation planning MUST treat each included item as governed by
  its own tenant, scope, sensitivity labels, and authorization facts rather
  than invalidating only the request's starting scope

### Requirement: Derived Context And Render Cache Invalidation Planning
Office Graph SHALL plan derived context and render cache invalidation for
scope hierarchy changes that affect user, agent, or integration-visible
context.

#### Scenario: Work packet or agent context depends on moved scope
- **WHEN** a work packet context package, execution package, embedded agent
  context, automatic agent context, or generated summary depends on records
  whose effective scope policy changes
- **THEN** the plan MUST mark the derived context stale, invalidated, or
  superseded and require recompilation through authorized projection or
  resource APIs before reuse

#### Scenario: Cached content crosses policy boundary
- **WHEN** cached projection, render, summary, count, or context output
  includes sensitive, redacted, restricted, external-provider-derived, or
  agent-generated content
- **THEN** invalidation planning MUST keep the cache scoped to the authorized
  viewer or policy context, or store only safe metadata that cannot leak
  restricted data after scope hierarchy changes

#### Scenario: Cache rebuild is asynchronous
- **WHEN** projection, render, or context cache rebuilds happen after the
  authoritative scope hierarchy mutation commits
- **THEN** the stale cache MUST be prevented from serving as current
  authorization-filtered truth until the rebuild completes under the current
  hierarchy and policy facts

### Requirement: Realtime Scope Invalidation Planning
Office Graph SHALL plan realtime delivery for scope hierarchy changes as
projection updates or invalidation hints, not as authoritative replacement
payloads.

#### Scenario: Scope hierarchy change commits
- **WHEN** a scope move, inheritance-mode change, scope lifecycle change, or
  closure repair commits
- **THEN** the owning domain or projection layer MUST publish a typed
  projection invalidation hint or stale marker after authorization-relevant
  durable state is committed

#### Scenario: Subscriber receives invalidation
- **WHEN** a user, agent, service account, integration, or system job
  subscribes to a projection affected by a scope hierarchy change
- **THEN** realtime delivery MUST include enough identity, version, or
  invalidation information for the subscriber to reconcile through the
  authorized projection API without exposing restricted payloads in the event
  itself

#### Scenario: Subscriber loses access after a scope move
- **WHEN** a scope move or repair causes a subscriber to lose or gain access,
  cross a sensitivity boundary, require approval, or receive redacted context
- **THEN** the realtime layer MUST stop, alter, redact, reauthorize, or replace
  delivery with an invalidation hint before exposing data governed by the new
  policy state
