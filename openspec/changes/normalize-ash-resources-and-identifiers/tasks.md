## 1. Lock Resource Conventions With Tests

- [x] 1.1 Add failing architecture tests that compare concrete migration foreign keys with compiled Ash relationships and reject unexplained `define_attribute? false`
- [x] 1.2 Add failing architecture tests that reject generic `:map` resource attributes and the generic Tombstones context/table
- [x] 1.3 Add failing tests for database-generated primary-key metadata, UUIDv7 values from ordinary creates, and permitted explicit identifiers
- [x] 1.4 Add failing layout tests for responsibility-based grouping and value-object behavior ownership

## 2. Normalize Generic Map Fields

- [x] 2.1 Replace execution-observation metadata and operation-correlation metadata with typed classification and command-digest columns, callers, and replay tests
- [x] 2.2 Replace raw-archive metadata with typed provider event and installation envelope columns and update webhook receipt/worker tests
- [x] 2.3 Replace proposed-change payload maps with typed title/body columns and update creation, validation, replay, and application tests
- [x] 2.4 Replace GitHub outbound-action input maps with validated typed review-reply/check-update columns and update worker/command tests
- [x] 2.5 Remove unused run-event payload, document-mark attrs, and evidence visibility constraints while preserving supported behavior and API contracts

## 3. Move Soft Deletion Into Owning Resources

- [x] 3.1 Add failing graph-relationship deletion and restore tests for in-table deletion actor, operation, timestamp, reason, lifecycle, and projection behavior
- [x] 3.2 Implement graph-relationship tombstone/restore actions with in-table deletion fields and remove the tombstone relationship from projections and APIs
- [x] 3.3 Remove the Tombstones context, domain, resource, schema inventory entry, configuration, and boundary references

## 4. Complete Ash Relationships

- [x] 4.1 Inventory concrete migration foreign keys, polymorphic identifiers, and stable inverse relationships in architecture conformance data
- [x] 4.2 Add missing Tenancy, Identity, Authorization, Operations, Audit, Revision, Content, Integration, and ExternalRefs relationships
- [x] 4.3 Add missing SoftwareProving, GitHubIntegration, ProposedChanges, WorkGraph, WorkPackets, Runs, AgentRuntime, and NodeConversations relationships
- [x] 4.4 Let ordinary `belongs_to` declarations define their source attributes and retain only tested explicit-attribute exceptions
- [x] 4.5 Group every touched resource declaration by identity/scope, lifecycle, domain data, and timestamps

## 5. Adopt Database-Generated UUIDv7

- [x] 5.1 Define the writable data-layer-generated UUID primary-key convention and add focused create tests against PostgreSQL
- [x] 5.2 Convert all durable Ash resource primary keys to the convention and remove ordinary application UUID generation from create paths
- [x] 5.3 Preserve and test only pre-insert identifier allocation required for replay, import, fixtures, or multi-record graph linkage
- [x] 5.4 Upgrade repository-managed PostgreSQL to 18, use the native AshPostgres UUIDv7 default without a compatibility function, and update the exact database-access inventory entry

## 6. Improve Physical Organization

- [x] 6.1 Move AgentRuntime resources, commands, adapters, workers, and value objects into responsibility-based subfolders without module-name changes
- [x] 6.2 Move WorkGraph and GitHubIntegration internals into responsibility-based subfolders without module-name changes
- [x] 6.3 Review every other `lib/office_graph` and `lib/office_graph_web` folder and group materially crowded mixed-responsibility folders
- [x] 6.4 Move reusable construction, normalization, and validation into owning struct modules while documenting genuinely passive DTOs through placement and module docs

## 7. Migrate And Verify

- [x] 7.1 Generate the forward resource migration, verify upgrade behavior, and verify all migrations from an empty database without editing archived migrations
- [x] 7.2 Run formatter, focused architecture/resource/action/concurrency/API tests, compilation with warnings as errors, and strict OpenSpec validation
- [ ] 7.3 Run the complete canonical `bin/verify` gate and confirm the worktree and database-access inventories are stable
- [ ] 7.4 Review the final diff for hidden JSON wrappers, false polymorphic relationships, application UUID defaults, generic tombstones, namespace churn, empty abstractions, and unrelated behavior changes
