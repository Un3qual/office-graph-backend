defmodule OfficeGraph.Identity.HumanSessionPersistence do
  @moduledoc false

  @callback before_access(:resolve | :revoke | :event) :: :ok | {:error, term()}

  def before_access(stage) when stage in [:resolve, :revoke, :event] do
    case implementation().before_access(stage) do
      :ok -> :ok
      {:error, _reason} -> {:error, :identity_storage_unavailable}
    end
  end

  defp implementation do
    Application.fetch_env!(:office_graph, :human_session_persistence)
  end
end

defmodule OfficeGraph.Identity.HumanSessionPersistence.Default do
  @moduledoc false

  @behaviour OfficeGraph.Identity.HumanSessionPersistence

  @impl true
  def before_access(_stage), do: :ok
end
