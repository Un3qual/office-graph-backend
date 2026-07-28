defmodule OfficeGraph.Repo.Migrations.AdoptDatabaseGeneratedUuidV7 do
  use Ecto.Migration

  @uuid_v7_primary_keys [
    {"organizations", :id},
    {"workspaces", :id},
    {"initiatives", :id},
    {"workstreams", :id},
    {"principals", :id},
    {"principal_profiles", :id},
    {"credentials", :id},
    {"external_identity_links", :id},
    {"sessions", :id},
    {"authentication_events", :id},
    {"oidc_login_transactions", :id},
    {"capabilities", :id},
    {"roles", :id},
    {"role_capabilities", :id},
    {"role_assignments", :id},
    {"policy_bundles", :id},
    {"authorization_decisions", :id},
    {"operation_correlations", :id},
    {"domain_events", :id},
    {"audit_records", :id},
    {"revisions", :id},
    {"documents", :id},
    {"document_blocks", :id},
    {"document_marks", :id},
    {"document_references", :id},
    {"document_revisions", :id},
    {"external_sources", :id},
    {"raw_archives", :id},
    {"normalized_intake_events", :id},
    {"integration_credentials", :id},
    {"external_references", :id},
    {"repositories", :id},
    {"repository_refs", :id},
    {"commits", :id},
    {"pull_requests", :id},
    {"review_threads", :id},
    {"review_comments", :id},
    {"check_runs", :id},
    {"github_installations", :id},
    {"github_permission_snapshots", :id},
    {"github_permission_entries", :id},
    {"github_installation_credentials", :id},
    {"github_sync_outcomes", :id},
    {"github_outbound_actions", :id},
    {"proposed_graph_changes", :id},
    {"relationship_definitions", :id},
    {"relationship_endpoint_rules", :id},
    {"graph_items", :id},
    {"graph_relationships", :id},
    {"signals", :id},
    {"tasks", :id},
    {"review_findings", :id},
    {"verification_checks", :id},
    {"artifacts", :id},
    {"evidence_candidates", :id},
    {"evidence_items", :id},
    {"verification_results", :id},
    {"work_packets", :id},
    {"work_packet_versions", :id},
    {"work_packet_version_sources", :id},
    {"work_packet_version_required_checks", :id},
    {"runs", :id},
    {"run_required_checks", :id},
    {"execution_observations", :id},
    {"run_events", :id},
    {"agent_definitions", :id},
    {"agent_organization_bindings", :id},
    {"agent_executions", :id},
    {"agent_authority_snapshots", :id},
    {"agent_context_packages", :id},
    {"agent_context_entries", :id},
    {"agent_model_requests", :id},
    {"agent_tool_requests", :id},
    {"agent_approval_requests", :id},
    {"agent_context_expansion_requests", :id},
    {"conversations", :id},
    {"conversation_messages", :id}
  ]

  def up do
    for {table_name, primary_key} <- @uuid_v7_primary_keys do
      alter table(table_name) do
        modify primary_key, :uuid, default: fragment("uuidv7()")
      end
    end
  end

  def down do
    for {table_name, primary_key} <- Enum.reverse(@uuid_v7_primary_keys) do
      alter table(table_name) do
        modify primary_key, :uuid, default: nil
      end
    end
  end
end
