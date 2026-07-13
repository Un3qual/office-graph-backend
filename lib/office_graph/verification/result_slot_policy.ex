defmodule OfficeGraph.Verification.ResultSlotPolicy do
  @moduledoc false

  def preflight(nil, _run_id, _verification_check_id), do: :ok

  def preflight(_existing_result, run_id, verification_check_id) do
    {:error, {:verification_result_slot_conflict, run_id, verification_check_id}}
  end
end
