defmodule OfficeGraph.Verification.ResultSlotPolicyTest do
  use ExUnit.Case, async: true

  alias OfficeGraph.Verification.ResultSlotPolicy

  test "an empty run/check slot is available" do
    assert :ok = ResultSlotPolicy.preflight(nil, "run-id", "check-id")
  end

  test "an occupied run/check slot returns the stable conflict" do
    assert {:error, {:verification_result_slot_conflict, "run-id", "check-id"}} =
             ResultSlotPolicy.preflight(%{id: "result-id"}, "run-id", "check-id")
  end
end
