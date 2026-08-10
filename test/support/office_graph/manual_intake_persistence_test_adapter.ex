defmodule OfficeGraph.Integrations.ManualIntakePersistenceTestAdapter do
  @moduledoc false

  @behaviour OfficeGraph.Integrations.ManualIntakePersistence

  alias OfficeGraphTest.PersistenceFailureResponses

  def configure!(responses), do: PersistenceFailureResponses.configure!(:manual_intake, responses)

  @impl true
  def before_write(stage, attrs) do
    case PersistenceFailureResponses.fetch(:manual_intake, stage) do
      callback when is_function(callback, 1) -> callback.(attrs)
      response -> response
    end
  end
end
