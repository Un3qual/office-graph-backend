defmodule OfficeGraph.AgentRuntime.StorageResultTest do
  use ExUnit.Case, async: true

  alias OfficeGraph.AgentRuntime.StorageResult

  test "database connection failures map to stable storage unavailability" do
    assert {:error, :integration_storage_unavailable} =
             StorageResult.run(fn ->
               raise DBConnection.ConnectionError, message: "database unavailable"
             end)
  end

  test "programming errors are not disguised as storage unavailability" do
    assert_raise RuntimeError, "programming fault", fn ->
      StorageResult.run(fn -> raise "programming fault" end)
    end
  end
end
