defmodule OfficeGraph.GitHubIntegration.SecretStore do
  @moduledoc """
  Resolves opaque integration credential references without exposing them through products APIs.
  """

  alias OfficeGraph.Integrations.IntegrationCredential

  @callback fetch(reference :: String.t(), scope :: map()) ::
              {:ok, String.t()}
              | {:error, :invalid_secret_reference | :secret_not_found | :unavailable}

  def resolve(credential_id, scope, adapter \\ configured_adapter())

  def resolve(credential_id, %{organization_id: organization_id} = scope, adapter)
      when is_binary(credential_id) and is_binary(organization_id) and is_atom(adapter) do
    with {:ok, %IntegrationCredential{} = credential} <-
           load_credential(credential_id),
         :ok <- authorize_scope(credential, scope),
         :ok <- require_active(credential),
         {:ok, secret} <- adapter.fetch(credential.secret_reference, scope) do
      {:ok, secret}
    else
      {:ok, nil} ->
        {:error, :secret_not_found}

      {:error, :forbidden} = error ->
        error

      {:error, reason}
      when reason in [:invalid_secret_reference, :secret_not_found, :unavailable] ->
        {:error, reason}

      {:error, _error} ->
        {:error, :unavailable}
    end
  end

  def resolve(_credential_id, _scope, _adapter), do: {:error, :forbidden}

  defp authorize_scope(credential, scope) do
    requested_workspace_id = Map.get(scope, :workspace_id, Map.get(scope, "workspace_id"))

    if credential.organization_id == scope.organization_id and
         credential.workspace_id == requested_workspace_id do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp require_active(%IntegrationCredential{status: "active"}), do: :ok
  defp require_active(_credential), do: {:error, :forbidden}

  defp load_credential(credential_id) do
    Ash.get(IntegrationCredential, credential_id,
      authorize?: false,
      not_found_error?: false
    )
  end

  defp configured_adapter do
    Application.fetch_env!(:office_graph, :github_secret_store)
  end
end
