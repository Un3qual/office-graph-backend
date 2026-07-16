defmodule OfficeGraph.DurableDelivery.SystemConformanceWorker do
  @moduledoc """
  Provider-neutral conformance worker for organization-scoped system delivery.
  """

  use Oban.Worker,
    queue: :delivery,
    max_attempts: 3,
    unique: [period: :infinity, fields: [:worker, :queue, :args], states: :all]

  @terminal_retry_delay_seconds 5

  alias OfficeGraph.{DurableDelivery, Operations}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    attrs = %{
      organization_id: args["organization_id"],
      workspace_id: args["workspace_id"],
      principal_id: args["principal_id"],
      action: :system_conformance,
      authority_basis: args["authority_basis"],
      causation_key: args["causation_key"],
      idempotency_scope: "durable-delivery:conformance",
      idempotency_key: args["idempotency_key"]
    }

    with {:ok, request} <- Operations.new_system_operation_request(attrs),
         {:ok, operation} <- Operations.start_system_operation(request),
         {:ok, _event} <-
           DurableDelivery.record_system_and_enqueue(operation, %{
             event_key: event_key(operation),
             event_kind: "system_conformance.completed"
           }) do
      :ok
    else
      {:error, :forbidden} -> finish_terminal_job(job, "system_conformance_forbidden")
      {:error, error} when is_struct(error) -> {:error, "system_conformance_storage_unavailable"}
      {:error, _error} -> finish_terminal_job(job, "invalid_system_conformance_job")
    end
  end

  defp finish_terminal_job(job, failure_code) do
    case DurableDelivery.stage_terminal_failure(job, failure_code) do
      :ok -> {:cancel, failure_code}
      {:error, _error} -> {:snooze, @terminal_retry_delay_seconds}
    end
  end

  defp event_key(operation), do: "system-conformance:#{operation.id}"
end
