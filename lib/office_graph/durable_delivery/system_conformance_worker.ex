defmodule OfficeGraph.DurableDelivery.SystemConformanceWorker do
  @moduledoc """
  Provider-neutral conformance worker for organization-scoped system delivery.
  """

  use Oban.Worker,
    queue: :delivery,
    max_attempts: 3,
    unique: [period: :infinity, fields: [:worker, :queue, :args], states: :all]

  alias OfficeGraph.{DurableDelivery, Operations}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
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
             event_key: event_key(operation, args["idempotency_key"]),
             event_kind: "system_conformance.completed"
           }) do
      :ok
    else
      {:error, :forbidden} -> {:cancel, "system_conformance_forbidden"}
      {:error, _error} -> {:cancel, "invalid_system_conformance_job"}
    end
  end

  defp event_key(operation, idempotency_key) do
    "system-conformance:#{operation.organization_id}:#{operation.principal_id}:#{idempotency_key}"
  end
end
