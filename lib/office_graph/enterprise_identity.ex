defmodule OfficeGraph.EnterpriseIdentity do
  @moduledoc """
  Provider-neutral enterprise connections, directories, and synchronized identity facts.
  """

  use Boundary,
    deps: [
      OfficeGraph.Authorization,
      OfficeGraph.CommandSupport,
      OfficeGraph.Identity,
      OfficeGraph.Integrations,
      OfficeGraph.Operations,
      OfficeGraph.Tenancy
    ],
    exports: [Domain]

  alias OfficeGraph.EnterpriseIdentity.{
    ActionSupport,
    Directory,
    DirectoryApplyResult,
    DirectoryProcessingResult,
    DirectorySyncEvent
  }

  alias OfficeGraph.EnterpriseIdentity.Adapters.WorkOS.DirectoryEvent
  alias OfficeGraph.EnterpriseIdentity.WebhookReceipt

  @storage_exceptions [
    Ash.Error.Forbidden,
    Ash.Error.Framework,
    Ash.Error.Invalid,
    Ash.Error.Unknown,
    DBConnection.ConnectionError,
    Ecto.ConstraintError,
    Ecto.StaleEntryError,
    Postgrex.Error
  ]

  def apply_directory_event(directory_id, %DirectoryEvent{} = event, operation_id)
      when is_binary(directory_id) and is_binary(operation_id) do
    Directory
    |> Ash.ActionInput.for_action(:apply_event, %{
      directory_id: directory_id,
      event: event,
      operation_id: operation_id
    })
    |> Ash.run_action(authorize?: false)
    |> ActionSupport.normalize_action_result()
    |> case do
      {:ok, %DirectoryApplyResult{} = result} -> DirectoryApplyResult.to_public_result(result)
      {:error, reason} when is_atom(reason) -> {:error, reason}
      {:error, _storage_error} -> {:error, :enterprise_identity_storage_unavailable}
    end
  rescue
    _error in @storage_exceptions -> {:error, :enterprise_identity_storage_unavailable}
  end

  def apply_directory_event(_directory_id, _event, _operation_id),
    do: {:error, :invalid_directory_event}

  def accept_webhook(headers, raw_body), do: WebhookReceipt.accept(headers, raw_body)

  def process_sync_event(sync_event_id, provider_event_id)
      when is_binary(sync_event_id) and is_binary(provider_event_id) do
    DirectorySyncEvent
    |> Ash.ActionInput.for_action(:process_event, %{
      sync_event_id: sync_event_id,
      provider_event_id: provider_event_id
    })
    |> Ash.run_action(authorize?: false)
    |> ActionSupport.normalize_action_result()
    |> case do
      {:ok, %DirectoryProcessingResult{}} -> :ok
      {:error, reason} when is_atom(reason) -> {:error, reason}
      {:error, _storage_error} -> {:error, :enterprise_identity_storage_unavailable}
    end
  rescue
    _error in @storage_exceptions -> {:error, :enterprise_identity_storage_unavailable}
  end

  def process_sync_event(_sync_event_id, _provider_event_id),
    do: {:error, :unknown_sync_event}

  def fail_sync_event(sync_event_id, reason) when is_binary(sync_event_id) do
    with {:ok, %DirectorySyncEvent{} = sync_event} <-
           Ash.get(DirectorySyncEvent, sync_event_id,
             authorize?: false,
             not_found_error?: false
           ),
         {:ok, _failed} <-
           sync_event
           |> Ash.Changeset.for_update(:mark_processed, %{
             status: "failed",
             result: bounded_sync_result(reason),
             processed_at: DateTime.utc_now()
           })
           |> Ash.update(authorize?: false) do
      :ok
    else
      {:ok, nil} -> {:error, :unknown_sync_event}
      {:error, _storage_error} -> {:error, :enterprise_identity_storage_unavailable}
    end
  end

  def fail_sync_event(_sync_event_id, _reason), do: {:error, :unknown_sync_event}

  defp bounded_sync_result(reason) when is_atom(reason),
    do: reason |> Atom.to_string() |> String.slice(0, 255)

  defp bounded_sync_result(_reason), do: "directory_sync_failed"
end
