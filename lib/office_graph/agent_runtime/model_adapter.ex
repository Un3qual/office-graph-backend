defmodule OfficeGraph.AgentRuntime.ModelAdapter do
  @moduledoc false

  alias OfficeGraph.AgentRuntime.{ModelInput, ModelManifest, ModelOutput}

  @callback manifest() :: ModelManifest.t()
  @callback invoke(ModelInput.t()) :: {:ok, ModelOutput.t()} | {:error, AdapterResult.failure()}
  @callback cancel(Ecto.UUID.t()) :: :ok | {:error, :not_found}
end
