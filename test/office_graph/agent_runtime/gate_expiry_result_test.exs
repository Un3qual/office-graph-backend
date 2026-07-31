defmodule OfficeGraph.AgentRuntime.GateExpiryResultTest do
  use ExUnit.Case, async: true

  alias OfficeGraph.AgentRuntime.GateExpiryResult

  test "storage unavailability remains retryable after the nominal attempt budget" do
    assert {:snooze, 5} =
             GateExpiryResult.to_oban_result({:error, :integration_storage_unavailable})
  end

  test "permanent expiry errors retain normal Oban error handling" do
    error = %Ash.Error.Invalid{errors: []}
    assert {:error, ^error} = GateExpiryResult.to_oban_result({:error, error})
  end
end
