## 1. OpenSpec And Gate Setup

Reference: use `openspec/changes/repair-ash-model-conformance/model-inventory.md`
as the normative 40-table inventory for the architecture conformance gate.

- [x] 1.1 Add this corrective OpenSpec change and model inventory.
- [x] 1.2 Replace the WorkGraph-only architecture conformance test with a
  repo-wide model ownership gate.
- [x] 1.3 Commit the failing conformance gate before converting models.

## 2. WorkGraph Convergence

- [x] 2.1 Convert canonical WorkGraph modules to Ash resources.
- [x] 2.2 Register graph identity, graph relationships, and typed resources in
  `OfficeGraph.WorkGraph.Domain`.
- [x] 2.3 Replace WorkGraph reads, reference validation, and tests with
  canonical Ash resource modules.
- [x] 2.4 Delete `OfficeGraph.WorkGraph.Resources.*` modules.

## 3. Foundation Domains

- [x] 3.1 Convert Tenancy resources and bootstrap writes to Ash.
- [x] 3.2 Convert Identity resources and bootstrap writes to Ash.
- [x] 3.3 Convert Authorization resources and bootstrap writes to Ash.

## 4. Traceability, Content, Intake, And Runtime Domains

- [x] 4.1 Convert Operations, Audit, Revisions, and Tombstones resources.
- [x] 4.2 Convert Content resources and `create_plain_document/3`.
- [x] 4.3 Convert Integrations and ExternalRefs resources and manual intake
  storage.
- [x] 4.4 Convert ProposedChanges resources and state transitions.
- [x] 4.5 Convert WorkPackets and Runs resources.

## 5. Final Conformance

- [x] 5.1 Remove all `use Ecto.Schema` occurrences under `lib/office_graph`.
- [x] 5.2 Shrink the architecture exception ledger to remaining direct Ecto
  transaction/read paths only in
  `openspec/changes/first-backend-walking-skeleton/architecture-exceptions.md`
  rather than creating a second ledger.
- [x] 5.3 Run full backend and OpenSpec verification.
- [x] 5.4 Commit final docs and evidence.
