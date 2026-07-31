defmodule OfficeGraph.DurableDelivery.DispatchEventWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :delivery,
    max_attempts: 5,
    unique: [period: :infinity, fields: [:worker, :queue, :args], states: :all]

  @terminal_retry_delay_seconds 5

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(30)

  @impl Oban.Worker
  def perform(job), do: perform(job, OfficeGraph.DurableDelivery)

  @doc false
  def perform(
        %Oban.Job{
          args: %{
            "event_id" => event_id,
            "organization_id" => organization_id,
            "workspace_id" => workspace_id
          },
          meta: %{"terminal_failure_code" => failure_code}
        },
        delivery
      )
      when is_binary(event_id) and is_binary(organization_id) and
             (is_binary(workspace_id) or is_nil(workspace_id)) and is_atom(delivery) do
    scope = %{organization_id: organization_id, workspace_id: workspace_id}

    failure_code =
      OfficeGraph.DurableDelivery.WorkerResult.safe_code(failure_code, "delivery_failed")

    persist_terminal_failure(event_id, scope, failure_code, delivery)
  end

  def perform(
        %Oban.Job{
          args: %{
            "event_id" => event_id,
            "organization_id" => organization_id,
            "workspace_id" => workspace_id
          }
        } = job,
        delivery
      )
      when is_binary(event_id) and is_binary(organization_id) and
             (is_binary(workspace_id) or is_nil(workspace_id)) and is_atom(delivery) do
    scope = %{organization_id: organization_id, workspace_id: workspace_id}

    result =
      event_id
      |> delivery.dispatch(scope)
      |> OfficeGraph.DurableDelivery.WorkerResult.normalize(job)

    case result do
      {:cancel, failure_code} ->
        stage_and_persist_terminal_failure(
          job,
          event_id,
          scope,
          failure_code,
          delivery
        )

      other ->
        other
    end
  end

  def perform(job, delivery) when is_atom(delivery) do
    {:cancel, failure_code} =
      OfficeGraph.DurableDelivery.WorkerResult.normalize(
        {:error, {:terminal, :invalid_job_args}},
        job
      )

    case delivery.stage_terminal_failure(job, failure_code) do
      :ok -> {:cancel, failure_code}
      {:error, _error} -> retry_terminal_failure_staging()
    end
  end

  defp stage_and_persist_terminal_failure(
         job,
         event_id,
         scope,
         failure_code,
         delivery
       ) do
    case delivery.stage_terminal_failure(job, failure_code) do
      :ok -> persist_terminal_failure(event_id, scope, failure_code, delivery)
      {:error, _error} -> retry_terminal_failure_staging()
    end
  end

  defp retry_terminal_failure_staging, do: {:snooze, @terminal_retry_delay_seconds}

  defp persist_terminal_failure(event_id, scope, failure_code, delivery) do
    case delivery.mark_failed(event_id, scope, failure_code) do
      :ok -> {:cancel, failure_code}
      {:error, {:retryable, _code}} -> {:snooze, @terminal_retry_delay_seconds}
    end
  end
end
