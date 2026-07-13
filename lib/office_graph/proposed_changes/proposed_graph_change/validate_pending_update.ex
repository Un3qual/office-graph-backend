defmodule OfficeGraph.ProposedChanges.ProposedGraphChange.ValidatePendingUpdate do
  @moduledoc false

  use Ash.Resource.Change

  alias OfficeGraph.ProposedChanges.ProposedGraphChange

  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case changeset.data do
        %{id: id} when is_binary(id) -> validate_current_status(changeset, id)
        _data -> changeset
      end
    end)
  end

  defp validate_current_status(changeset, id) do
    ProposedGraphChange
    |> Ash.Query.filter(id == ^id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %{status: "pending"}} ->
        changeset

      {:ok, _non_pending_or_missing} ->
        Ash.Changeset.add_error(changeset, field: :status, message: "must be pending")

      {:error, error} ->
        Ash.Changeset.add_error(changeset,
          field: :status,
          message: "status lookup failed: #{inspect(error)}"
        )
    end
  end
end
