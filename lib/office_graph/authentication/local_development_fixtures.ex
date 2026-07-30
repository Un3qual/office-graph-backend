defmodule OfficeGraph.Authentication.LocalDevelopmentFixtures do
  @moduledoc false

  @provider "local_development"
  @provider_tenant "office_graph_development"

  @fixtures [
    %{
      key: "owner",
      subject: "owner",
      email: "owner@office-graph.local",
      display_name: "Office Graph Owner",
      principal_status: "active",
      link_status: "active",
      role_profile: :owner
    },
    %{
      key: "workspace_admin",
      subject: "workspace-admin",
      email: "workspace-admin@office-graph.local",
      display_name: "Workspace Administrator",
      principal_status: "active",
      link_status: "active",
      role_profile: :workspace_admin
    },
    %{
      key: "member",
      subject: "member",
      email: "member@office-graph.local",
      display_name: "Workspace Member",
      principal_status: "active",
      link_status: "active",
      role_profile: :member
    },
    %{
      key: "deprovisioned_member",
      subject: "deprovisioned-member",
      email: "deprovisioned@office-graph.local",
      display_name: "Deprovisioned Member",
      principal_status: "disabled",
      link_status: "disabled",
      role_profile: :member
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
