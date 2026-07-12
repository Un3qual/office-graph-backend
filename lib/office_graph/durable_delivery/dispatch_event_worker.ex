defmodule OfficeGraph.DurableDelivery.DispatchEventWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :delivery,
    max_attempts: 5,
    unique: [period: :infinity, fields: [:worker, :queue, :args], states: :all]

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
      when is_binary(event_id) and is_binary(organization_id) and is_binary(workspace_id) do
    scope = %{organization_id: organization_id, workspace_id: workspace_id}

    result =
      event_id
      |> OfficeGraph.DurableDelivery.dispatch(scope)
      |> OfficeGraph.DurableDelivery.WorkerResult.normalize(job)

    case result do
      {:cancel, failure_code} = cancelled ->
        OfficeGraph.DurableDelivery.mark_failed(event_id, scope, failure_code)
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
