defmodule OfficeGraph.AgentRuntime.Changes.SyncBindingDisabledAt do
  @moduledoc false

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :lifecycle_state) do
      "active" -> Ash.Changeset.force_change_attribute(changeset, :disabled_at, nil)
      state when state in ~w(disabled revoked) -> set_disabled_at(changeset)
      _other -> changeset
    end
  end

  defp set_disabled_at(changeset) do
    disabled_at = Ash.Changeset.get_attribute(changeset, :disabled_at) || DateTime.utc_now()
    Ash.Changeset.force_change_attribute(changeset, :disabled_at, disabled_at)
  end
end
