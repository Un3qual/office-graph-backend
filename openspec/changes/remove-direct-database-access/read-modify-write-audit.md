# Production Read-Modify-Write Audit

Every production mutating function changed by this OpenSpec change must be
entered here before its persistence implementation changes. The audit records
the persisted reads that influence the write, the Ash concurrency safeguard
that owns the invariant, and the behavior or concurrency test that proves it.
Rows remain in this table after implementation so the final review can verify
that no touched invariant silently fell back to application-level
read-modify-write behavior.

| Owner and function | Persisted reads and invariant | Ash safeguard | Verification |
| --- | --- | --- | --- |
| `OfficeGraph.Tenancy.ensure_local_scope/1` | Reads or creates the organization by slug, then its workspace and initiative by parent-scoped slug, plus the default workstream. Exactly one row for each identity must survive concurrent first bootstrap attempts, and all returned records must belong to the same hierarchy. | One transactional generic action declares every touched tenancy resource. Each create uses an Ash upsert action backed by the existing identity and changes no fields on conflict. PostgreSQL 18 `MERGE` can surface a unique violation when two statements concurrently observe the same missing identity, so the boundary retries the complete action once only for the four declared tenancy identity constraints; the failed action has already rolled back before retry. | `OfficeGraph.Foundation.BootstrapTest` proves stable IDs on repeat bootstrap. `OfficeGraph.Integrations.IntakeBootstrapConcurrencyTest` proves two independent first-scope attempts return the same IDs and one row per identity. |
| `OfficeGraph.Content.persist_plain_document/3` | Performs no decision-making persisted read. The invariant is failure atomicity across the document, initial paragraph block, and first revision. | A transactional generic action on `Document` declares the block and revision resources it touches. Any nested Ash create error is returned to the action so Ash rolls back the full action-owned transaction. | `OfficeGraph.WorkGraph.PersistenceTest` proves the document, block, and revision are created as one domain operation and that invalid or unauthorized operation contexts persist none of them. |
