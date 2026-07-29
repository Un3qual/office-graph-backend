defmodule OfficeGraph.ProposedChanges.Persistence do
  @moduledoc false

  @callback before_write(:manual_intake_changes, map()) :: :ok | {:error, term()}

  def before_write(:manual_intake_changes, context) when is_map(context) do
    case implementation().before_write(:manual_intake_changes, context) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
      _other -> {:error, :integration_storage_unavailable}
    end
  end

  defp implementation do
    Application.get_env(
      :office_graph,
      :proposed_change_persistence,
      OfficeGraph.ProposedChanges.Persistence.Default
    )
  end
end

defmodule OfficeGraph.ProposedChanges.Persistence.Default do
  @moduledoc false

  @behaviour OfficeGraph.ProposedChanges.Persistence

  @impl true
  def before_write(:manual_intake_changes, _context), do: :ok
end
