defmodule OfficeGraph.GitHubIntegration.WebhookWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :integrations,
    max_attempts: 10,
    unique: [period: :infinity, fields: [:worker, :queue, :args], states: :all]

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "delivery_id" => delivery_id,
          "installation_id" => installation_id,
          "archive_id" => archive_id,
          "event_id" => event_id
        }
      })
      when is_binary(delivery_id) and is_binary(installation_id) and is_binary(archive_id) and
             is_binary(event_id) do
    :ok
  end

  def perform(_job), do: {:cancel, "invalid_github_webhook_job"}
end
