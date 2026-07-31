defmodule OfficeGraph.Release do
  @moduledoc """
  Idempotent application-data setup for a migrated Office Graph database.

  In a packaged release, run:

      bin/office_graph eval "OfficeGraph.Release.setup!()"
  """

  alias OfficeGraph.AgentRuntime.Domain, as: AgentRuntime
  alias OfficeGraph.Authorization.Domain, as: Authorization
  alias OfficeGraph.WorkGraph.Domain, as: WorkGraph

  def setup do
    with {:ok, _capability_count} <- Authorization.setup_reference_data(),
         {:ok, _relationship_count} <- WorkGraph.setup_reference_data(),
         {:ok, _agent_definition_count} <- AgentRuntime.setup_reference_data() do
      :ok
    end
  end

  def setup! do
    case setup() do
      :ok -> :ok
      {:error, error} -> raise "Office Graph setup failed: #{inspect(error)}"
    end
  end
end
