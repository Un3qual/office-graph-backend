## Context

The base branch replaces direct database access with Ash, moves APIs toward generated Relay surfaces, adds WorkOS enterprise identity, and codifies repository boundaries. The review found that several regressions live at those new boundaries and that some enforcement mechanisms duplicate the product schema or exist only to drive tests. The remediation must preserve fail-closed identity behavior, the raw-SQL approval rule, concurrency coverage, and the generated API contracts while deleting implementation-coupled machinery.

## Goals / Non-Goals

**Goals:**

- Fix the verified WorkOS restoration, Relay submission, ordering, and error-classification regressions with behavior tests that fail on the base branch.
- Keep local-development session validation exact while performing constant bounded work from the identity already loaded during session resolution.
- Make uniqueness retry detection one nil-safe responsibility instead of copied private-error parsing.
- Make test cleanup depend on canonical Ash resources rather than a shadow resource graph.
- Keep only failure checkpoints that prove an externally observable rollback or retry contract, and make their test state process-scoped rather than VM-global.
- Leave one semantic database-boundary scanner, one ExDNA configuration path, and focused conformance helpers.

**Non-Goals:**

- Change public routes, GraphQL field names, WorkOS provider contracts, or the PostgreSQL 18 UUIDv7 strategy.
- Remove dynamic module references that are required to break genuine reciprocal Ash resource compile cycles.
- Introduce raw SQL, direct Repo calls, another dependency, or a second planning format.

## Decisions

### Restore only an exact immutable WorkOS identity

An active directory event may reactivate a disabled `workos_directory` link only when provider tenant, directory subject, provider identity, normalized verified email, and principal ownership match the retained records. The same transaction reactivates a directory-created principal when it has no incompatible identity state. A later SSO login may reactivate only the retained exact SSO subject after the active directory basis is proven. Email-only or cross-subject relinking remains review-required.

This is preferred over creating replacement links because it preserves provenance and ordinary identities, and over unconditional reactivation because that would weaken deprovisioning and conflict handling.

### Normalize errors at their owning boundary

`OfficeGraph.CommandSupport` will own the nil-safe unique-constraint predicate used by bounded race retries. Conversation action support will unwrap its exact rollback marker and rescue only concrete database connection/constraint exceptions. Ash validation, authorization, framework, runtime, and unrelated exit failures retain their original classification.

This is preferred over adding more catch-all mappings because callers can retry only genuine transient failures and defects stay diagnosable.

### Translate and order Relay data before entering mutable UI state

Command variables are computed before the controller marks a request pending. Operator history records are converted to internal IDs before sorting by timestamp and internal ID ascending. Test fixtures represent raw and Relay IDs separately and generated Node responses use only Relay IDs.

This keeps a conversion failure synchronous and recoverable and preserves the prior deterministic ordering contract without decoding and re-encoding IDs in assertions.

### Reuse the identity basis loaded for session resolution

Human session resolution will retain a bounded authentication-basis value containing only the exact principal and external-link facts needed for revalidation. Local-development authentication matches that value against the fixed in-memory fixture manifest; it does not reload profiles or probe every fixture. Enterprise validation continues to perform its provider-specific current-state checks.

### Use canonical resources for committed-test cleanup

Test support will read canonical resources and use a single test-only hard-delete helper backed by the Ash data layer after records are selected through Ash queries. The helper exists only in `test/support`; it bypasses product destroy policy solely to remove data committed by separate database owners. Oban cleanup may retain one narrow test-only resource because `oban_jobs` has no Office Graph Ash resource. Foreign-key ordering remains explicit in the cleanup function, but table schemas, attributes, and a duplicate Ash domain are removed.

This is preferred over adding destroy actions to every production resource or introducing an unapproved SQL/Repo cleanup path.

### Keep failure injection test-owned and process-scoped

The existing checkpoints cover otherwise unreachable storage failures in rollback, retry, and bounded-response contracts. They remain only where a test asserts a consumer-visible outcome. Test adapters use one process-local response store and are selected once by test configuration; individual tests no longer mutate application configuration or force unrelated suites to serialize. Checkpoints that support only implementation assertions are deleted.

### Make quality gates terminal and semantic

The database scanner classifies only executable SQL-bearing AST positions. The completed removal-debt inventory, inventory builder, remediation-progress API, and stale-debt diagnostics are deleted; current occurrences must either match the exact approved exception inventory or fail. ExDNA runs once through Credo with one current path list. Relay and migration conformance tests use schema/AST behavior rather than source-text counts, and migration parsing moves to a focused support module.

The archived local-authentication execution plan is deleted because its durable decisions already exist in canonical OpenSpec artifacts.

## Risks / Trade-offs

- **[Restoration could revive the wrong actor]** → Require exact retained subject, tenant, IdP identity, email, and principal matches under the existing reconciliation transaction and locks.
- **[Canonical hard deletion bypasses product destroy policy]** → Keep the helper test-only, require callers to select typed canonical records first, and retain explicit foreign-key ordering.
- **[Process-local failure state may not reach spawned workers]** → Keep worker failure tests synchronous or explicitly propagate ownership only for the tests that exercise a separate process; do not fall back to VM-global configuration.
- **[Removing debt history loses obsolete diagnostics]** → Preserve the exact approved exceptions and strict current scan; git and archived OpenSpec retain historical remediation evidence.
- **[A smaller conformance suite could miss architecture drift]** → Assert observable schema, scanner, and command behavior and retain canonical end-to-end verification rather than source formatting.

## Migration Plan

No database or public API migration is required. Apply code and test changes, synchronize the four delta specifications, run the complete repository verification from PostgreSQL 18, archive this OpenSpec change, and publish the result as a PR based on `codex/quality-boundaries`. Reverting the stacked PR restores the previous behavior without data transformation.

## Open Questions

None.
