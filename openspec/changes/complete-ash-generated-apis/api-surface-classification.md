# API Surface Classification

This inventory classifies every hand-written GraphQL and JSON API surface that
exists at the start of `complete-ash-generated-apis`. It is an implementation
inventory, not an exception ledger: entries classified as generated reads,
generated actions, or removal must disappear from the terminal custom-path
inventory.

The terminal classes are:

- `generated resource`: an Ash resource type, relationship, read, or Relay
  connection owns the surface;
- `generated action`: an owning Ash domain action and its typed arguments,
  result, metadata, and errors own the surface for both transports;
- `mixed projection`: a capability-owned projection may remain hand-written
  because it combines multiple resources into a deliberately different read
  model;
- `provider callback`: an externally dictated webhook or provider callback may
  remain a transport boundary;
- `remove`: the surface is pre-release compatibility or duplicates another
  supported surface.

## Manual GraphQL Root Fields

| Surface | Current owner | Terminal class | Target |
|---|---|---|---|
| `graphql.query.health` | `OfficeGraphWeb.GraphQL.Common.Queries` | remove | Keep the HTTP health boundary; do not expose an unrelated GraphQL compatibility field. |
| `graphql.query.operator_run_conversation` | `OfficeGraph.NodeConversations` | generated resource | `conversationForRunGraphItem` and generated conversation, message, execution, approval, and context relationships own resource data; the existing name retains only command affordances, source watermarking, and independently redacted message-context facts until the projection cleanup milestone. |
| `graphql.query.github_integration_health` | `OfficeGraph.GitHubIntegration` | mixed projection | Capability-owned typed health projection action. |
| `graphql.query.graph_relationships` | `OfficeGraph.WorkGraph` | mixed projection | Redacted relationship-view projection; stable returned views remain Relay nodes. |
| `graphql.query.operator_workflow_items` | `OfficeGraph.Projections` | mixed projection | Capability-owned workflow projection connection. |
| `graphql.query.operator_runs` | `OfficeGraph.Runs` | generated resource | `listWorkRuns` and generated packet relationship. |
| `graphql.query.operator_workflow_item` | `OfficeGraph.Projections` | mixed projection | Capability-owned workflow projection node read. |
| `graphql.query.operator_relationship_details` | `OfficeGraph.WorkGraph` | mixed projection | Redacted relationship-detail projection connection. |
| `graphql.query.operator_packet_readiness` | `OfficeGraph.WorkPackets` | generated action | Typed packet-readiness Ash query action. |
| `graphql.query.operator_packet_workspace` | `OfficeGraph.Projections` | mixed projection | Retain only readiness, blockers, next actions, and command affordances; `getWorkPacket` and generated relationships own every packet resource field. |
| `graphql.query.operator_packet_create_affordance` | `OfficeGraph.WorkPackets` | mixed projection | Capability-owned command-affordance projection. |
| `graphql.query.operator_manual_intake_affordance` | `OfficeGraph.Integrations` | mixed projection | Capability-owned command-affordance projection. |
| `graphql.query.operator_run_state` | `OfficeGraph.Runs` | mixed projection | Retain only derived status, command affordances and options, child summary, activity, missing-evidence facts, and a source watermark; `getWorkRun` owns all resource fields and relationships. |
| `graphql.query.operator_run_command_option_page` | `OfficeGraph.Runs` | mixed projection | Capability-owned command-option projection connection. |
| `graphql.query.operator_verification_outcome` | `OfficeGraph.Verification` | remove | Fold derived status and missing-evidence facts into `operatorRunState`; generated `getWorkRun` relationships own verification-result resources. |

Every current mutation is a generated owning-domain action target:

