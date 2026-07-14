defmodule OfficeGraph.GitHubIntegration.WebhookReceipt do
  @moduledoc false

  require Ash.Query

  alias OfficeGraph.{DurableDelivery, Integrations, Operations, Repo}

  alias OfficeGraph.GitHubIntegration.{
    Installation,
    InstallationCredential,
    SecretStore,
    WebhookSignature,
    WebhookWorker
  }

  @supported_events MapSet.new(~w(
    check_run
    pull_request
    pull_request_review
    pull_request_review_comment
  ))

  @header_pattern ~r/^[A-Za-z0-9._:=+-]+$/

  def accept(headers, raw_body) when is_map(headers) and is_binary(raw_body) do
    with {:ok, delivery_id} <- required_header(headers, "x-github-delivery"),
         {:ok, event_name} <- required_header(headers, "x-github-event"),
         {:ok, signature} <- required_header(headers, "x-hub-signature-256"),
         {:ok, external_installation_id} <- installation_identity(raw_body),
         {:ok, installation} <- active_installation(external_installation_id),
         {:ok, credential_binding} <- webhook_credential(installation.id),
         {:ok, secret} <-
           SecretStore.resolve(credential_binding.credential_id, %{
             organization_id: installation.organization_id,
             workspace_id: installation.workspace_id
           }),
         :ok <- WebhookSignature.verify(raw_body, signature, secret),
         :ok <- supported_event(event_name) do
      record_receipt(installation, credential_binding, delivery_id, event_name, raw_body)
    else
      {:error, reason}
      when reason in [
             :forbidden,
             :invalid_secret_reference,
             :secret_not_found,
             :unavailable,
             :unknown_installation
           ] ->
        {:error, :invalid_signature}

      error ->
        error
    end
  end

  def accept(_headers, _raw_body), do: {:error, :invalid_delivery}

  defp record_receipt(installation, credential_binding, delivery_id, event_name, raw_body) do
    case Repo.transaction(fn ->
           with {:ok, request} <-
                  Operations.new_system_operation_request(%{
                    organization_id: installation.organization_id,
                    workspace_id: installation.workspace_id,
                    principal_id: installation.webhook_principal_id,
                    action: :provider_webhook_receive,
                    authority_basis: "github_installation:#{installation.id}",
                    causation_key: "github_delivery:#{delivery_id}",
                    idempotency_scope: "github:delivery",
                    idempotency_key: delivery_id,
                    credential_id: credential_binding.credential_id
                  }),
                {:ok, operation} <- Operations.start_system_operation(request),
                {:ok, source} <-
                  Integrations.ensure_provider_source(
                    "github_app:#{installation.app_slug}",
                    "GitHub App #{installation.app_slug}"
                  ),
                {:ok, archive, archive_state} <-
                  Integrations.archive_system_delivery(operation, source, %{
                    external_delivery_id: delivery_id,
                    body: raw_body,
                    metadata: %{
                      "event" => event_name,
                      "installation_id" => installation.external_installation_id
                    }
                  }),
                {:ok, event} <-
                  DurableDelivery.record_system_and_enqueue(operation, %{
                    event_key: "github-delivery:#{delivery_id}",
                    event_kind: "provider_delivery.received"
                  }),
                {:ok, _job} <-
                  enqueue_webhook(
                    installation,
                    delivery_id,
                    event_name,
                    archive.id,
                    event.id
                  ) do
             archive_state
           else
             {:error, reason} -> Repo.rollback(reason)
           end
         end) do
      {:ok, :created} -> {:ok, :accepted}
      {:ok, :replayed} -> {:ok, :duplicate}
      {:error, reason} -> {:error, normalize_receipt_error(reason)}
    end
  end

  defp enqueue_webhook(installation, delivery_id, event_name, archive_id, event_id) do
    %{
      "delivery_id" => delivery_id,
      "event_name" => event_name,
      "installation_id" => installation.id,
      "archive_id" => archive_id,
      "event_id" => event_id,
      "organization_id" => installation.organization_id,
      "workspace_id" => installation.workspace_id
    }
    |> WebhookWorker.new()
    |> Oban.insert()
  end

  defp active_installation(external_installation_id) do
    Installation
    |> Ash.Query.filter(
      external_installation_id == ^external_installation_id and lifecycle_state == "active"
    )
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, :unknown_installation}
      {:ok, installation} -> {:ok, installation}
      {:error, _error} -> {:error, :unknown_installation}
    end
  end

  defp webhook_credential(installation_id) do
    InstallationCredential
    |> Ash.Query.filter(installation_id == ^installation_id and purpose == "webhook_secret")
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, :unknown_installation}
      {:ok, binding} -> {:ok, binding}
      {:error, _error} -> {:error, :unknown_installation}
    end
  end

  defp installation_identity(raw_body) do
    with {:ok, payload} <- Jason.decode(raw_body),
         installation when is_map(installation) <- Map.get(payload, "installation"),
         {:ok, installation_id} <- positive_integer(Map.get(installation, "id")) do
      {:ok, installation_id}
    else
      _error -> {:error, :invalid_delivery}
    end
  end

  defp positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> {:ok, integer}
      _other -> {:error, :invalid_delivery}
    end
  end

  defp positive_integer(_value), do: {:error, :invalid_delivery}

  defp required_header(headers, name) do
    case Map.get(headers, name) || Map.get(headers, String.to_atom(name)) do
      value when is_binary(value) and byte_size(value) in 1..255 ->
        if Regex.match?(@header_pattern, value),
          do: {:ok, value},
          else: {:error, :invalid_delivery}

      _other ->
        {:error, :invalid_delivery}
    end
  end

  defp supported_event(event_name) do
    if MapSet.member?(@supported_events, event_name),
      do: :ok,
      else: {:error, :unsupported_event}
  end

  defp normalize_receipt_error({:system_idempotency_conflict, _operation_id}),
    do: :delivery_identity_conflict

  defp normalize_receipt_error(reason)
       when reason in [
              :delivery_identity_conflict,
              :invalid_delivery,
              :unknown_installation,
              :unsupported_event
            ],
       do: reason

  defp normalize_receipt_error(_reason), do: :receipt_failed
end
