defmodule OfficeGraph.GitHubIntegration.OutboundPersistenceTestAdapter do
  @moduledoc false

  @behaviour OfficeGraph.GitHubIntegration.OutboundPersistence

  alias OfficeGraphTest.PersistenceFailureResponses

  def configure!(responses), do: PersistenceFailureResponses.configure!(:github_outbound, responses)
  def clear_outbound_failures!, do: PersistenceFailureResponses.clear!(:github_outbound)

  @impl true
  def before_write(stage), do: PersistenceFailureResponses.fetch(:github_outbound, stage)
end
