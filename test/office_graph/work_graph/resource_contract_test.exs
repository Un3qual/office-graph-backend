defmodule OfficeGraph.WorkGraph.ResourceContractTest do
  use ExUnit.Case, async: true

  alias OfficeGraph.WorkGraph.{EvidenceCandidate, EvidenceItem, GraphItem, VerificationResult}

  test "run history resources expose declarative chronological access paths" do
    for {resource, name} <- [
          {EvidenceCandidate, "evidence_candidates_work_run_inserted_at_id_index"},
          {EvidenceItem, "evidence_items_work_run_inserted_at_id_index"},
          {VerificationResult, "verification_results_work_run_inserted_at_id_index"}
        ] do
      assert %AshPostgres.CustomIndex{
               fields: [:work_run_id, :inserted_at, :id],
               unique: false
             } = custom_index(resource, name)
    end
  end

  test "graph item listing exposes a declarative tenant scope access path" do
    assert %AshPostgres.CustomIndex{
             fields: [:organization_id, :workspace_id, :id],
             unique: false
           } = custom_index(GraphItem, "graph_items_scope_id_index")
  end

  defp custom_index(resource, name) do
    Enum.find(AshPostgres.DataLayer.Info.custom_indexes(resource), &(&1.name == name))
  end
end