| Surface | Owning Ash domain |
|---|---|
| `graphql.mutation.invoke_agent` | `OfficeGraph.AgentRuntime` |
| `graphql.mutation.cancel_agent_execution` | `OfficeGraph.AgentRuntime` |
| `graphql.mutation.start_run_conversation` | `OfficeGraph.NodeConversations` |
| `graphql.mutation.append_conversation_message` | `OfficeGraph.NodeConversations` |
| `graphql.mutation.resolve_agent_approval` | `OfficeGraph.AgentRuntime` |
| `graphql.mutation.resolve_agent_context_expansion` | `OfficeGraph.AgentRuntime` |
| `graphql.mutation.bind_github_installation` | `OfficeGraph.GitHubIntegration` |
| `graphql.mutation.reply_to_github_review` | `OfficeGraph.GitHubIntegration` |
| `graphql.mutation.update_github_check` | `OfficeGraph.GitHubIntegration` |
| `graphql.mutation.submit_manual_intake` | `OfficeGraph.Integrations` |
| `graphql.mutation.apply_proposed_changes` | `OfficeGraph.ProposedChanges` |
| `graphql.mutation.create_work_packet` | `OfficeGraph.WorkPackets` |
| `graphql.mutation.create_work_packet_version` | `OfficeGraph.WorkPackets` |
| `graphql.mutation.start_work_run` | `OfficeGraph.Runs` |
| `graphql.mutation.record_execution_observation` | `OfficeGraph.Runs` |
| `graphql.mutation.create_evidence_candidate` | `OfficeGraph.Verification` |
| `graphql.mutation.accept_evidence` | `OfficeGraph.Verification` |
| `graphql.mutation.waive_verification_check` | `OfficeGraph.Verification` |

## Manual GraphQL Types

The following current types mirror Ash resources and must be replaced by the
generated resource type and generated relationship loading:

- `graphql.type.operator_packet_workspace_packet`
- `graphql.type.operator_packet_workspace_version`
- `graphql.type.operator_run_ref`
- `graphql.type.operator_packet_ref`
- `graphql.type.operator_packet_version_ref`
- `graphql.type.operator_run_summary`
- `graphql.type.operator_observation`
- `graphql.type.operator_evidence_candidate`
- `graphql.type.operator_evidence_item`
- `graphql.type.operator_verification_result`
- `graphql.type.operator_run_conversation_context_entry`
- `graphql.type.operator_run_conversation_record`
- `graphql.type.operator_run_conversation_message`
- `graphql.type.operator_run_conversation_execution`
- `graphql.type.operator_run_conversation_approval_request`
- `graphql.type.operator_run_conversation_context_expansion_request`
- `graphql.type.operator_command_agent_request`
- `graphql.type.operator_command_agent_execution`
- `graphql.type.github_installation_command_result`
- `graphql.type.github_permission_snapshot_command_result`
- `graphql.type.github_permission_command_result`
- `graphql.type.github_credential_command_result`
- `graphql.type.github_outbound_action_command_result`
- `graphql.type.operator_command_signal`
- `graphql.type.operator_command_task`
- `graphql.type.operator_command_review_finding`
- `graphql.type.operator_command_verification_check`
- `graphql.type.operator_command_work_packet`
- `graphql.type.operator_command_work_packet_version`
- `graphql.type.operator_command_work_run`
- `graphql.type.operator_command_run_required_check`
- `graphql.type.operator_command_execution_observation`
- `graphql.type.operator_command_evidence_candidate`
- `graphql.type.operator_command_evidence_item`
- `graphql.type.operator_command_verification_result`

The following current types are action inputs, action results, or operation
metadata. They move to owning Ash action arguments, action-owned typed result
structs only where multiple results are necessary, and action metadata. Generic
payload wrappers that add no domain meaning are removed:

