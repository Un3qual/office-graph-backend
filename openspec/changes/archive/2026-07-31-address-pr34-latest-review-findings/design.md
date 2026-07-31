## Context

PR 34 intentionally centralizes database access, WorkOS identity exchange, directory lifecycle, and agent approval under typed boundaries. The latest review exposed four places where an accepted high-level contract is broader than the implementation actually enforces. The fixes must preserve the existing no-raw-SQL policy, avoid a new HTTP dependency, remain replay-safe under Ash transactions, and avoid designing a multi-capability approval model that no shipped adapter needs.

## Goals / Non-Goals

**Goals:**

- Close the remaining scanner spelling gap with AST-level classification.
- Enforce the existing one-megabyte WorkOS success-response limit while bytes arrive.
- Restore only an exact retained directory identity after legitimate reprovisioning.
- Make the one-capability durable approval model an explicit adapter-contract invariant.
- Preserve existing fixes for the two earlier outside-diff findings.

**Non-Goals:**

- Add a general HTTP client library or replace every project HTTP adapter.
- Relink directory identities by email alone or restore conflicting identities.
- Add capability arrays, multiple approval requests per step, or a new approval UI.
- Resolve old GitHub threads whose code fixes have already been replied to.

## Decisions

### Classify fragment calls at remote-call dispatch

`classify_database_operation/2` will recognize `fragment` and `unsafe_fragment` on `Ecto.Query.API` and its explicit aliases. This closes the bypass at the same receiver-resolution boundary used for repositories and SQL adapters. A source-text heuristic would be less precise and would create false positives.

### Bound successful WorkOS bodies with controlled streaming

The existing `:httpc` adapter will request asynchronous `{self, once}` streaming for successful responses. It will reject an oversized declared content length before requesting body chunks, accumulate at most the configured byte limit, cancel on overflow or timeout, and return the same bounded response map expected by the SSO client. This retains the pinned OTP transport and TLS configuration without adding a second HTTP stack. Partial-content responses are not accepted as WorkOS token successes.

### Restore the exact retained identity basis

Reconciliation will reactivate a disabled directory link only when provider tenant, provider subject, provider identity, verified email, retained principal, and linked lifecycle all match. A directory-created disabled human principal may be reactivated; a reused principal must already be active. Conflicting or ambiguous links remain review-required. This uses the locks already held by the owning Ash action, so restoration is atomic with the directory event.

### Fail closed on multi-capability approval manifests

An approval-required adapter manifest must declare exactly one capability. The durable approval request, replay checks, UI, and authority validation already represent one capability, and no shipped approval-required adapter needs more. Rejecting a broader manifest at preflight closes the privilege-representation gap without introducing speculative persistence and UI machinery. A future capability-set approval design must change the durable model explicitly before relaxing this invariant.

## Risks / Trade-offs

- **Async HTTP messages can outlive cancellation** → Every receive matches the request ID, bounded waits cancel the request, and unrelated mailbox messages remain untouched.
- **Missing or dishonest content length** → Chunk accumulation independently enforces the byte limit.
- **Identity restoration could revive the wrong principal** → Restoration requires exact retained identifiers and rejects any incompatible email-linked identity.
- **A future adapter may need multiple approved capabilities** → It will fail manifest validation until a deliberate capability-set gate is specified and implemented, which is safer than silently under-representing authority.
