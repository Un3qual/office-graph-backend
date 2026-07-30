## Context

The review findings cross the WorkOS transport, enterprise identity lifecycle,
human sessions, generated Ash GraphQL reads, and principal lookup schema. The
branch is unreleased, uses an accepted empty-database rebaseline, forbids new
raw SQL, and requires mutations to enforce read-before-write invariants inside
owning Ash transactions.

## Goals / Non-Goals

**Goals:**

- Close each validated review finding at its owning boundary.
- Preserve generated Ash GraphQL and Relay as the frontend data path.
- Keep connection and directory lifecycle decisions race-safe and auditable.
- Restore indexed canonical principal lookup without a SQL expression index.

**Non-Goals:**

- Add AuthKit, hosted WorkOS sessions, or WorkOS-owned authorization.
- Add unbounded conversation history or a new custom GraphQL resolver.
- Preserve data across the already accepted unreleased database reset.
- Introduce raw SQL, direct Ecto access, or explicit repository transactions.

## Decisions

1. The OTP HTTP adapter will pass `verify_peer`, the runtime CA store, and
   HTTPS hostname verification to every WorkOS request. This keeps the existing
   dependency-free adapter while authenticating the remote server; replacing
   the adapter solely for TLS configuration would add unnecessary surface.

2. The Relay query will use generated top-level Ash list fields for separate
   nonterminal/terminal execution and pending/resolved gate connections. The
   client will merge each pair active-first and then apply the existing
   100-record bound. This avoids nested per-execution over-fetching and
   preserves the same priority contract as the command projection without
   adding a manual resolver.

3. Human sessions issued by WorkOS will persist the internal
   `enterprise_connection_id` as authentication provenance. The Authentication
   boundary will validate that exact connection and tenant scope on every
   session resolution. A provider-tenant-only check cannot distinguish two
   internal connections to the same WorkOS organization.

4. Logout will resolve the local session before revocation and choose external
   logout behavior from its recorded authentication method. Generic OIDC may
   return a provider logout URI; WorkOS remains a passive local logout because
   Office Graph, not WorkOS, owns the session.

5. Directory deprovisioning will continue to lock the principal first, disable
   the exact directory link, and disable matching SSO links only when no other
   active linked directory basis remains for that principal and WorkOS tenant.
   SSO reconciliation will tolerate disabled historical links owned by the
   same principal while still rejecting conflicting or review-required links.

6. Directory binding will be exposed through the EnterpriseIdentity boundary.
   It will validate the management operation, authorize the target
   connection's exact scope, and use an Ash identity/upsert action so concurrent
   attempts create one binding. A returned existing binding must match both the
   requested connection and operation; otherwise the command fails closed.

7. The existing principal `email` attribute will be canonicalized to its
   trimmed lowercase form by an Ash change on every create/upsert. All
   reconciliation queries will filter that attribute and use its existing
   Ash identity index. A second copy of the same value would add migration and
   consistency risk without improving lookup behavior.

## Risks / Trade-offs

- [Risk] The split Relay query can retrieve up to 100 rows from both priority
  classes before applying the 100-row UI bound. → Mitigation: use top-level
  connections, keep every individual query bounded, and avoid multiplying gate
  reads per execution.
- [Risk] Adding the nullable session provenance column changes the unreleased
  reset schema. → Mitigation: generate it declaratively and prove setup from an
  empty database.
- [Risk] Connection disablement can race with a request that has already
  completed session validation. → Mitigation: validate on every session load;
  no session remains valid on its next request after the lifecycle change.
- [Risk] Historical disabled identity links could hide a true conflict. →
  Mitigation: tolerate them only when they remain linked to the same principal;
  nil, foreign-principal, or review-required links still fail closed.

## Migration Plan

Generate a declarative AshPostgres migration and snapshot for session
provenance. Principal lookup reuses the existing email identity index and needs
no schema change. The branch's existing reset notice remains authoritative:
development/test databases created before the rebaseline must be recreated.
Verification must run the empty-database migration baseline and schema-drift
checks.

## Open Questions

None.
