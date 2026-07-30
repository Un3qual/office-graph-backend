## 1. Lock The Development Authentication Contract

- [ ] 1.1 Add failing Phoenix tests for development-build, explicit-enable, loopback, CSRF, fixed-selector, safe-return-target, and production-unavailable route behavior
- [ ] 1.2 Add failing authentication and session tests for eligible fixture issuance, locked identity revalidation, bounded rejection evidence, session reuse, logout, and identity switching
- [ ] 1.3 Add failing setup tests for idempotent owner, workspace-administrator, member, and deprovisioned fixtures with no request-time repair or duplicate identity and authorization facts
- [x] 1.4 Add failing authorization behavior tests that distinguish the seeded owner, workspace-administrator, member, and deprovisioned profiles through real capability checks
- [ ] 1.5 Add failing browser and frontend tests for correctly typed authentication errors, provider choices, sign-out/switch navigation, and preservation of the requested product route

## 2. Seed Deterministic Identity And Role Fixtures

- [x] 2.1 Add one typed development fixture manifest with stable selector keys, expected emails, local-development subjects, lifecycle, scope, role keys, and centralized capability profiles
- [x] 2.2 Add idempotent Foundation, Identity, and Authorization Ash actions that reconcile the manifest without direct Ecto, explicit `Repo.transaction`, raw SQL, or browser-controlled identity facts
- [x] 2.3 Create active `local_development` external identity links for eligible fixtures and retain a disabled identity basis plus historical role assignment for the deprovisioned fixture
- [x] 2.4 Extend `mix demo.seed` to invoke fixture reconciliation before optional workflow examples and report an actionable bounded summary

## 3. Add The Gated Local Development Provider

- [ ] 3.1 Add development-only runtime configuration for `LOCAL_DEV_AUTH_ENABLED` and enforce the compile-time development-route plus loopback gates
- [ ] 3.2 Add Authentication-boundary fixture resolution that accepts only stable server-owned keys, resolves the exact seeded link and scope, and delegates issuance to the existing locked human-session action with method `local_development`
- [ ] 3.3 Add the Phoenix-rendered `/auth/login` development chooser, a CSRF-protected fixture-selection POST, safe return-target handling, and an explicit Authentik option when generic OIDC is configured
- [ ] 3.4 Return bounded correctly typed browser pages for missing fixtures, disabled identities, invalid selections, unavailable providers, and transient storage failures

## 4. Make Identity Switching Easy And Safe

- [ ] 4.1 Add a standard product-shell sign-out control and route-focused frontend tests without exposing fixture identities in production UI
- [ ] 4.2 Make local-development logout revoke the current durable session and return to the chooser, while preserving existing passive Authentik and WorkOS logout behavior
- [ ] 4.3 Prove revocation failure preserves the current cookie and prevents selection of another fixture, and prove a revoked prior session cannot be reused after switching

## 5. Document And Verify The Change

- [ ] 5.1 Update local setup documentation with the Postgres, migration/setup, `mix demo.seed`, opt-in local-auth, role-switching, optional Authentik, and WorkOS enterprise test paths
- [ ] 5.2 Run focused authentication, Identity, Authorization, seed, controller, route, and frontend tests plus Relay generation, typecheck, lint, formatting, and compilation with warnings as errors
- [ ] 5.3 Run strict OpenSpec validation, architecture and raw-SQL policy gates, the canonical `bin/verify` suite, and a final diff review for production route leakage, request-time bootstrap, arbitrary impersonation, read-modify-write races, and unrelated changes
