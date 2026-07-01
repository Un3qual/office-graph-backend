## 1. Regression Baseline

- [x] 1.1 Add an Ecto telemetry query-count helper for focused projection/API tests.
- [x] 1.2 Add an operator workflow projection scaling test with multiple applied inbox rows and linked graph resources.
- [ ] 1.3 Capture current query-count behavior in a failing or threshold-marked test that identifies bootstrap/auth, selected-item duplication, and projection fan-out separately.

## 2. Frontend Transport And Request Fanout

- [ ] 2.1 Add a small GraphQL HTTP fetcher for the operator workflow projection client.
- [ ] 2.2 Switch `createDefaultOperatorWorkflowProjectionClient()` to the GraphQL adapter while preserving explicit JSON adapter construction.
- [ ] 2.3 Add frontend tests proving the default console path uses GraphQL and both adapters return the same view model shape.
- [ ] 2.4 Reuse the selected inbox row as initial item detail instead of immediately refetching the same normalized event.
- [ ] 2.5 Avoid a separate verification-outcome read when loaded run state already contains the verification data required by the panel.

## 3. Session Context And Authorization

- [ ] 3.1 Route hand-written operator workflow JSON reads through a server-controlled local owner/session context path rather than request-time bootstrap in each `ApiSupport.read_operator_*` call.
- [ ] 3.2 Update GraphQL operator workflow resolvers to pass the trusted request actor/session context into `ApiSupport`.
- [ ] 3.3 Preserve rejection of client-supplied `session_context` maps for JSON routes.
- [ ] 3.4 Teach authorization reads to use trusted session capability facts for the current scope without re-querying capability and role tables on each projection read.
- [ ] 3.5 Add tests for forbidden bootstrap-disabled behavior and trusted session-context reuse.

## 4. Batched Projection Assembly

- [x] 4.1 Refactor `OfficeGraph.Projections.operator_inbox/1` and `operator_workflow_item/2` to use one shared batched row builder.
- [x] 4.2 Batch proposed-change reads by normalized intake event ids.
- [x] 4.3 Batch audit and revision trace reads by applied operation ids.
- [x] 4.4 Batch graph resource link reads by resource type and id.
- [x] 4.5 Batch graph relationship, work-packet required-check, work-packet source, and linked-run reads across all rows.
- [x] 4.6 Preserve existing status, reason-code, blocker, audit-trace, revision-trace, graph-link, and source-watermark semantics.

## 5. Verification

- [ ] 5.1 Run focused operator workflow API parity tests for JSON and GraphQL.
- [ ] 5.2 Run focused frontend projection-client and operator console tests.
- [ ] 5.3 Run the query-count scaling test and document the accepted budget.
- [ ] 5.4 Run `mix format --check-formatted`, `mix compile --warnings-as-errors`, frontend verification, and OpenSpec strict validation from the Nix shell.
