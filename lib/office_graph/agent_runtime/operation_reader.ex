defmodule OfficeGraph.AgentRuntime.OperationReader do
  @moduledoc false

  alias OfficeGraph.Operations
  alias OfficeGraph.AgentRuntime.StorageResult

  def read_operation(operation_id) do
    StorageResult.run(fn ->
      case Operations.read_operation(operation_id) do
        {:ok, operation} -> {:ok, operation}
        {:error, {:not_found, _resource, _id}} = error -> error
        {:error, _storage_error} -> {:error, :integration_storage_unavailable}
      end
    end)
  end
end
