## Why

The backend operator workflow now exposes inbox, item detail, packet readiness,
run state, and verification outcome contracts, but operators still have no
product surface to run that loop. React is the locked frontend direction and
LiveView is explicitly forbidden, so the next coherent slice is the first
minimal operator console over the existing JSON workflow API.

## What Changes

- Add a React-based operator console mounted from the Phoenix app rather than a
  LiveView product UI.
- Provide the first usable screens for inbox triage, item detail, packet
  readiness, run state, and verification outcome.
- Add a small frontend build/test path that fits the project Nix shell and
  Phoenix static serving model.
- Keep the console focused on the manual intake to verification loop; defer
  broad UI polish, provider webhooks, full graph editing, rich text
  collaboration, mobile-specific work, and workflow-builder behavior.

## Capabilities

### New Capabilities
- `operator-console`: Operator-facing React console for running the first
  manual intake to packet readiness, run state, and verification workflow from
  Phoenix-served frontend assets.

### Modified Capabilities
- None.

## Impact

- Affected code: Phoenix router/static serving, frontend source under the
  project workspace, frontend build/test configuration, and narrowly scoped
  controller or fixture changes if the existing JSON API needs UI-friendly
  status/error semantics.
- APIs: consumes the existing `/api/operator-workflow/*` JSON API; no new
  transport contract is expected unless implementation exposes a concrete gap.
- Dependencies: introduces a minimal React frontend toolchain compatible with
  the project flake's Node runtime.
- Systems: no database, agent runtime, provider integration, or ordering
  behavior changes are planned for this slice.
