defmodule OfficeGraph.GitHubIntegration.ResourceContractTest do
  use ExUnit.Case, async: true

  alias OfficeGraph.GitHubIntegration.{OutboundAction, SyncOutcome}

  test "integration health reads have declarative installation history indexes" do
    assert %AshPostgres.CustomIndex{
             name: "github_sync_outcomes_installation_updated_at_id_index",
             fields: [:installation_id, :updated_at, :id],
             unique: false
           } =
             custom_index(
               SyncOutcome,
               "github_sync_outcomes_installation_updated_at_id_index"
             )

    assert %AshPostgres.CustomIndex{
             name: "github_outbound_actions_installation_updated_at_id_index",
             fields: [:installation_id, :updated_at, :id],
             unique: false
           } =
             custom_index(
               OutboundAction,
               "github_outbound_actions_installation_updated_at_id_index"
             )
  end

  defp custom_index(resource, name) do
    Enum.find(AshPostgres.DataLayer.Info.custom_indexes(resource), &(&1.name == name))
  end
end
