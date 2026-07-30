## 1. Lock The Enterprise Identity Contract

- [x] 1.1 Add WorkOS SSO adapter contract tests for organization-bound redirects, one-time callback state, normalized profile exchange, unavailable configuration, and no persisted provider tokens or raw attributes
- [x] 1.2 Add WorkOS webhook signature and receipt tests for exact raw-body HMAC verification, clock skew, unknown directories, supported event shapes, duplicate hashes, conflicting replays, and bounded errors
- [ ] 1.3 Add directory lifecycle contract tests for user, group, and membership create/update/remove/restore plus stale-event ordering and Oban retry
- [ ] 1.4 Add identity and authorization tests for directory-first and SSO-first reconciliation, conflicts, required provisioning, deprovisioning, group-to-role mapping, removal, scope isolation, and query-count bounds
- [ ] 1.5 Add separate-owner concurrency tests for competing directory/SSO identities and duplicate membership events

## 2. Add Provider-Neutral Enterprise Identity Resources

- [x] 2.1 Add the `OfficeGraph.EnterpriseIdentity` Boundary and Ash domain with organized resource, action, adapter, service, value, and worker folders
- [x] 2.2 Add `EnterpriseConnection` and `Directory` resources with typed scope, provider identities, lifecycle, directory requirement, operations, identities, and complete in-boundary relationships
- [x] 2.3 Add `DirectoryUser` with typed provider identity, normalized email, bounded profile fields, principal/link relationships, lifecycle, provider timestamp, review state, and database-generated UUIDv7 metadata
- [x] 2.4 Add `DirectoryGroup` and in-table-soft-deleted `DirectoryMembership` resources with ordinary Ash identities and active identity slots
- [x] 2.5 Add replay-safe `DirectorySyncEvent` with provider event identity, content hash, raw archive, operation, state, result, and processing timestamps
- [ ] 2.6 Add EnterpriseIdentity-owned `ExternalGroupRoleMapping`, connect it to existing roles and exact scope, and expose it to Authorization through a dependency-inverted fact provider without creating a boundary cycle

## 3. Implement WorkOS Adapters And Receipt

- [x] 3.1 Add `EnterpriseSsoClient`, WorkOS HTTP client, and SecretStore behaviours with production `:httpc` and environment adapters plus deterministic test adapters
- [x] 3.2 Implement WorkOS SSO authorization URL and code exchange with HTTPS enforcement, bounded timeouts and bodies, typed profile parsing, and stable connection-scoped subjects
- [x] 3.3 Extend the raw body reader and router with an API-only WorkOS webhook endpoint and map signature, payload, directory, replay, and storage failures to bounded responses
- [x] 3.4 Implement WorkOS timestamped webhook signature verification and bounded user/group/membership event normalization before persistence
- [x] 3.5 Implement signed receipt through the registered webhook principal, operation, provider source, raw archive, sync event identity, and one newly accepted Oban job

## 4. Apply Directory Lifecycle Through Ash

- [x] 4.1 Add transactional Ash actions that lock and upsert directory users, groups, and memberships while rejecting stale provider timestamps
- [x] 4.2 Add directory provisioning reconciliation that creates or reuses one eligible principal and `workos_directory` external link or preserves deterministic review state
- [x] 4.3 Add deprovisioning that disables directory and matching WorkOS SSO links in-table, preserves provenance, and disables the principal only when no accepted active identity basis remains
- [x] 4.4 Add an idempotent Oban worker that loads the accepted archived event and records applied, stale, review, or failed outcomes without duplicate mutations
- [ ] 4.5 Add explicit enterprise connection and group-role mapping Ash actions with current authorization, operation correlation, and no direct Ecto or explicit `Repo.transaction`

## 5. Wire SSO And Mapped Authorization

- [x] 5.1 Generalize the browser login transaction to capture provider and enterprise connection without weakening local OIDC nonce, PKCE, expiry, and one-time consumption
- [x] 5.2 Add WorkOS login and callback orchestration that loads the captured connection, exchanges through the adapter, reconciles `workos_sso`, enforces required directory provisioning, and issues the existing Office Graph session
- [x] 5.3 Add WorkOS web routes/controller behavior while preserving safe return paths, passive local logout, local OIDC routes, and bounded authentication evidence
- [ ] 5.4 Extend login-scope and capability evaluation with active directory membership plus explicit active group-role mappings using bounded set-based Ash reads
- [ ] 5.5 Prove disabled connections, directories, users, groups, memberships, mappings, links, and principals all fail closed on session or authorization reuse

## 6. Generate And Verify The Forward Change

- [ ] 6.1 Add runtime configuration and operator documentation for WorkOS client ID, API/webhook secret references, base URLs, connection binding, Directory Sync webhook URL, local fake adapters, rotation, and optional sandbox smoke tests
- [ ] 6.2 Update recognized capability/setup manifests and architecture ledgers for enterprise identity management and WorkOS webhook receipt
- [ ] 6.3 Generate and review one forward AshPostgres migration plus current resource snapshots without editing the archived initial baseline or adding raw SQL beyond the exact approved PostgreSQL 18 UUIDv7 default fragment
- [ ] 6.4 Run formatter, compilation with warnings as errors, migration drift, focused WorkOS/directory/auth tests, architecture and smell gates, Dialyzer, dependency audit, frontend verification, and strict OpenSpec validation
- [ ] 6.5 Run canonical `bin/verify`, confirm the worktree remains free of generated drift, review the final diff for secrets, raw payload promotion, tenant selection, read-modify-write races, N+1 queries, raw SQL, and unrelated behavior changes
