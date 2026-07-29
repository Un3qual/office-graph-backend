defmodule OfficeGraph.Authorization.Persistence do
  @moduledoc false

  @callback before_read(:login_scope | :principal_capability | :system_principal) ::
              :ok | {:error, term()}

  def before_read(stage) when stage in [:login_scope, :principal_capability, :system_principal] do
    case implementation().before_read(stage) do
      :ok -> :ok
      {:error, _reason} -> unavailable(stage)
    end
  end

  defp implementation do
    Application.fetch_env!(:office_graph, :authorization_persistence)
  end

  defp unavailable(:login_scope), do: {:error, :authorization_storage_unavailable}
  defp unavailable(:principal_capability), do: {:error, :integration_storage_unavailable}
  defp unavailable(:system_principal), do: {:error, :integration_storage_unavailable}
end

defmodule OfficeGraph.Authorization.Persistence.Default do
  @moduledoc false

  @behaviour OfficeGraph.Authorization.Persistence

  @impl true
  def before_read(_stage), do: :ok
end
