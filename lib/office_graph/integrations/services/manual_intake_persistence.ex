defmodule OfficeGraph.Integrations.ManualIntakePersistence do
  @moduledoc false

  @callback before_write(:raw_archive, map()) :: :ok | {:error, term()}

  def before_write(:raw_archive, attrs) when is_map(attrs) do
    case implementation().before_write(:raw_archive, attrs) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
      _other -> {:error, :integration_storage_unavailable}
    end
  end

  defp implementation do
    Application.get_env(
      :office_graph,
      :manual_intake_persistence,
      OfficeGraph.Integrations.ManualIntakePersistence.Default
    )
  end
end

defmodule OfficeGraph.Integrations.ManualIntakePersistence.Default do
  @moduledoc false

  @behaviour OfficeGraph.Integrations.ManualIntakePersistence

  @impl true
  def before_write(:raw_archive, _attrs), do: :ok
end
