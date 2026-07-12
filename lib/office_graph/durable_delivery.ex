defmodule OfficeGraph.DurableDelivery do
  @moduledoc """
  Public boundary for durable domain events, jobs, and projection invalidation.
  """

  use Boundary,
    deps: [
      OfficeGraph.Authorization,
      OfficeGraph.Identity,
      OfficeGraph.Operations,
      OfficeGraph.Repo
    ],
    exports: [DomainEvent, ProjectionInvalidation, TerminalJob]

  alias OfficeGraph.DurableDelivery.{DispatchEventWorker, DomainEvent, EventRequest}
  alias OfficeGraph.Repo

  def record_and_enqueue(session_context, operation, attrs) do
    with {:ok, request} <- EventRequest.new(session_context, operation, attrs) do
      transaction(fn -> record_and_enqueue_request(request) end)
    end
  end

  def dispatch(_event_id), do: :ok

  defp record_and_enqueue_request(request) do
    with {:ok, event} <- create_or_replay_event(request),
         :ok <- validate_replay(event, request),
         {:ok, _job} <- enqueue(event) do
      event
    else
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp create_or_replay_event(request) do
    DomainEvent
    |> Ash.Changeset.for_create(:create, EventRequest.to_attrs(request))
    |> Ash.create(
      upsert?: true,
      upsert_identity: :event_key,
      upsert_fields: [],
      touch_update_defaults?: false,
      return_notifications?: true
    )
    |> case do
      {:ok, event, _notifications} -> {:ok, event}
      result -> result
    end
  end

  defp validate_replay(event, request) do
    matching? =
      Enum.all?(
        [
          :event_key,
          :event_kind,
          :subject_kind,
          :subject_id,
          :subject_version,
          :organization_id,
          :workspace_id,
          :operation_id,
          :causation_event_id
        ],
        &(Map.fetch!(event, &1) == Map.fetch!(request, &1))
      )

    if matching?, do: :ok, else: {:error, :event_identity_conflict}
  end

  defp enqueue(event) do
    %{
      "event_id" => event.id,
      "organization_id" => event.organization_id,
      "workspace_id" => event.workspace_id
    }
    |> DispatchEventWorker.new()
    |> Oban.insert()
  end

  defp transaction(fun) do
    if Repo.in_transaction?() do
      case fun.() do
        {:error, error} -> {:error, error}
        result -> {:ok, result}
      end
    else
      Repo.transaction(fun)
    end
  end
end
