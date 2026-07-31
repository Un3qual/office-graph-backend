## Context

PR 34 currently uses OTP `:httpc` controlled streaming to bound successful WorkOS responses, but the pinned OTP 29 implementation streams only status 200 and 206; other statuses are buffered by the inets handler before the adapter sees them. The local fixture seed already reconciles identity lifecycle and role-capability drift, but it only ensures the expected role assignment. The database scanner likewise covers ordinary Repo reads and writes without classifying explicit connection checkout. Finally, the WorkOS active-connection lookup collapses Ash read failures into the same reason as a missing or disabled connection.

## Goals / Non-Goals

**Goals:**

- Enforce one byte limit while every WorkOS response body is received.
- Keep WorkOS transport behavior small, TLS-authenticated, non-retrying, and non-redirecting for credential-bearing code exchange.
- Repair the exact role-assignment set owned by each explicit local fixture manifest replay.
- Preserve storage outages as retryable authentication failures.
- Close the Repo checkout spelling in the direct-Ecto scanner with AST regression coverage.

**Non-Goals:**

- Generalize all repository HTTP adapters in this focused review fix.
- Add hosted WorkOS tests or AuthKit.
- Reconcile non-fixture principals or change production role-assignment policy.
- Expand the database scanner based only on database-like function names from unrelated receivers.

## Decisions

### Use Req function streaming for the WorkOS adapter

Replace the WorkOS adapter's `:httpc` receive loop with a pinned Req dependency and a function-valued `into` collector. Req's function collector receives chunks for every response status and supports `{:halt, ...}` cancellation, unlike `:httpc` streaming. The collector checks declared content length when available, accumulates bounded iodata plus a byte count, and halts as soon as the limit would be exceeded. Response decoding and compression remain disabled so the adapter returns exact bytes.

The request disables automatic retries and redirects. Authorization-code exchange is not assumed replay-safe, and credential-bearing requests must not silently follow another endpoint. Req/Mint's normal HTTPS validation replaces the hand-written inets TLS options.

Alternatives considered:

- Keeping `:httpc` cannot bound non-200/206 bodies because buffering happens inside the inets handler.
- A custom `:ssl` HTTP parser would duplicate redirect, framing, chunking, timeout, and TLS behavior and create a larger security surface.
- Bounding only after `:httpc` returns preserves the current vulnerability.

### Reconcile fixture-owned assignments with an Ash action

Add a transaction-enabled Ash action on role assignments that atomically destroys every assignment for the fixture principal except the already-ensured manifest assignment, then verifies the exact postcondition. Invoke it for owner, workspace-administrator, member, and deprovisioned-member fixtures only from explicit seed setup. This keeps login read-only and avoids `Repo.transaction` or read-modify-write deletion loops.

Fixture setup runs before the resulting human actor exists, so the private action dispatch, nested destroy, and verification read use narrowly documented Ash authorization bypasses. Record those exact functions in the architecture exception ledger with a retirement condition requiring a purpose-built trusted setup actor; do not broaden runtime role-assignment policy.

### Preserve storage and absence as distinct outcomes

Map only `{:ok, nil}` to `enterprise_connection_unavailable`; map an Ash read error to `enterprise_identity_storage_unavailable`. The existing authentication boundary already treats the latter as transient and maps it to the browser's service-unavailable path.

### Extend receiver-aware scanner classification

Add `checkout` to the known `OfficeGraph.Repo` operation set and cover direct and explicitly aliased calls. Classification remains receiver-aware so unrelated `checkout` functions do not create false positives.

## Risks / Trade-offs

- [New HTTP dependency increases the runtime dependency graph] -> Pin the narrow supported Req line, disable unused automatic behavior, audit dependencies in the canonical gate, and keep the WorkOS adapter contract unchanged.
- [A streaming collector can accidentally perform quadratic concatenation] -> Accumulate reversed chunks with a separate byte count and materialize the binary once after completion.
- [Fixture replay removes intentionally added development authority] -> Limit reconciliation to server-owned local fixture principals and the explicit `mix demo.seed` action; ordinary login remains fail-closed and non-mutating.
- [Concurrent fixture setup can observe transient drift] -> Run reconciliation as a transaction-enabled Ash action after the expected assignment exists and validate the exact resulting set before returning.
