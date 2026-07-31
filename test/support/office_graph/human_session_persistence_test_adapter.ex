defmodule OfficeGraph.Identity.HumanSessionPersistenceTestAdapter do
  @moduledoc false

  @behaviour OfficeGraph.Identity.HumanSessionPersistence

  alias OfficeGraphTest.PersistenceFailureResponses

  def configure!(responses),
    do: PersistenceFailureResponses.configure!(:human_sessions, responses)

  @impl true
  def before_access(stage), do: PersistenceFailureResponses.fetch(:human_sessions, stage)
end
