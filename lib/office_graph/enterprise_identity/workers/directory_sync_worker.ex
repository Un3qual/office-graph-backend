defmodule OfficeGraph.EnterpriseIdentity.Workers.DirectorySyncWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :integrations,
    max_attempts: 10,
    unique: [period: :infinity, fields: [:worker, :queue, :args], states: :all]

  alias OfficeGraph.EnterpriseIdentity

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(30)

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "sync_event_id" => sync_event_id,
          "provider_event_id" => provider_event_id
        },
        attempt: attempt,
        max_attempts: max_attempts
      })
      when is_binary(sync_event_id) and is_binary(provider_event_id) do
    case EnterpriseIdentity.process_sync_event(sync_event_id, provider_event_id) do
      :ok ->
        :ok

      {:error, reason} when attempt >= max_attempts ->
        with :ok <- EnterpriseIdentity.fail_sync_event(sync_event_id, reason) do
          {:discard, bounded_reason(reason)}
        end

      {:error, _reason} = error ->
        error
    end
  end

  def perform(_job), do: {:cancel, "invalid_workos_directory_sync_job"}

  defp bounded_reason(reason)
       when reason in [
              :directory_dependency_missing,
              :enterprise_identity_storage_unavailable,
              :event_conflict,
              :integration_storage_unavailable,
              :unknown_directory,
              :unknown_sync_event
            ],
       do: Atom.to_string(reason)

  defp bounded_reason(_reason), do: "directory_sync_failed"
end
