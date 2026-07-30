## Context

Office Graph already has an OIDC authorization-code flow, one-time
server-backed login guards, durable principals, external identity links,
browser sessions, authentication evidence, and internal role/capability
authorization. The implemented provider is intentionally configured for the
local Authentik identity lab. There is no enterprise connection registry,
WorkOS adapter, directory user/group storage, provisioning webhook, or
external-group role evaluation.

The accepted product decision is to use WorkOS for enterprise SSO and managed
Directory Sync, but not WorkOS AuthKit. Office Graph must continue to own the
browser session, internal identity lifecycle, authorization facts, and all
product permissions. WorkOS credentials and signed deliveries are external
integration inputs, not an alternate user database or authority store.

The implementation crosses Authentication, Identity, Authorization,
Integrations, Operations, Tenancy, Phoenix, Oban, and PostgreSQL. It must
remain fully testable without a WorkOS account, use Ash and AshPostgres for
persistence, and add no repository-authored raw SQL.

## Goals / Non-Goals

**Goals:**

- Add organization-bound WorkOS SSO without AuthKit while retaining the
  existing Office Graph login transaction, principal reconciliation, durable
  session, scope selection, and authentication evidence.
- Add provider-neutral typed resources for enterprise connections,
  directories, users, groups, memberships, and group-to-role mappings.
- Verify, archive, deduplicate, and asynchronously apply WorkOS Directory Sync
  events through owning Ash actions.
- Reconcile provisioning-time directory users and login-time SSO profiles to
  one principal, fail closed on conflicts and deprovisioning, and preserve
  historical provenance.
- Make active directory group membership an internal authorization fact only
  through an explicit group-to-role mapping.
- Keep local Authentik OIDC and deterministic fake adapters as the normal
  development and CI path.

**Non-Goals:**

- Adopt AuthKit, WorkOS-hosted sessions, WorkOS user management, or WorkOS
  authorization as Office Graph product authority.
- Build a polished enterprise administration UI, connection-creation wizard,
  or customer self-service WorkOS organization provisioning.
- Import arbitrary WorkOS raw attributes into queryable JSON/JSONB product
  state.
- Trust SSO group claims as capabilities or create roles automatically from
  unconfigured external group names.
- Require credentialed WorkOS smoke tests in canonical verification.
- Replace Authentik as the local OIDC/SAML fixture or remove the repo-owned
  deterministic directory contract path.

## Decisions

### 1. Add an EnterpriseIdentity boundary with provider-neutral resources

`OfficeGraph.EnterpriseIdentity` will own an Ash domain and the following
resources:

- `EnterpriseConnection`: maps one active provider organization to an Office
  Graph organization and optional governing workspace; records provider,
  provider organization ID, lifecycle state, and directory requirement.
- `Directory`: records the provider directory ID and lifecycle beneath a
  connection.
- `DirectoryUser`: records provider user ID, IdP ID, normalized email, bounded
  human profile fields, lifecycle, provider update time, principal, and
  external identity link.
- `DirectoryGroup`: records provider group ID, name, lifecycle, and provider
  update time.
- `DirectoryMembership`: records one user/group fact with active/removed
  lifecycle and a private active identity slot so add/remove/re-add is
  replay-safe without a partial index.
- `DirectorySyncEvent`: records provider event ID, event kind, content hash,
  archive and operation references, received/provider timestamps, processing
  state, and bounded result.

`OfficeGraph.Authorization` will own `ExternalGroupRoleMapping`, because it is
an authorization fact linking an active directory group to an existing
internal role and exact organization/workspace scope. Directory resources do
not depend back on Authorization; the one-way mapping preserves compile-time
boundary direction.

All IDs use generated Ash UUID attributes backed by PostgreSQL 18 `uuidv7()`.
Relationships supply their foreign-key attributes. Resources use ordinary
identities, `nils_distinct?`, and private identity slots rather than partial
indexes or handwritten predicates.

Alternative considered: store WorkOS users and groups in raw payload JSON.
Rejected because users, lifecycle, membership, and authorization mappings are
core queryable domain state.

Alternative considered: put WorkOS-specific columns directly on principals,
external identity links, and roles. Rejected because it couples reusable
identity/authorization concepts to one vendor and prevents another directory
adapter from using the same model.

### 2. Keep browser authentication provider-neutral and Office Graph-owned

The existing browser transaction will be generalized from an OIDC-only map to
a bounded login transaction that names its selected provider and enterprise
connection. The callback trusts only the provider and connection captured
before redirect; callback parameters cannot select either.

