defmodule OfficeGraph.GitHubIntegration.SecretStore.Environment do
  @moduledoc false

  @behaviour OfficeGraph.GitHubIntegration.SecretStore

  @impl true
  def fetch("env:" <> variable, _scope) do
    if Regex.match?(~r/^[A-Z][A-Z0-9_]*$/, variable) do
      case System.fetch_env(variable) do
        {:ok, secret} when secret != "" -> {:ok, secret}
        _missing -> {:error, :secret_not_found}
      end
    else
      {:error, :invalid_secret_reference}
    end
  end

  def fetch(_reference, _scope), do: {:error, :invalid_secret_reference}
end
