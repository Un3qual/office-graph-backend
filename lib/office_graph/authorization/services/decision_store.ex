defmodule OfficeGraph.Authorization.DecisionStore do
  @moduledoc false

  @callback record(map()) :: :ok | {:error, term()}

  def record(attrs) when is_map(attrs) do
    implementation().record(attrs)
  end

  defp implementation do
    Application.fetch_env!(:office_graph, :authorization_decision_store)
  end
end

defmodule OfficeGraph.Authorization.DecisionStore.AshAdapter do
  @moduledoc false

  @behaviour OfficeGraph.Authorization.DecisionStore

  alias OfficeGraph.Authorization.AuthorizationDecision

  @impl true
  def record(attrs) do
    AuthorizationDecision
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create(authorize?: false, return_notifications?: true)
    |> case do
      {:ok, _decision, _notifications} -> :ok
      {:ok, _decision} -> :ok
      {:error, error} -> {:error, {:authorization_decision_failed, error}}
    end
  end
end