Local OIDC continues to use Oidcc with nonce and PKCE. WorkOS SSO uses a new
`EnterpriseSsoClient` behaviour and production WorkOS adapter:

1. read and lock the active enterprise connection selected by its internal ID;
2. create random state and a one-time ten-minute database guard;
3. build the WorkOS SSO authorization URL with the configured client ID,
   captured redirect URI, state, and bound WorkOS organization ID;
4. atomically consume the guard before exchanging the callback code;
5. exchange the code server-side using the configured WorkOS API credential;
6. normalize only stable profile identity fields;
7. reconcile an external link using provider `workos_sso`, the bound WorkOS
   organization as provider tenant, and the connection-scoped IdP subject;
8. resolve current internal scope and issue the existing `human_web` session.

WorkOS access tokens, authorization codes, raw profile attributes, and AuthKit
cookies are never persisted. WorkOS logout support is not assumed; local
logout still revokes the Office Graph session and completes passively.

Alternative considered: replace the existing flow with AuthKit. Rejected
because it would move user/session ownership to WorkOS, make product behavior
more vendor-dependent, and duplicate durable Office Graph identity and
authorization state.

Alternative considered: force WorkOS through the existing generic OIDC client.
Rejected because WorkOS standalone SSO returns a normalized SSO profile rather
than an IdP ID token validated through Office Graph's OIDC discovery worker.
The two adapters share the outer transaction/session orchestration but retain
accurate provider-specific exchange contracts.

### 3. Use signed, archived, replay-safe asynchronous Directory Sync ingestion

Phoenix will expose one API-only WorkOS webhook route. The raw body reader will
buffer only the GitHub and WorkOS webhook paths. Ingestion will:

1. require the bounded WorkOS signature header;
2. verify the timestamped HMAC over the exact raw body with a short clock-skew
   tolerance before JSON decoding;
3. validate the event envelope and supported directory event type;
4. resolve the directory and tenant from the provider directory ID, never from
   caller-supplied Office Graph scope;
5. start an operation for the registered webhook principal;
6. archive the exact delivery through the existing raw-provider archive;
7. create or replay one `DirectorySyncEvent` by provider event ID and content
   hash;
8. enqueue one Oban job for a newly accepted event.

The worker loads the archived body and invokes one transactional Ash action for
the specific user, group, or membership event. Duplicate deliveries return
success without a second job. A reused event ID with a different hash fails as
a conflict. Provider update timestamps prevent an older delivery from
overwriting a newer lifecycle state. Unknown, malformed, or unsupported events
are rejected with bounded public errors and no partial product mutation.

Alternative considered: apply provisioning synchronously in the controller.
Rejected because provider retries and response deadlines should not own a
multi-resource identity transaction, while Oban already provides durable
retry and failure handling.

Alternative considered: implement a public SCIM server in this slice.
Rejected because WorkOS Directory Sync is the accepted managed adapter.
Provider-neutral Ash actions and fake event adapters preserve a later direct
SCIM path without duplicating the current ingestion surface.

### 4. Reconcile directory lifecycle through one locked Ash action

Directory user create/update locks the exact directory user identity, relevant
normalized-email principals, and compatible external links. It creates one
human principal when provisioning policy permits, or links the one eligible
existing principal; ambiguous or incompatible identifiers produce a durable
review state. It creates a `workos_directory` external identity link distinct
from the login-time `workos_sso` link, with both links resolving to the same
principal.

Directory deactivation or deletion marks the directory user and directory link
disabled in-table, disables matching WorkOS SSO links for the same principal
and provider organization, and makes existing sessions fail on their next
load. The principal is disabled only when no other accepted active identity
basis remains. Historical principals, links, memberships, sessions, audit
evidence, ownership, and authorship are retained.

If an enterprise connection requires directory provisioning, WorkOS login must
find an active matching directory user for the reconciled principal. A
connection without a directory, or explicitly configured for optional
provisioning, can use the existing verified-identifier linking policy.

These mutations use Ash actions, `FOR UPDATE` query locks, identities/upserts,
and action-managed transactions. No outer `Repo.transaction` is introduced.

### 5. Treat directory groups as policy facts, not copied role assignments

An active `ExternalGroupRoleMapping` names an existing internal role and exact
scope. Authorization capability and login-scope resolution will combine:

- direct active role assignments; and
- active directory users whose active memberships reference an active group
  with an active mapping to that role and scope.

