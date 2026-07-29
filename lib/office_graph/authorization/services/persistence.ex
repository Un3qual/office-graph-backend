defmodule OfficeGraph.Authorization.Persistence do
  @moduledoc false

  @callback before_read(:login_scope) :: :ok | {:error, term()}

  def before_read(:login_scope) do
    implementation().before_read(:login_scope)
  end

  defp implementation do
    Application.fetch_env!(:office_graph, :authorization_persistence)
  end
end

defmodule OfficeGraph.Authorization.Persistence.Default do
  @moduledoc false

  @behaviour OfficeGraph.Authorization.Persistence

  @impl true
  def before_read(_stage), do: :ok
end
