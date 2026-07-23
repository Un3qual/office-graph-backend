defmodule OfficeGraph.AgentRuntime.Agents.OpenSpecReviewStore do
  @moduledoc false

  alias OfficeGraph.AgentRuntime.{ContextEntry, ModelRequest, StorageResult, ToolRequest}

  require Ash.Query

  def context_entries(context_package_id) do
    StorageResult.run(fn ->
      ContextEntry
      |> Ash.Query.filter(context_package_id == ^context_package_id)
      |> Ash.Query.sort(ordinal: :asc)
      |> Ash.read(authorize?: false)
      |> normalize_read()
    end)
  end

  def read_requests(execution_id) do
    StorageResult.run(fn ->
      ToolRequest
      |> Ash.Query.filter(
        execution_id == ^execution_id and state == "succeeded" and
          tool_key in ["repository.read", "openspec.read"]
      )
      |> Ash.Query.sort(requested_at: :asc, id: :asc)
      |> Ash.read(authorize?: false)
      |> normalize_read()
    end)
  end

  def model_review_request(execution_id) do
    StorageResult.run(fn ->
      ModelRequest
      |> Ash.Query.filter(execution_id == ^execution_id and step_key == "model:review")
      |> Ash.read_one(authorize?: false)
      |> normalize_read()
    end)
  end

  defp normalize_read({:ok, value}), do: {:ok, value}
  defp normalize_read({:error, _storage_error}), do: {:error, :integration_storage_unavailable}
end
