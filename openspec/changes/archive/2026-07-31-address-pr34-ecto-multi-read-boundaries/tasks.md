## 1. Database boundary enforcement

- [x] 1.1 Add focused failing regressions for fully qualified and explicitly aliased `Ecto.Multi` read operations while preserving unrelated-receiver behavior.
- [x] 1.2 Classify `Ecto.Multi.all`, `Ecto.Multi.one`, and `Ecto.Multi.exists?` through the existing receiver-aware direct Ecto operation inventory.

## 2. Verification and specification closeout

- [x] 2.1 Run focused regressions, formatting, `git diff --check`, and the canonical `./bin/verify` gate.
- [x] 2.2 Verify implementation against the change, sync the delta specification, and archive the completed change.
