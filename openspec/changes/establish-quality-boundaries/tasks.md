## 1. Reconcile Repository Planning

- [x] 1.1 Classify every `docs/superpowers/**` file as already canonical, obsolete, or containing a unique current normative decision and record the evidence inside this OpenSpec change
- [x] 1.2 Promote only unique current normative decisions into their owning OpenSpec capabilities and update `openspec/project.md` with the approved OpenSpec-only, Ash-first, and raw-SQL approval boundaries
- [x] 1.3 Remove `docs/superpowers/**` and update repository guidance so required agent workflows write project designs and tasks only through OpenSpec

## 2. Enforce Database Access Boundaries

- [x] 2.1 Add focused scanner tests covering direct SQL calls, fragments, unsafe fragments, migration SQL constructs, tracked SQL files, direct Ecto operations, explicit transactions, exclusions, and stable fingerprints
- [x] 2.2 Implement a syntax-aware tracked-source scanner that reports raw-SQL and direct-Ecto occurrences without executing or rewriting project files
- [x] 2.3 Create separate machine-readable current-debt and approved-exception inventories, with no existing debt entry represented as user-approved
- [x] 2.4 Replace broad approval language in the existing architecture exception ledger and supporting conformance coverage with the new debt-versus-approval model

## 3. Integrate Canonical Verification

- [x] 3.1 Add a non-mutating planning-boundary check that rejects `docs/superpowers/**` and other prohibited parallel planning roots
- [x] 3.2 Add the database-boundary comparison command to canonical verification and make its diagnostics identify new, changed, and stale occurrences
- [x] 3.3 Add regression coverage proving the canonical gate rejects new parallel plans and unclassified SQL while accepting the reviewed unchanged debt baseline

## 4. Verify And Close The Boundary Change

- [x] 4.1 Run formatter, focused architecture and project-quality tests, compilation with warnings as errors, and strict OpenSpec validation
- [ ] 4.2 Run the complete canonical `bin/verify` gate and confirm it leaves the worktree unchanged
- [ ] 4.3 Review the final diff for copied historical plans, accidental implied SQL approvals, vague exceptions, placeholders, and unrelated behavior changes
