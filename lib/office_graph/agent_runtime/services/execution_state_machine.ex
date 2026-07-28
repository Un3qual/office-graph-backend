defmodule OfficeGraph.AgentRuntime.ExecutionStateMachine do
  @moduledoc false

  @terminal_states ~w(completed failed cancelled)
  @transitions %{
    "queued" => ~w(running waiting_approval waiting_context failed cancelled),
    "running" =>
      ~w(running waiting_approval waiting_context retry_scheduled completed failed cancelled),
    "waiting_approval" => ~w(queued running failed cancelled),
    "waiting_context" => ~w(queued running failed cancelled),
    "retry_scheduled" => ~w(running failed cancelled),
    "completed" => [],
    "failed" => [],
    "cancelled" => []
  }

  def validate(from, to) when is_binary(from) and is_binary(to) do
    if to in Map.get(@transitions, from, []),
      do: :ok,
      else: {:error, {:invalid_agent_execution_transition, from, to}}
  end

  def validate(from, to), do: {:error, {:invalid_agent_execution_transition, from, to}}

  def terminal?(state), do: state in @terminal_states
end
