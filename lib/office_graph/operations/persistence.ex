defmodule OfficeGraph.Operations.Persistence do
  @moduledoc false

  @callback before_write(:human_operation | :system_operation) :: :ok | {:error, term()}

  def before_write(stage) when stage in [:human_operation, :system_operation] do
    implementation().before_write(stage)
  end

  defp implementation do
    Application.fetch_env!(:office_graph, :operation_persistence)
  end
end

defmodule OfficeGraph.Operations.Persistence.Default do
  @moduledoc false

  @behaviour OfficeGraph.Operations.Persistence

  @impl true
  def before_write(_stage), do: :ok
end
