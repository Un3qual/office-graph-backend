defmodule OfficeGraph.Runs.Changes.DeriveRunInitialLifecycle do
  @moduledoc false

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.force_change_attributes(changeset, %{
      state: "running",
      aggregate_state: "running",
      execution_state: "pending",
      verification_state: "unverified",
      started_at: DateTime.utc_now(),
      completed_at: nil
    })
  end
end
