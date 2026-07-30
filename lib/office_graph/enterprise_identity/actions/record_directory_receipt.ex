defmodule OfficeGraph.EnterpriseIdentity.Actions.RecordDirectoryReceipt do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.{Integrations, Operations}

  alias OfficeGraph.EnterpriseIdentity.{
    ActionSupport,
    Directory,
    DirectoryReceiptResult,
    DirectorySyncEvent,
    Workers.DirectorySyncWorker
  }

  alias OfficeGraph.EnterpriseIdentity.Adapters.WorkOS.DirectoryEvent

  require Ash.Query

  @impl true
  def run(input, _opts, _context) do
    event = input.arguments.event
    raw_body = input.arguments.raw_body

    case persist(event, raw_body) do
      {:ok, result} -> {:ok, result}
      {:error, error} -> ActionSupport.rollback(DirectorySyncEvent, error)
    end
  end

  defp persist(event, raw_body) do
    with {:ok, directory} <- locked_directory(event.directory_id),
         {:ok, request} <- operation_request(directory, event),
         {:ok, operation} <- Operations.start_system_operation(request),
         {:ok, source} <-
           Integrations.ensure_provider_source(
             "workos_directory:#{directory.provider_directory_id}",
             "WorkOS directory #{directory.provider_directory_id}"
           ),
         {:ok, archive, archive_status} <-
           archive(operation, source, event, raw_body),
         {:ok, result} <-
           record_sync_event(
             archive_status,
             archive,
             operation,
             directory,
             event,
             raw_body
           ) do
      {:ok, result}
    else
      {:error, {:system_idempotency_conflict, _operation_id}} -> {:error, :event_conflict}
      {:error, :delivery_identity_conflict} -> {:error, :event_conflict}
      {:error, _reason} = error -> error
    end
  end

  defp locked_directory(provider_directory_id) do
    Directory
    |> Ash.Query.filter(provider_directory_id == ^provider_directory_id and status == "active")
    |> Ash.Query.load(:connection)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %Directory{connection: %{status: "active"}} = directory} -> {:ok, directory}
      {:ok, _missing_or_inactive} -> {:error, :unknown_directory}
      {:error, _reason} = error -> error
    end
  end

  defp operation_request(directory, event) do
    connection = directory.connection

    Operations.new_system_operation_request(%{
      organization_id: connection.organization_id,
      workspace_id: connection.workspace_id,
      principal_id: connection.webhook_principal_id,
      action: :provider_webhook_receive,
      authority_basis: "workos_connection:#{connection.id}",
      causation_key: "workos_directory_event:#{event.provider_event_id}",
      idempotency_scope: "workos:directory_delivery",
      idempotency_key: event.provider_event_id
    })
  end

  defp archive(operation, source, event, raw_body) do
    Integrations.archive_system_delivery(operation, source, %{
      external_delivery_id: event.provider_event_id,
      body: raw_body,
      provider_event: event.event_type
    })
  end

  defp record_sync_event(
         archive_status,
         archive,
         operation,
         directory,
         event,
         raw_body
       ) do
    with {:ok, existing} <- locked_sync_event(event.provider_event_id) do
      case {existing, archive_status} do
        {nil, :created} ->
          create_and_enqueue(archive, operation, directory, event, raw_body)

        {%DirectorySyncEvent{} = existing, _archive_status} ->
          replay(existing, archive, operation, directory, event, raw_body)

        {nil, _archive_status} ->
          {:error, :event_conflict}
      end
    end
  end

  defp create_and_enqueue(archive, operation, directory, event, raw_body) do
    attrs =
      sync_event_attrs(archive, operation, directory, event, raw_body)
      |> Map.put(:status, "pending")

    with {:ok, sync_event} <-
           DirectorySyncEvent
           |> Ash.Changeset.for_create(:create, attrs)
           |> Ash.create(authorize?: false, return_notifications?: true)
           |> consume_notifications(),
         {:ok, _job} <- enqueue(sync_event) do
      DirectoryReceiptResult.created(sync_event)
    end
  end

  defp replay(existing, archive, operation, directory, event, raw_body) do
    expected = sync_event_attrs(archive, operation, directory, event, raw_body)

    if existing.content_hash == expected.content_hash and
         existing.connection_id == expected.connection_id and
         existing.directory_id == expected.directory_id and
         existing.raw_archive_id == expected.raw_archive_id and
         existing.operation_id == expected.operation_id and
         existing.event_type == expected.event_type do
      DirectoryReceiptResult.replayed(existing)
    else
      {:error, :event_conflict}
    end
  end

  defp sync_event_attrs(archive, operation, directory, event, raw_body) do
    %{
      connection_id: directory.connection_id,
      directory_id: directory.id,
      raw_archive_id: archive.id,
      operation_id: operation.id,
      provider_event_id: event.provider_event_id,
      event_type: event.event_type,
      content_hash: DirectoryEvent.content_hash(raw_body),
      provider_occurred_at: event.provider_occurred_at
    }
  end

  defp locked_sync_event(provider_event_id) do
    DirectorySyncEvent
    |> Ash.Query.filter(provider_event_id == ^provider_event_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
  end

  defp enqueue(sync_event) do
    %{
      "sync_event_id" => sync_event.id,
      "provider_event_id" => sync_event.provider_event_id
    }
    |> DirectorySyncWorker.new()
    |> Oban.insert()
  end

  defp consume_notifications({:ok, record, _notifications}), do: {:ok, record}
  defp consume_notifications({:error, error}), do: {:error, error}
end
