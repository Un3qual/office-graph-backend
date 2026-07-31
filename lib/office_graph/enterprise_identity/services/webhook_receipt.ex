defmodule OfficeGraph.EnterpriseIdentity.WebhookReceipt do
  @moduledoc false

  alias OfficeGraph.EnterpriseIdentity.{
    ActionSupport,
    Adapters.WorkOS.DirectoryEvent,
    Adapters.WorkOS.WebhookSignature,
    DirectoryReceiptResult,
    DirectorySyncEvent,
    SecretStore
  }

  @signature_header "workos-signature"

  def accept(headers, raw_body) when is_map(headers) and is_binary(raw_body) do
    with {:ok, secret_reference} <- webhook_secret_reference(),
         {:ok, secret} <- SecretStore.resolve(secret_reference),
         {:ok, signature} <- required_signature(headers),
         :ok <- WebhookSignature.verify(raw_body, signature, secret),
         {:ok, event} <- DirectoryEvent.normalize(raw_body),
         {:ok, %DirectoryReceiptResult{} = result} <-
           record(event, raw_body) do
      case result.status do
        :created -> {:ok, :accepted}
        :replayed -> {:ok, :duplicate}
      end
    else
      {:error, reason}
      when reason in [
             :invalid_signature,
             :invalid_delivery,
             :unsupported_event,
             :unknown_directory,
             :event_conflict
           ] ->
        {:error, reason}

      {:error, _configuration_or_storage_error} ->
        {:error, :receipt_unavailable}
    end
  end

  def accept(_headers, _raw_body), do: {:error, :invalid_delivery}

  defp record(event, raw_body) do
    DirectorySyncEvent
    |> Ash.ActionInput.for_action(:record_receipt, %{event: event, raw_body: raw_body})
    |> Ash.run_action(authorize?: false)
    |> ActionSupport.normalize_action_result()
    |> case do
      {:ok, %DirectoryReceiptResult{} = result} -> {:ok, result}
      {:error, reason} when is_atom(reason) -> {:error, reason}
      {:error, _storage_error} -> {:error, :receipt_unavailable}
    end
  end

  defp webhook_secret_reference do
    case Application.get_env(:office_graph, :workos_enterprise, [])[
           :webhook_secret_reference
         ] do
      reference when is_binary(reference) and reference != "" -> {:ok, reference}
      _missing -> {:error, :workos_unavailable}
    end
  end

  defp required_signature(headers) do
    case Map.get(headers, @signature_header) || Map.get(headers, :"workos-signature") do
      value when is_binary(value) and byte_size(value) in 1..2_048 -> {:ok, value}
      _missing_or_invalid -> {:error, :invalid_signature}
    end
  end
end
