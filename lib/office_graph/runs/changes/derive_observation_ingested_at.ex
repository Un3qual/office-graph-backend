defmodule OfficeGraph.Runs.Changes.DeriveObservationIngestedAt do
  @moduledoc false

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.force_change_attribute(changeset, :ingested_at, DateTime.utc_now())
  end
end
