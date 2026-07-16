defmodule OfficeGraph.DurableDelivery.DispatchEventWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :delivery,
    max_attempts: 5,
    unique: [period: :infinity, fields: [:worker, :queue, :args], states: :all]

  @terminal_retry_delay_seconds 5

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "event_id" => event_id,
          "organization_id" => organization_id,
          "workspace_id" => workspace_id
        },
        meta: %{"terminal_failure_code" => failure_code}
      })
      when is_binary(event_id) and is_binary(organization_id) and
             (is_binary(workspace_id) or is_nil(workspace_id)) do
    scope = %{organization_id: organization_id, workspace_id: workspace_id}

    failure_code =
      OfficeGraph.DurableDelivery.WorkerResult.safe_code(failure_code, "delivery_failed")

    persist_terminal_failure(event_id, scope, failure_code)
  end

  @impl Oban.Worker
  def perform(
        %Oban.Job{
          args: %{
            "event_id" => event_id,
            "organization_id" => organization_id,
            "workspace_id" => workspace_id
          }
        } = job
      )
      when is_binary(event_id) and is_binary(organization_id) and
             (is_binary(workspace_id) or is_nil(workspace_id)) do
    scope = %{organization_id: organization_id, workspace_id: workspace_id}

    result =
      event_id
      |> OfficeGraph.DurableDelivery.dispatch(scope)
      |> OfficeGraph.DurableDelivery.WorkerResult.normalize(job)

    case result do
      {:cancel, failure_code} ->
        stage_and_persist_terminal_failure(job, event_id, scope, failure_code)

      other ->
        other
    end
  end

  def perform(job) do
    {:cancel, failure_code} =
      OfficeGraph.DurableDelivery.WorkerResult.normalize(
        {:error, {:terminal, :invalid_job_args}},
        job
      )

    case OfficeGraph.DurableDelivery.stage_terminal_failure(job, failure_code) do
      :ok -> {:cancel, failure_code}
      {:error, _error} -> retry_terminal_failure_staging()
    end
  end

  defp stage_and_persist_terminal_failure(job, event_id, scope, failure_code) do
    case OfficeGraph.DurableDelivery.stage_terminal_failure(job, failure_code) do
      :ok -> persist_terminal_failure(event_id, scope, failure_code)
      {:error, _error} -> retry_terminal_failure_staging()
    end
  end

  defp retry_terminal_failure_staging, do: {:snooze, @terminal_retry_delay_seconds}

  defp persist_terminal_failure(event_id, scope, failure_code) do
    case OfficeGraph.DurableDelivery.mark_failed(event_id, scope, failure_code) do
      :ok -> {:cancel, failure_code}
      {:error, {:retryable, _code}} -> {:snooze, @terminal_retry_delay_seconds}
    end
  end
end
