defmodule OfficeGraph.Runs.ResourceContractTest do
  use ExUnit.Case, async: true

  alias OfficeGraph.Runs.ExecutionObservation

  test "execution observation history exposes a declarative run access path" do
    assert %AshPostgres.CustomIndex{
             fields: [:work_run_id, :inserted_at, :id],
             unique: false
           } =
             Enum.find(
               AshPostgres.DataLayer.Info.custom_indexes(ExecutionObservation),
               &(&1.name == "execution_observations_work_run_inserted_at_id_index")
             )
  end
end
