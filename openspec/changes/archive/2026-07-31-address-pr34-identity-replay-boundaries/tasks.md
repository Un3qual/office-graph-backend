## 1. Enterprise identity correctness

- [x] 1.1 Add a regression for deprovisioning the last shared directory basis and derive principal creation provenance from retained directory users.
- [x] 1.2 Add exact and changed-input directory-binding replay coverage and reject incompatible operation replays without mutating the binding.

## 2. Database boundary enforcement

- [x] 2.1 Classify direct and aliased `OfficeGraph.Repo.rollback` calls while preserving unrelated-receiver behavior.

## 3. Verification and specification closeout

- [x] 3.1 Run focused regressions, formatting, `git diff --check`, and the canonical `./bin/verify` gate.
- [x] 3.2 Validate implementation against the change, sync the delta specs, and archive the completed change.
