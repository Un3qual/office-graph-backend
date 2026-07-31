defmodule OfficeGraph.EnterpriseIdentity.Actions.ProcessDirectorySyncEvent do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.Integrations

  alias OfficeGraph.EnterpriseIdentity.{
    Adapters.WorkOS.DirectoryEvent,
    ActionSupport,
    Directory,
    DirectoryApplyResult,
    DirectoryProcessingResult,
    DirectorySyncEvent
  }

  require Ash.Query

  @impl true
  def run(input, _opts, _context) do
    result =
      with {:ok, sync_event} <-
             locked_sync_event(
               input.arguments.sync_event_id,
               input.arguments.provider_event_id
             ) do
        process(sync_event)
      end

    case result do
      {:ok, _result} = success -> success
      {:error, error} -> ActionSupport.rollback(DirectorySyncEvent, error)
    end
  end

  defp process(%DirectorySyncEvent{status: "pending"} = sync_event) do
    connection = sync_event.connection

    with {:ok, archive} <-
           Integrations.provider_delivery_archive(
             connection.organization_id,
             connection.workspace_id,
             sync_event.raw_archive_id,
             sync_event.provider_event_id
           ),
         {:ok, event} <- DirectoryEvent.normalize(archive.body),
         :ok <- validate_archived_event(sync_event, event, archive.body),
         {:ok, %DirectoryApplyResult{} = apply_result} <-
           apply_event(sync_event, event),
         {:ok, _processed} <- mark_processed(sync_event, apply_result.status) do
      DirectoryProcessingResult.completed(apply_result.status)
    end
  end

  defp process(%DirectorySyncEvent{}),
    do: DirectoryProcessingResult.completed(:already_processed)

  defp locked_sync_event(sync_event_id, provider_event_id) do
    DirectorySyncEvent
    |> Ash.Query.filter(id == ^sync_event_id and provider_event_id == ^provider_event_id)
    |> Ash.Query.load([:connection, :directory])
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %DirectorySyncEvent{} = sync_event} -> {:ok, sync_event}
      {:ok, nil} -> {:error, :unknown_sync_event}
      {:error, _reason} = error -> error
    end
  end

  defp validate_archived_event(sync_event, event, raw_body) do
    valid? =
      event.provider_event_id == sync_event.provider_event_id and
        event.event_type == sync_event.event_type and
        event.directory_id == sync_event.directory.provider_directory_id and
        DirectoryEvent.content_hash(raw_body) == sync_event.content_hash

    if valid?, do: :ok, else: {:error, :event_conflict}
  end

  defp apply_event(sync_event, event) do
    Directory
    |> Ash.ActionInput.for_action(:apply_event, %{
      directory_id: sync_event.directory_id,
      event: event,
      operation_id: sync_event.operation_id,
      provider_received_at: sync_event.inserted_at
    })
    |> Ash.run_action(authorize?: false)
  end

  defp mark_processed(sync_event, status) do
    status = Atom.to_string(status)

    sync_event
    |> Ash.Changeset.for_update(:mark_processed, %{
      status: status,
      result: status,
      processed_at: DateTime.utc_now()
    })
    |> Ash.update(authorize?: false)
  end
end
