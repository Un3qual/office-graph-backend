## Why

The repository-wide audit found that the default verification path is slower and less complete than its name implies, a locked database driver has a current advisory, and an obsolete resolved-review handoff remains at the repository root. These issues make routine changes harder to trust and maintain even though the existing static-analysis baseline is strong.

## What Changes

- Update Postgrex to the patched locked version and add dependency-advisory checking to the normal verification path.
- Stop the Relay schema snapshot check from recompiling the backend when it is invoked after the parent Mix verification compile.
- Make the default verification and precommit aliases run strict OpenSpec validation so the declared source of truth cannot drift silently.
- Remove the resolved, dated code-review handoff from the repository root; Git history already preserves it.
- Keep behavior-preserving source refactors limited to responsibility boundaries that materially reduce file size or coupling without introducing generic helper layers.

## Capabilities

### New Capabilities

None. This change improves the development and verification workflow without adding product behavior.

### Modified Capabilities

- `architecture-stabilization`: Make strict OpenSpec validation and dependency-advisory checks explicit parts of full-project verification.

## Impact

The change affects `mix.lock`, Mix aliases, the Relay schema verification script, repository hygiene, and internal source organization where justified. Product APIs, persistence schemas, runtime behavior, and frontend visual behavior are unchanged.
