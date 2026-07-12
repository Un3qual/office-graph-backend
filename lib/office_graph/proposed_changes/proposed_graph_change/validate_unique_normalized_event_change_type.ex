defmodule OfficeGraph.ProposedChanges.ProposedGraphChange.ValidateUniqueNormalizedEventChangeType do
  @moduledoc false

  use Ash.Resource.Change

  alias OfficeGraph.ProposedChanges.ProposedGraphChange

  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    normalized_event_id = Ash.Changeset.get_attribute(changeset, :normalized_event_id)
    change_type = Ash.Changeset.get_attribute(changeset, :change_type)

    if is_nil(normalized_event_id) or is_nil(change_type) do
      changeset
    else
      validate_unique_event_change_type(changeset, normalized_event_id, change_type)
    end
  end

  defp validate_unique_event_change_type(changeset, normalized_event_id, change_type) do
    ProposedGraphChange
    |> Ash.Query.filter(
      normalized_event_id == ^normalized_event_id and change_type == ^change_type
    )
    |> Ash.exists?(authorize?: false)
    |> case do
      true ->
        changeset
        |> Ash.Changeset.add_error(
          field: :normalized_event_id,
          message: "normalized_event_id and change_type must be unique"
        )
        |> Ash.Changeset.add_error(
          field: :change_type,
          message: "normalized_event_id and change_type must be unique"
        )

      false ->
        changeset
    end
  end
end