- `graphql.type.operator_typed_id`
- `graphql.type.invoke_agent_input`
- `graphql.type.cancel_agent_execution_input`
- `graphql.type.start_run_conversation_input`
- `graphql.type.append_conversation_message_input`
- `graphql.type.resolve_agent_approval_input`
- `graphql.type.resolve_agent_context_expansion_input`
- `graphql.type.github_installation_permission_input`
- `graphql.type.bind_github_installation_input`
- `graphql.type.reply_to_github_review_input`
- `graphql.type.update_github_check_input`
- `graphql.type.submit_manual_intake_input`
- `graphql.type.apply_proposed_changes_input`
- `graphql.type.create_work_packet_input`
- `graphql.type.create_work_packet_version_input`
- `graphql.type.start_work_run_input`
- `graphql.type.record_execution_observation_input`
- `graphql.type.create_evidence_candidate_input`
- `graphql.type.accept_evidence_input`
- `graphql.type.waive_verification_check_input`
- `graphql.type.start_run_conversation_payload`
- `graphql.type.append_conversation_message_payload`
- `graphql.type.invoke_agent_payload`
- `graphql.type.cancel_agent_execution_payload`
- `graphql.type.resolve_agent_approval_payload`
- `graphql.type.resolve_agent_context_expansion_payload`
- `graphql.type.bind_github_installation_payload`
- `graphql.type.github_outbound_action_payload`
- `graphql.type.submit_manual_intake_payload`
- `graphql.type.apply_proposed_changes_payload`
- `graphql.type.create_work_packet_payload`
- `graphql.type.create_work_packet_version_payload`
- `graphql.type.start_work_run_payload`
- `graphql.type.record_execution_observation_payload`
- `graphql.type.create_evidence_candidate_payload`
- `graphql.type.accept_evidence_payload`
- `graphql.type.waive_verification_check_payload`

The following current types are mixed projection shapes. They remain custom
only when the implementation still returns the classified projection; stable
identity-bearing shapes must be Relay nodes and growing collections must be
Relay connections:

- `graphql.type.operator_source`
- `graphql.type.operator_proposed_change_status`
- `graphql.type.operator_proposed_action_preview`
- `graphql.type.operator_graph_link`
- `graphql.type.operator_graph_relationship`
- `graphql.type.graph_relationship_endpoint`
- `graphql.type.graph_relationship_view`
- `graphql.type.operator_trace`
- `graphql.type.operator_command_affordance`
- `graphql.type.operator_command_input_default`
- `graphql.type.operator_relationship_summary`
- `graphql.type.operator_relationship_detail`
- `graphql.type.operator_workflow_item`
- `graphql.type.operator_required_check`
- `graphql.type.operator_source_link`
- `graphql.type.operator_packet_readiness`
- `graphql.type.operator_packet_workspace`
- `graphql.type.operator_missing_evidence`
- `graphql.type.operator_run_activity`
- `graphql.type.operator_run_conversation_referenced_context`
- `graphql.type.operator_run_conversation_message_context`
- `graphql.type.operator_run_conversation`
- `graphql.type.operator_run_child_summary`
- `graphql.type.operator_observation_command_option`
- `graphql.type.operator_observation_outcome_option`
- `graphql.type.operator_evidence_candidate_command_option`
- `graphql.type.operator_evidence_acceptance_command_option`
- `graphql.type.operator_waiver_command_option`
- `graphql.type.operator_run_command_options`
- `graphql.type.operator_run_command_option_choice`
- `graphql.type.operator_run_command_option_summary`
- `graphql.type.operator_run_state`
- `graphql.type.github_integration_permission_health`
- `graphql.type.github_integration_credential_health`
- `graphql.type.github_integration_failure_health`
- `graphql.type.github_integration_health`
- `graphql.type.operator_packet_readiness_input`

The terminal projection identity classification is:

- `OperatorWorkflowItem` and `GraphRelationshipView` retain their existing
  Relay Node contracts;
- `OperatorPacketWorkspace`, `OperatorRunState`,
  `OperatorRunConversation`, and `GithubIntegrationHealth` are stable,
  authorized projections with canonical inputs and therefore implement Relay
  Node with authorized refetch;
- packet readiness is input-dependent and has no stable refetch identity;
- relationship detail rows, run activity rows, command options, command
  affordances, summaries, health child values, and message-context facts exist
  only inside their parent projection and remain ordinary typed objects rather
  than receiving invented Node identities.

## Manual JSON Routes

The provider-owned webhook is the sole provider-callback exception:

| Surface | Terminal class |
|---|---|
| `json.post./api/v1/webhooks/github` | provider callback |

