defmodule OfficeGraph.AgentRuntime.ToolAdapter do
  @moduledoc false

  alias OfficeGraph.AgentRuntime.{AdapterResult, ToolInput, ToolManifest, ToolOutput}

  @callback manifest() :: ToolManifest.t()
  @callback invoke(ToolInput.t()) :: {:ok, ToolOutput.t()} | {:error, AdapterResult.failure()}
  @callback cancel(Ecto.UUID.t()) :: :ok | {:error, :not_found}
end
