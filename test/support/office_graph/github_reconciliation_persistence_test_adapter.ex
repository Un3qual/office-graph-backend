defmodule OfficeGraph.GitHubIntegration.ReconciliationPersistenceTestAdapter do
  @moduledoc false

  @behaviour OfficeGraph.GitHubIntegration.ReconciliationPersistence

  alias OfficeGraphTest.PersistenceFailureResponses

  def configure!(responses),
    do: PersistenceFailureResponses.configure!(:github_reconciliation, responses)

  def clear_reconciliation_failures!,
    do: PersistenceFailureResponses.clear!(:github_reconciliation)

  @impl true
  def before_write(stage), do: PersistenceFailureResponses.fetch(:github_reconciliation, stage)
end
