defmodule OfficeGraph.WorkPackets.Changes.DeriveVersionLifecycleState do
  @moduledoc false

  use Ash.Resource.Change

  alias OfficeGraph.WorkPackets.Readiness

  @impl true
  def change(changeset, _opts, _context) do
    lifecycle_state =
      changeset
      |> readiness_attrs()
      |> Readiness.lifecycle_state()

    Ash.Changeset.force_change_attribute(changeset, :lifecycle_state, lifecycle_state)
  end

  defp readiness_attrs(changeset) do
    %{
      objective: Ash.Changeset.get_attribute(changeset, :objective),
      context_summary: Ash.Changeset.get_attribute(changeset, :context_summary),
      requirements: Ash.Changeset.get_attribute(changeset, :requirements),
      success_criteria: Ash.Changeset.get_attribute(changeset, :success_criteria),
      autonomy_posture: Ash.Changeset.get_attribute(changeset, :autonomy_posture),
      source_graph_item_ids: Ash.Changeset.get_argument(changeset, :source_graph_item_ids) || [],
      verification_check_ids: Ash.Changeset.get_argument(changeset, :verification_check_ids) || []
    }
  end
end