The following reads move to generated resources or generated typed query
actions:

| Surface | Terminal class |
|---|---|
| `json.get./api/v1/graph-items/:item_id/relationships` | mixed projection |
| `json.get./api/v1/github/installations/:installation_id/health` | generated action |
| `json.get./api/v1/runs/:run_id/graph-items/:graph_item_id/conversation` | generated resource |

Every current command route is a generated owning-domain action target:

- `json.post./api/v1/commands/submit-manual-intake`
- `json.post./api/v1/commands/bind-github-installation`
- `json.post./api/v1/commands/reply-to-github-review`
- `json.post./api/v1/commands/update-github-check`
- `json.post./api/v1/commands/apply-proposed-changes`
- `json.post./api/v1/commands/create-work-packet`
- `json.post./api/v1/commands/create-work-packet-version`
- `json.post./api/v1/commands/start-work-run`
- `json.post./api/v1/commands/resolve-agent-approval`
- `json.post./api/v1/commands/resolve-agent-context-expansion`
- `json.post./api/v1/commands/invoke-agent`
- `json.post./api/v1/commands/cancel-agent-execution`
- `json.post./api/v1/commands/start-run-conversation`
- `json.post./api/v1/commands/append-conversation-message`
- `json.post./api/v1/commands/record-execution-observation`
- `json.post./api/v1/commands/create-evidence-candidate`
- `json.post./api/v1/commands/accept-evidence`
- `json.post./api/v1/commands/waive-verification-check`

`serializer.OfficeGraphWeb.JsonApi.OperatorCommands.Serializer` is generated
action serialization, not a terminal custom serializer.

## Transport Implementation Files

These files are migration inputs and are deleted after their callers move to
owning Ash actions:

- `lib/office_graph_web/graphql/operator_commands/mutations.ex`
- `lib/office_graph_web/graphql/operator_commands/types.ex`
- `lib/office_graph_web/graphql/operator_commands/resolvers/agents.ex`
- `lib/office_graph_web/graphql/operator_commands/resolvers/github.ex`
- `lib/office_graph_web/graphql/operator_commands/resolvers/intake.ex`
- `lib/office_graph_web/graphql/operator_commands/resolvers/packets.ex`
- `lib/office_graph_web/graphql/operator_commands/resolvers/runs.ex`
- `lib/office_graph_web/graphql/operator_commands/resolvers/verification.ex`
- `lib/office_graph_web/json_api/operator_commands/agents_controller.ex`
- `lib/office_graph_web/json_api/operator_commands/github_controller.ex`
- `lib/office_graph_web/json_api/operator_commands/intake_controller.ex`
- `lib/office_graph_web/json_api/operator_commands/packets_controller.ex`
- `lib/office_graph_web/json_api/operator_commands/runs_controller.ex`
- `lib/office_graph_web/json_api/operator_commands/verification_controller.ex`
- `lib/office_graph_web/json_api/operator_commands/serializer.ex`
- `lib/office_graph_web/operator_commands/input.ex`
- `lib/office_graph_web/operator_commands/errors.ex`

The following general-purpose web transport helpers remain only to serve
accepted custom projections or provider callbacks. Generated AshGraphql and
AshJsonApi paths use their owning-domain error handlers and actor context:

- `lib/office_graph_web/graphql/common/errors.ex`
- `lib/office_graph_web/json_api/common/errors.ex`
- `lib/office_graph_web/request_session.ex`
- `lib/office_graph_web/controllers/github_webhook_controller.ex`
- `lib/office_graph_web/json_api/relationships/controller.ex`
- `lib/office_graph_web/json_api/github_health_controller.ex`
- `lib/office_graph_web/json_api/conversations_controller.ex`

## Terminal Inventory Rule

At completion, the canonical inventory contains only the accepted mixed
projection and provider-callback entries above. It must not contain migration
targets, `operator_commands` namespaces, resource-mirroring GraphQL objects,
custom command controllers, a custom command serializer, or a central
transport-layer command input/error switch.
