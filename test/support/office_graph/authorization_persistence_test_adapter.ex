defmodule OfficeGraph.Authorization.PersistenceTestAdapter do
  @moduledoc false

  @behaviour OfficeGraph.Authorization.Persistence

  alias OfficeGraphTest.PersistenceFailureResponses

  def configure!(responses), do: PersistenceFailureResponses.configure!(:authorization, responses)
  def clear!, do: PersistenceFailureResponses.clear!(:authorization)

  @impl true
  def before_read(stage), do: PersistenceFailureResponses.fetch(:authorization, stage)
end
