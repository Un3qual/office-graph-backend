defmodule OfficeGraph.GitHubIntegration.SecretStore.TestAdapter do
  @moduledoc false

  @behaviour OfficeGraph.GitHubIntegration.SecretStore

  @state_key {__MODULE__, :secrets}

  def put(secrets) when is_map(secrets) do
    Process.put(@state_key, secrets)
    :ok
  end

  @impl true
  def fetch(reference, _scope) when is_binary(reference) do
    case Process.get(@state_key, %{}) do
      %{^reference => secret} when is_binary(secret) -> {:ok, secret}
      _secrets -> {:error, :secret_not_found}
    end
  end

  def fetch(_reference, _scope), do: {:error, :invalid_secret_reference}
end
