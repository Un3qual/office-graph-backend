## 1. Frontend Foundation

- [x] 1.1 Extract implementation tokens and component inventory from `assets/operator-console-concept.png`.
- [x] 1.2 Add a minimal React frontend source tree and package scripts that run inside the project Nix shell.
- [x] 1.3 Add typed API-client helpers for the existing operator workflow JSON endpoints.
- [x] 1.4 Add shared UI primitives, status vocabulary helpers, and sample test fixtures for operator workflow projections.
- [x] 1.5 Add frontend tests for API-client loading, success, empty, and error states.

## 2. Phoenix App Shell

- [x] 2.1 Add a Phoenix route/controller path that serves the React app shell without using LiveView.
- [x] 2.2 Configure compiled frontend asset serving through the existing Phoenix static asset model.
- [x] 2.3 Add backend tests that verify the console route returns the app shell and asset references.

## 3. Operator Console Workflow UI

- [ ] 3.1 Implement the console shell with inbox/list and selected-detail regions.
- [ ] 3.2 Render inbox rows with source summary, actionability, status, blockers, allowed next actions, watermark, loading, empty, and error states.
- [ ] 3.3 Render selected item detail with typed identity, source context, proposed-change status, affected graph links, traces, and safe next actions.
- [ ] 3.4 Render packet readiness with objective, source references, context summary, success criteria, autonomy posture, required checks, blockers, and disabled/enabled handoff affordances.
- [ ] 3.5 Render run state and verification outcome with lifecycle, required checks, evidence state, accepted evidence, policy or actor basis, and failure reason codes.
- [ ] 3.6 Add responsive behavior for desktop and narrow viewports without introducing mobile-specific product scope.

## 4. Verification And Handoff

- [ ] 4.1 Add focused component tests for inbox selection, item detail, packet readiness, run state, and verification outcome.
- [ ] 4.2 Add frontend build or type-check verification and document the command in the change summary.
- [ ] 4.3 Capture rendered desktop and narrow screenshots and compare them against `assets/operator-console-concept.png`.
- [ ] 4.4 Run OpenSpec validation for the change and the project specs.
- [ ] 4.5 Run project formatting and focused backend/frontend tests needed for the changed surfaces.
- [ ] 4.6 Update the implementation summary with verification evidence and any deferred follow-up work.
