defmodule OfficeGraph.AgentRuntime.RequestOutcome do
  @moduledoc false

  @classified_states ~w(retry_scheduled failed cancelled)

  def classified_attrs(state, failure_code, %DateTime{} = now)
      when state in @classified_states and is_binary(failure_code) do
    %{
      state: state,
      failure_code: failure_code,
      completed_at: if(state in ["failed", "cancelled"], do: now, else: nil)
    }
  end
end
