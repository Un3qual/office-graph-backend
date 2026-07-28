## 1. Lock The Terminal API Boundary

- [x] 1.1 Add a classified inventory of every manual GraphQL root field, manual GraphQL object that mirrors an Ash resource, Phoenix JSON route, resolver, controller, serializer, input parser, and error mapper
- [ ] 1.2 Add failing architecture tests that reject `OfficeGraphWeb.OperatorCommands`, transport `operator_commands` folders, unclassified manual root fields/routes, and duplicate manual objects for generated Ash resources
- [ ] 1.3 Add failing schema tests that require Relay Node identity and authorized refetch for every stable generated resource object and accepted stable projection object
- [ ] 1.4 Add failing tests that require Relay connections for growing generated lists and reject wrapper dataloader resolvers
- [ ] 1.5 Add dual-transport contract tests for typed action arguments, safe errors, operation correlation, affected identities, authorization, idempotency, and conflict outcomes

## 2. Complete Generated Resource Reads

- [ ] 2.1 Replace manual Signal resource object/loading paths with the generated WorkGraph AshGraphql type, Relay node loading, relationships, and AshJsonApi routes
- [ ] 2.2 Replace resource-shaped graph relationship and graph item fields/routes with generated relationships or typed projection actions while retaining only the redacted relationship-view exception
- [ ] 2.3 Replace packet-workspace resource objects and loaders with generated WorkPacket, WorkPacketVersion, source-reference, and required-check types and relationships
- [ ] 2.4 Replace run-index and run-detail resource objects and loaders with generated WorkRun, RunRequiredCheck, ExecutionObservation, and related packet types
- [ ] 2.5 Replace conversation, message, agent execution, approval, and context-expansion resource objects and loaders with generated Ash types and relationships
- [ ] 2.6 Keep operator workflow, integration health, command affordance, and other true mixed projections typed and capability-owned; make every stable projection object a tested Relay node

## 3. Expose Commands Through Owning Ash Actions

- [ ] 3.1 Add typed Ash errors and GraphQL/JSON API protocol implementations for the safe command outcomes currently handled by the shared web error switch
- [ ] 3.2 Add responsibility-owned Ash typed input/result types only where action arguments, multiple records, or operation facts cannot use existing resource types and action metadata
- [ ] 3.3 Expose manual-intake submission and proposed-change application through owning Integrations and ProposedChanges generic actions
- [ ] 3.4 Expose packet creation and version creation through owning WorkPackets generic actions
- [ ] 3.5 Expose run start and execution-observation recording through owning Runs generic actions
- [ ] 3.6 Expose evidence-candidate creation, evidence acceptance, and verification waiver through owning WorkGraph and Verification generic actions
- [ ] 3.7 Expose agent invocation, cancellation, approval, context expansion, conversation start, and message append through owning AgentRuntime and NodeConversations generic actions
- [ ] 3.8 Expose GitHub installation binding, review reply, and check update through owning GitHubIntegration generic actions
- [ ] 3.9 Use built-in Ash argument validation, actor context, action hooks, and existing public domain commands without changing current command transaction or concurrency behavior

## 4. Generate Both Transport Surfaces

- [ ] 4.1 Add AshGraphql domain mutation declarations for each public generic action and configure exact Relay ID translations for resource arguments
- [ ] 4.2 Return generated resource objects or action-owned typed results from generated mutations and remove duplicate command-result object definitions
- [ ] 4.3 Add AshJsonApi generic action routes for current external command paths and generated related/relationship routes for supported resource relationships
- [ ] 4.4 Implement owning-domain GraphQL and JSON API error handlers without a central web-layer switch over every command
- [ ] 4.5 Update route-owned Relay operations, fragments, mutation handling, and store invalidation for the generated schema and remove JSON API frontend fallbacks
- [ ] 4.6 Update external JSON API tests to generated resource/action envelopes without retaining unused pre-release compatibility aliases

## 5. Remove Compatibility Code

- [ ] 5.1 Delete superseded GraphQL operator-command mutations, types, and resolver modules
- [ ] 5.2 Delete superseded JSON API operator-command controllers and serializer modules
- [ ] 5.3 Delete shared `OfficeGraphWeb.OperatorCommands.Input` and `OfficeGraphWeb.OperatorCommands.Errors` after their final callers migrate
- [ ] 5.4 Remove manual Ash-resource node dispatch and duplicate GraphQL field loaders while preserving only accepted mixed-projection node resolution
- [ ] 5.5 Reorganize the remaining custom projections, webhook, and provider-callback modules by transport and owning capability with no empty compatibility namespaces
- [ ] 5.6 Replace the temporary migration ledger with the exact terminal custom-path inventory and make canonical verification reject new unclassified paths

## 6. Verify And Finish

- [ ] 6.1 Regenerate the GraphQL schema and Relay artifacts and run Relay compiler, TypeScript, lint, formatting, and frontend behavior tests
- [ ] 6.2 Run focused GraphQL, JSON API, resource relationship, authorization, idempotency, error, operation, and concurrency tests for every migrated command group
- [ ] 6.3 Run formatter, strict Credo, compilation with warnings as errors, architecture tests, and strict OpenSpec validation
- [ ] 6.4 Run the complete canonical `bin/verify` gate and confirm API and database-access inventories remain stable
- [ ] 6.5 Review the final diff for artificial API resources, untyped map results, redundant DTOs, wrapper resolvers, compatibility aliases, namespace churn, and unrelated behavior changes
