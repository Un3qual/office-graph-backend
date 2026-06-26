defmodule OfficeGraphWeb.OperatorWorkflowSerializer do
  @moduledoc false

  def inbox(inbox) do
    %{
      type: inbox.type,
      empty: Map.fetch!(inbox, :empty?),
      source_watermark: inbox.source_watermark,
      rows: Enum.map(inbox.rows, &item/1)
    }
  end

  def item(item) do
    %{
      type: item.type,
      typed_id: typed_id(item.typed_id),
      normalized_event_id: item.normalized_event_id,
      duplicate_of_id: item.duplicate_of_id,
      status: item.status,
      reason_codes: item.reason_codes,
      source: item.source,
      proposed_change_status: item.proposed_change_status,
      blocker_reasons: item.blocker_reasons,
      allowed_next_actions: item.allowed_next_actions,
      operation_watermark: item.operation_watermark,
      source_watermark: item.source_watermark,
      graph_links: Enum.map(item.graph_links, &graph_link/1),
      graph_relationships: Enum.map(item.graph_relationships, &graph_relationship/1),
      audit_trace: trace(item.audit_trace),
      revision_trace: trace(item.revision_trace)
    }
  end

  def packet_readiness(readiness) do
    %{
      type: readiness.type,
      ready: Map.fetch!(readiness, :ready?),
      status: readiness.status,
      allowed_next_actions: readiness.allowed_next_actions,
      blocker_reasons: readiness.blocker_reasons,
      source_links: Enum.map(readiness.source_links, &source_link/1),
      required_checks: Enum.map(readiness.required_checks, &required_check/1),
      source_watermark: readiness.source_watermark
    }
  end

  def run_state(run_state) do
    %{
      type: run_state.type,
      status: run_state.status,
      allowed_next_actions: run_state.allowed_next_actions,
      source_watermark: run_state.source_watermark,
      packet: run_state.packet,
      packet_version: run_state.packet_version,
      run: run_state.run,
      required_checks: run_state.required_checks,
      observations: run_state.observations,
      evidence_candidates: run_state.evidence_candidates,
      evidence_items: run_state.evidence_items,
      verification_results: run_state.verification_results,
      missing_evidence: run_state.missing_evidence
    }
  end

  def verification_outcome(outcome) do
    %{
      type: outcome.type,
      status: outcome.status,
      source_watermark: outcome.source_watermark,
      run: outcome.run,
      verification_results: outcome.verification_results,
      missing_evidence: outcome.missing_evidence
    }
  end

  defp typed_id(typed_id) do
    %{
      type: typed_id.type,
      id: typed_id.id
    }
  end

  defp graph_link(link) do
    %{
      type: link.type,
      id: link.id,
      graph_item_id: link.graph_item_id,
      title: link.title,
      state: link.state
    }
  end

  defp graph_relationship(relationship) do
    %{
      id: relationship.id,
      source_graph_item_id: relationship.source_graph_item_id,
      target_graph_item_id: relationship.target_graph_item_id,
      relationship_type: relationship.relationship_type
    }
  end

  defp source_link(link) do
    %{
      type: link.type,
      id: link.id,
      graph_item_id: link.graph_item_id,
      title: link.title
    }
  end

  defp required_check(check) do
    %{
      id: check.id,
      graph_item_id: check.graph_item_id,
      state: check.state
    }
  end

  defp trace(trace) do
    %{
      operation_id: trace.operation_id,
      resource_count: trace.resource_count,
      resources: Enum.map(Map.get(trace, :resources, []), &typed_id/1)
    }
  end
end
