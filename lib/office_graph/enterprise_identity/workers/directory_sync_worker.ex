defmodule OfficeGraph.EnterpriseIdentity.Workers.DirectorySyncWorker do
  @moduledoc false

  @terminal_retry_delay_seconds 5
  @terminal_reasons [
    :directory_dependency_missing,
    :enterprise_identity_storage_unavailable,
    :event_conflict,
    :integration_storage_unavailable,
    :unknown_directory,
    :unknown_sync_event,
    :directory_sync_failed
  ]
  @terminal_failure_reasons Map.new(@terminal_reasons, &{Atom.to_string(&1), &1})

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
        meta: %{"terminal_failure_code" => failure_code}
      })
      when is_binary(sync_event_id) and is_binary(provider_event_id) and
             is_binary(failure_code) do
    case Map.fetch(@terminal_failure_reasons, failure_code) do
      {:ok, reason} -> persist_terminal_failure(sync_event_id, reason, failure_code)
      :error -> {:cancel, "invalid_workos_directory_sync_terminalization"}
    end
  end

  @impl Oban.Worker
  def perform(
        %Oban.Job{
          args: %{
            "sync_event_id" => sync_event_id,
            "provider_event_id" => provider_event_id
          },
          attempt: attempt,
          max_attempts: max_attempts
        } = job
      )
      when is_binary(sync_event_id) and is_binary(provider_event_id) do
    case EnterpriseIdentity.process_sync_event(sync_event_id, provider_event_id) do
      :ok ->
        :ok

      {:error, reason} when attempt >= max_attempts ->
        failure_code = bounded_reason(reason)

        case stage_terminal_failure(job, failure_code) do
          :ok -> persist_terminal_failure(sync_event_id, reason, failure_code)
          {:error, _error} -> retry_terminal_failure()
        end

      {:error, _reason} = error ->
        error
    end
  end

  def perform(_job), do: {:cancel, "invalid_workos_directory_sync_job"}

  defp stage_terminal_failure(job, failure_code) do
    meta = Map.put(job.meta || %{}, "terminal_failure_code", failure_code)

    case Oban.update_job(job, %{meta: meta}) do
      {:ok, _updated_job} -> :ok
      {:error, error} -> {:error, error}
    end
  rescue
    error in [
      DBConnection.ConnectionError,
      Ecto.ConstraintError,
      Ecto.StaleEntryError,
      Postgrex.Error
    ] ->
      {:error, error}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp persist_terminal_failure(sync_event_id, reason, failure_code) do
    case EnterpriseIdentity.fail_sync_event(sync_event_id, reason) do
      :ok -> {:discard, failure_code}
      {:error, _error} -> retry_terminal_failure()
    end
  end

  defp retry_terminal_failure, do: {:snooze, @terminal_retry_delay_seconds}

  defp bounded_reason(reason) when reason in @terminal_reasons,
    do: Atom.to_string(reason)

  defp bounded_reason(_reason), do: "directory_sync_failed"
end
