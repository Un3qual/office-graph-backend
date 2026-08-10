defmodule OfficeGraph.GitHubIntegration.WebhookReceiptPersistenceTestAdapter do
  @moduledoc false

  @behaviour OfficeGraph.GitHubIntegration.WebhookReceiptPersistence

  alias OfficeGraphTest.PersistenceFailureResponses

  def configure!(responses),
    do: PersistenceFailureResponses.configure!(:github_webhook_receipt, responses)

  @impl true
  def before_write(stage), do: PersistenceFailureResponses.fetch(:github_webhook_receipt, stage)
end
