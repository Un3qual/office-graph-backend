defmodule OfficeGraph.ProposedChanges.PersistenceTestAdapter do
  @moduledoc false

  @behaviour OfficeGraph.ProposedChanges.Persistence

  alias OfficeGraphTest.PersistenceFailureResponses

  def configure!(responses),
    do: PersistenceFailureResponses.configure!(:proposed_changes, responses)

  def clear!, do: PersistenceFailureResponses.clear!(:proposed_changes)

  @impl true
  def before_write(stage, context) do
    case PersistenceFailureResponses.fetch(:proposed_changes, stage) do
      callback when is_function(callback, 1) -> callback.(context)
      response -> response
    end
  end
end
