defmodule OfficeGraph.Runs.ObservationStateReducer do
  @moduledoc false

  def next_state(run, normalized_status, failed_observations?) do
    cond do
      normalized_status != "succeeded" -> :failed
      failed_state?(run) -> :preserve
      failed_observations? -> :failed
      verified_state?(run) -> :preserve
      true -> :awaiting_verification
    end
  end

  defp failed_state?(run) do
    Map.get(run, :state) == "failed" or Map.get(run, :aggregate_state) == "failed" or
      Map.get(run, :execution_state) == "failed" or
      Map.get(run, :verification_state) == "failed"
  end

  defp verified_state?(run) do
    Map.get(run, :state) == "verified" or Map.get(run, :aggregate_state) == "verified" or
      Map.get(run, :verification_state) == "verified"
  end
end
