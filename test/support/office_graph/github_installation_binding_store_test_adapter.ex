defmodule OfficeGraph.GitHubIntegration.InstallationBindingStoreTestAdapter do
  @moduledoc false

  @behaviour OfficeGraph.GitHubIntegration.InstallationBindingStore

  @response_key :github_installation_binding_store_test_response
  @store_key :github_installation_binding_store

  def configure!(response) do
    configured_store = Application.fetch_env(:office_graph, @store_key)
    configured_response = Application.fetch_env(:office_graph, @response_key)

    Application.put_env(:office_graph, @response_key, response)
    Application.put_env(:office_graph, @store_key, __MODULE__)

    ExUnit.Callbacks.on_exit(fn ->
      restore(@store_key, configured_store)
      restore(@response_key, configured_response)
    end)

    :ok
  end

  @impl true
  def persist(_input, _opts) do
    Application.fetch_env!(:office_graph, @response_key)
  end

  defp restore(key, {:ok, value}), do: Application.put_env(:office_graph, key, value)
  defp restore(key, :error), do: Application.delete_env(:office_graph, key)
end
