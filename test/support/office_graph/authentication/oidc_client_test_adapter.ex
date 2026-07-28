defmodule OfficeGraph.Authentication.OidcClient.TestAdapter do
  @moduledoc false

  @behaviour OfficeGraph.Authentication.OidcClient

  @state_key {__MODULE__, :state}

  def put(responses) when is_map(responses) do
    Process.put(@state_key, %{responses: responses, requests: %{}, calls: %{}})
    :ok
  end

  def authorization_uri(request), do: respond(:authorization_uri, request)
  def exchange(request), do: respond(:exchange, request)
  def logout_uri(request), do: respond(:logout_uri, request)

  def request(operation) do
    get_in(Process.get(@state_key, %{}), [:requests, operation])
  end

  def calls(operation) do
    get_in(Process.get(@state_key, %{}), [:calls, operation]) || 0
  end

  defp respond(operation, request) do
    state = Process.get(@state_key, %{responses: %{}, requests: %{}, calls: %{}})

    Process.put(@state_key, %{
      state
      | requests: Map.put(state.requests, operation, request),
        calls: Map.update(state.calls, operation, 1, &(&1 + 1))
    })

    Map.get(state.responses, operation, {:error, :fixture_not_found})
  end
end
