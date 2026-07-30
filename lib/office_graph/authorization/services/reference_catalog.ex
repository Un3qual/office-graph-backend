defmodule OfficeGraph.Authorization.ReferenceCatalog do
  @moduledoc false

  @owner_capabilities %{
    skeleton_read: "skeleton.read",
    durable_delivery_read: "durable_delivery.read",
    manual_intake_submit: "manual_intake.submit",
    proposed_change_apply: "proposed_change.apply",
    evidence_link: "evidence.link",
    verification_complete: "verification.complete",
    work_packet_create: "work_packet.create",
    work_packet_version_create: "work_packet.version.create",
    work_run_start: "work_run.start",
    execution_observation_record: "execution_observation.record",
    evidence_candidate_create: "evidence_candidate.create",
    evidence_accept: "evidence.accept",
    graph_relationship_create: "graph_relationship.create",
    graph_relationship_supersede: "graph_relationship.supersede",
    graph_relationship_archive: "graph_relationship.archive",
    graph_relationship_restore: "graph_relationship.restore",
    agent_definition_bind: "agent.definition.bind",
    agent_invoke: "agent.invoke",
    agent_cancel: "agent.cancel",
    agent_approval_resolve: "agent.approval.resolve",
    agent_context_expansion_resolve: "agent.context_expansion.resolve",
    conversation_write: "conversation.write",
    agent_model_generate: "agent.model.generate",
    agent_tool_read: "agent.tool.read",
    agent_proposal_create: "proposal.create",
    agent_repository_read: "repository.read",
    agent_evidence_suggest: "evidence.suggest",
    github_installation_bind: "github.installation.bind",
    github_review_reply: "github.review.reply",
    github_check_update: "github.check.update",
    verification_waive: "verification.waive"
  }

  @restricted_capabilities %{
    graph_relationship_cross_workspace: "graph_relationship.cross_workspace",
    agent_runtime_execute: "agent.runtime.execute",
    integration_reconcile: "integration.reconcile",
    provider_webhook_receive: "provider.webhook.receive",
    system_conformance: "system.conformance"
  }

  @recognized_capabilities Map.merge(@owner_capabilities, @restricted_capabilities)

  @system_capabilities Map.merge(
                         @restricted_capabilities,
                         Map.take(@owner_capabilities, [
                           :skeleton_read,
                           :agent_model_generate,
                           :agent_proposal_create,
                           :agent_evidence_suggest
                         ])
                       )

  def owner_capabilities, do: @owner_capabilities
  def recognized_capabilities, do: @recognized_capabilities
  def system_capabilities, do: @system_capabilities

  def recognized_capability_keys do
    @recognized_capabilities
    |> Map.values()
    |> Enum.sort()
  end
end