Role capabilities remain the only source of capability keys. SSO claim groups,
unmapped directory groups, removed memberships, disabled users, disabled
directories, and disabled connections grant nothing. This avoids creating and
deleting copied `RoleAssignment` rows, eliminates source-ownership ambiguity,
and makes membership removal effective on the next authorization read.

The added authorization reads will use bounded Ash queries and set-based
filters. Focused query-count coverage will prevent per-membership or per-group
N+1 behavior.

Alternative considered: materialize one role assignment per directory
membership. Rejected because an assignment may also be granted manually or by
another directory, making safe revocation require a second provenance model
and read-modify-write coordination. Evaluating mapped membership as a current
policy fact is both clearer and safer.

### 6. Keep secrets and HTTP behind narrow adapters

WorkOS API credentials and the endpoint-level webhook secret remain behind an
`OfficeGraph.EnterpriseIdentity.SecretStore` behaviour. Runtime configuration
stores explicit secret references, never secret values in product tables. The
default environment adapter resolves `env:` references; tests use an in-memory
adapter. The endpoint-level webhook secret is resolved before the untrusted
payload is decoded, and only then can the verified provider directory ID select
an internal enterprise connection and tenant scope.

The WorkOS SSO client uses a small project-owned HTTP behaviour with a
production `:httpc` adapter, matching the existing GitHub integration pattern
and avoiding an unofficial WorkOS Elixir SDK. It enforces HTTPS base URLs,
bounded timeouts, expected status codes, response-size limits, and typed
response parsing. Tests replace the HTTP behaviour and never perform network
requests.

### 7. Configuration and verification remain fail-closed

WorkOS is disabled unless its client ID, API credential reference, webhook
credential reference, and adapter configuration are complete. Local OIDC
continues to operate independently. Production startup does not fetch provider
state.

Canonical verification uses fake SSO exchange and fake signed-directory
deliveries. Optional credentialed smoke tests may exercise a WorkOS sandbox,
but they are outside `bin/verify`.

The change adds an AshPostgres-generated forward migration and updated resource
snapshots. It does not edit the archived initial baseline and introduces no raw
SQL exception.

## Risks / Trade-offs

- [WorkOS API or event shapes evolve] → Parse only bounded fields, isolate
  vendor envelopes in adapters, reject unknown shapes, and cover recorded
  contract fixtures without persisting them as product state.
- [Webhook replay or reordering corrupts lifecycle] → Verify signatures before
  parsing, identity events by provider event ID plus content hash, and compare
  provider update timestamps inside the locked Ash action.
- [Provisioning and SSO race for the same email] → Lock normalized-email
  principals and provider subjects, use database identities/upserts, and add
  separate-owner concurrency coverage.
- [Directory deprovisioning leaves a usable session] → Disable matching
  WorkOS links transactionally and retain current per-request external-link
  lifecycle validation.
- [External groups become accidental authority] → Grant only through active
  explicit mappings to internal roles; never consume capability-like provider
  claims directly.
- [Directory-backed authorization adds query cost] → Use bounded set queries,
  add query-count coverage, and keep direct assignments as the common fast
  path.
- [Global WorkOS credentials broaden blast radius] → Keep values outside
  product tables, use scoped references and a narrow adapter, and document
  rotation/revocation; customer-managed secrets can replace the default
  environment store later.

## Migration Plan

1. Add failing adapter, signature, SSO transaction, directory lifecycle,
   reconciliation, group mapping, authorization, replay, and concurrency tests.
2. Add the EnterpriseIdentity boundary, domain, typed resources, and
   Authorization-owned external group mapping.
3. Add fake and production WorkOS SSO, HTTP, and secret adapters.
4. Add the verified webhook receipt, provider archive, DirectorySyncEvent,
   Oban worker, and transactional Ash event actions.
5. Generalize browser authentication and add WorkOS login/callback routes
   without changing local OIDC behavior.
6. Generate and review the forward AshPostgres migration and snapshots.
7. Run focused security/concurrency/query-count tests, migration drift,
   PostgreSQL rollback/reapply, strict OpenSpec validation, and `bin/verify`.

Rollback removes the WorkOS routes and adapters and rolls back the forward
migration before any supported release. Disabling an enterprise connection
fails WorkOS login and mapped group authority closed while preserving all
historical identity provenance.

## Open Questions

None. WorkOS SSO and Directory Sync, Office Graph-owned sessions and
authorization, no AuthKit, local Authentik/fake testing, and no mandatory
hosted smoke tests are accepted decisions.
