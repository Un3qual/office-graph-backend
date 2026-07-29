defmodule OfficeGraph.GitHubIntegration.WebhookReceiptPersistence do
  @moduledoc false

  @callback before_write(atom()) :: :ok | {:error, term()}

  def before_write(stage) when is_atom(stage) do
    implementation().before_write(stage)
  end

  defp implementation do
    Application.fetch_env!(:office_graph, :github_webhook_receipt_persistence)
  end
end

defmodule OfficeGraph.GitHubIntegration.WebhookReceiptPersistence.Default do
  @moduledoc false

  @behaviour OfficeGraph.GitHubIntegration.WebhookReceiptPersistence

  @impl true
  def before_write(_stage), do: :ok
end
