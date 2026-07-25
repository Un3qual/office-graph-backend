## 1. OIDC And Persistence Foundation

- [ ] 1.1 Add the `oidcc` dependency, explicit runtime configuration, optional
  provider-configuration child, and deterministic OIDC adapter test support.
- [ ] 1.2 Add failing migration/resource tests for external identity links,
  authentication events, and extended human session metadata.
- [ ] 1.3 Add migrations and Ash resources for external identity links,
  authentication events, and human session metadata with lifecycle constraints
  and indexes.

## 2. Identity Reconciliation And Session Lifecycle

- [ ] 2.1 Add failing behavior tests for exact subject reuse, explicit
  verified-email linking, durable review outcomes, conflicts, and disabled
  identities.
- [ ] 2.2 Implement provider-neutral external identity reconciliation without
  mapping external claims into product authority.
- [ ] 2.3 Add failing behavior tests for human session issue, replacement,
  expiry, revocation, logout, principal/link revalidation, and bounded
  authentication evidence.
- [ ] 2.4 Implement human session issue/load/revoke and authentication event
  recording through the Identity boundary.

## 3. Authentication Orchestration

- [ ] 3.1 Add failing tests for OIDC state/nonce/PKCE transactions, provider
  failure normalization, internal login-scope selection, and preferred-scope
  disambiguation.
- [ ] 3.2 Implement the OIDC client boundary and
  `OfficeGraph.Authentication` login/logout orchestration.
- [ ] 3.3 Add current role-assignment-based login-scope resolution to the
  Authorization boundary.

## 4. Phoenix Session Boundary

- [ ] 4.1 Add failing controller and plug tests for login redirect, callback
  validation, opaque cookie session, logout, product-page redirect, and absent
  API actors.
- [ ] 4.2 Implement authentication routes/controller, durable session loading,
  product-page session requirement, and secure cookie options.
- [ ] 4.3 Remove `LocalApiOwnerPlug` and every request-time
  `bootstrap_local_api_owner/0` fallback.
- [ ] 4.4 Convert existing ConnCase-backed web tests to explicit durable
  session fixtures and retain opt-out unauthenticated coverage.

## 5. Verification And Closeout

- [ ] 5.1 Run formatting, migrations, focused Identity/Authentication/web
  tests, Boundary checks, dependency audit, and strict OpenSpec validation.
- [ ] 5.2 Run the complete Nix-backed `./bin/verify` repository gate and
  `git diff --check`, fixing all regressions.
- [ ] 5.3 Verify implementation against every change requirement, mark tasks
  complete, archive the OpenSpec change with synced durable specs, and commit
  the final verified state.
