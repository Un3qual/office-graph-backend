defmodule OfficeGraph.AgentRuntime.ExecutionLock do
  @moduledoc false

  alias OfficeGraph.AgentRuntime.AgentExecution

  require Ash.Query

  def lock_execution(execution_id) do
    AgentExecution
    |> Ash.Query.filter(id == ^execution_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
  end
end
