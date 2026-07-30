## 1. Regression Coverage

- [x] 1.1 Add a transport test proving WorkOS HTTP requests configure TLS peer and hostname verification.
- [x] 1.2 Add focused conversation coverage proving active executions and pending gates survive terminal-history saturation.
- [x] 1.3 Add enterprise lifecycle coverage for multi-directory deprovisioning, provider-aware logout, disabled-connection session rejection, and authorized directory binding.
- [x] 1.4 Add principal reconciliation coverage for canonical email storage and indexed lookup behavior.

## 2. Root-Cause Fixes

- [x] 2.1 Configure the OTP WorkOS adapter with the runtime trust store and HTTPS hostname verification.
- [x] 2.2 Split generated agent history reads by lifecycle priority and merge them inside the existing hard bound.
- [x] 2.3 Preserve SSO while another directory basis remains, persist issuing connection provenance on WorkOS sessions, validate it on every session load, and select logout behavior from the session method.
- [x] 2.4 Add the authorized operation-correlated directory-binding boundary and concurrency-safe Ash identity action.
- [x] 2.5 Canonicalize principal email at the Ash write boundary and use the existing identity index in reconciliation queries.

## 3. Generated Artifacts and Contracts

- [x] 3.1 Generate and inspect AshPostgres migration snapshots without raw SQL.
- [x] 3.2 Regenerate the GraphQL schema, Relay artifacts, and frontend types.
- [x] 3.3 Update architecture exception locators or inventories only where the owning function signatures changed.

## 4. Verification and Closeout

- [x] 4.1 Run focused backend and frontend regression checks, formatting, and strict OpenSpec validation.
- [x] 4.2 Run the canonical repository verification gate and migration baseline from an empty database.
- [x] 4.3 Sync the accepted delta requirements into canonical specs and archive the completed change.
