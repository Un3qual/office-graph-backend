defmodule OfficeGraph.Authentication.LocalDevelopmentFixtures do
  @moduledoc false

  @provider "local_development"
  @provider_tenant "office_graph_development"

  # These profiles exist to exercise meaningful authorization differences in
  # local development. They are not production default-role policy.
  @workspace_admin_actions [
    :skeleton_read,
    :durable_delivery_read,
    :manual_intake_submit,
    :proposed_change_apply,
    :evidence_link,
    :verification_complete,
    :work_packet_create,
    :work_packet_version_create,
    :work_run_start,
    :execution_observation_record,
    :evidence_candidate_create,
    :evidence_accept,
    :graph_relationship_create,
    :graph_relationship_supersede,
    :graph_relationship_archive,
    :graph_relationship_restore,
    :agent_definition_bind,
    :agent_invoke,
    :agent_cancel,
    :agent_approval_resolve,
    :agent_context_expansion_resolve,
    :conversation_write
  ]

  @member_actions [
    :skeleton_read,
    :durable_delivery_read,
    :manual_intake_submit,
    :conversation_write
  ]

  @fixtures [
    %{
      key: "owner",
      subject: "owner",
      email: "owner@office-graph.local",
      display_name: "Office Graph Owner",
      principal_status: "active",
      link_status: "active",
      role_profile: :owner,
      role_key: "owner",
      scope: :workspace,
      actions: []
    },
    %{
      key: "workspace_admin",
      subject: "workspace-admin",
      email: "workspace-admin@office-graph.local",
      display_name: "Workspace Administrator",
      principal_status: "active",
      link_status: "active",
      role_profile: :workspace_admin,
      role_key: "workspace_admin",
      scope: :workspace,
      actions: @workspace_admin_actions
    },
    %{
      key: "member",
      subject: "member",
      email: "member@office-graph.local",
      display_name: "Workspace Member",
      principal_status: "active",
      link_status: "active",
      role_profile: :member,
      role_key: "member",
      scope: :workspace,
      actions: @member_actions
    },
    %{
      key: "deprovisioned_member",
      subject: "deprovisioned-member",
      email: "deprovisioned@office-graph.local",
      display_name: "Deprovisioned Member",
      principal_status: "disabled",
      link_status: "disabled",
      role_profile: :member,
      role_key: "member",
      scope: :workspace,
      actions: @member_actions
    }
  ]

  def all do
    Enum.map(@fixtures, &Map.merge(&1, provider_metadata()))
  end

  def fetch(key) when is_binary(key) do
    case Enum.find(all(), &(&1.key == key)) do
      nil -> :error
      fixture -> {:ok, fixture}
    end
  end

  def fetch(_key), do: :error

  def provider, do: @provider
  def provider_tenant, do: @provider_tenant

  defp provider_metadata do
    %{provider: @provider, provider_tenant: @provider_tenant}
  end
end
