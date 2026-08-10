defmodule OfficeGraph.Operations.PersistenceTestAdapter do
  @moduledoc false

  @behaviour OfficeGraph.Operations.Persistence

  alias OfficeGraphTest.PersistenceFailureResponses

  def configure!(responses), do: PersistenceFailureResponses.configure!(:operations, responses)
  def clear_operation_failures!, do: PersistenceFailureResponses.clear!(:operations)

  @impl true
  def before_write(stage), do: PersistenceFailureResponses.fetch(:operations, stage)
end
