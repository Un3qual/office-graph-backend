defmodule OfficeGraph.DurableDelivery.DispatchEventWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :delivery,
    max_attempts: 5,
    unique: [period: :infinity, fields: [:worker, :queue, :args], states: :all]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event_id" => event_id}} = job) when is_binary(event_id) do
    result =
      event_id
      |> OfficeGraph.DurableDelivery.dispatch()
      |> OfficeGraph.DurableDelivery.WorkerResult.normalize(job)

    case result do
      {:cancel, failure_code} = cancelled ->
        OfficeGraph.DurableDelivery.mark_failed(event_id, failure_code)
        cancelled

      other ->
        other
    end
  end

  def perform(job),
    do:
      OfficeGraph.DurableDelivery.WorkerResult.normalize(
        {:error, {:terminal, :invalid_job_args}},
        job
      )
end
