defmodule OfficeGraph.GitHubIntegration.WebhookWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :integrations,
    max_attempts: 10,
    unique: [period: :infinity, fields: [:worker, :queue, :args], states: :all]

  alias OfficeGraph.{DurableDelivery, Integrations, Operations}

  alias OfficeGraph.GitHubIntegration.{
    Installation,
    InstallationCredential,
    Reconciler,
    ReconciliationRequest
  }

  require Ash.Query

  @impl Oban.Worker
  def perform(
        %Oban.Job{
          args: %{
            "delivery_id" => delivery_id,
            "installation_id" => installation_id,
            "archive_id" => archive_id,
            "event_id" => event_id,
            "organization_id" => organization_id,
            "workspace_id" => workspace_id
          }
        } = job
      )
      when is_binary(delivery_id) and is_binary(installation_id) and is_binary(archive_id) and
             is_binary(event_id) and is_binary(organization_id) and
             (is_binary(workspace_id) or is_nil(workspace_id)) do
    with {:ok, installation} <- load_installation(installation_id, organization_id, workspace_id),
         {:ok, archive} <- load_archive(archive_id, delivery_id, installation),
         {:ok, credential_id} <- private_key_credential(installation.id),
         {:ok, request} <- reconciliation_request(archive, installation, delivery_id),
         {:ok, operation_request} <-
           operation_request(installation, credential_id, request, event_id),
         {:ok, operation} <- Operations.start_system_operation(operation_request) do
      operation
      |> Reconciler.reconcile(request)
      |> normalize_result(job)
    else
      {:error, code} -> normalize_result({:error, {:terminal, safe_code(code)}}, job)
    end
  end

  def perform(_job), do: {:cancel, "invalid_github_webhook_job"}

  defp load_archive(archive_id, delivery_id, installation) do
    case Integrations.provider_delivery_archive(
           installation.organization_id,
           installation.workspace_id,
           archive_id,
           delivery_id
         ) do
      {:ok, %{metadata: %{"installation_id" => external_installation_id}} = archive}
      when external_installation_id == installation.external_installation_id ->
        {:ok, archive}

      _missing_or_mismatch ->
        {:error, :invalid_delivery_archive}
    end
  end

  defp load_installation(installation_id, organization_id, workspace_id) do
    case Ash.get(Installation, installation_id, authorize?: false, not_found_error?: false) do
      {:ok,
       %Installation{
         lifecycle_state: "active",
         organization_id: ^organization_id,
         workspace_id: ^workspace_id
       } = installation} ->
        {:ok, installation}

      _missing_or_cross_scope ->
        {:error, :installation_revoked}
    end
  end

  defp private_key_credential(installation_id) do
    InstallationCredential
    |> Ash.Query.filter(installation_id == ^installation_id and purpose == "app_private_key")
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %InstallationCredential{credential_id: credential_id}} -> {:ok, credential_id}
      _missing -> {:error, :invalid_credential}
    end
  end

  defp reconciliation_request(archive, installation, delivery_id) do
    event_name = Map.get(archive.metadata, "event")

    with {:ok, payload} <- Jason.decode(archive.body),
         {:ok, {object_type, object_id}} <- provider_object(event_name, payload) do
      ReconciliationRequest.new(%{
        installation_id: installation.id,
        object_type: object_type,
        object_id: object_id,
        delivery_id: delivery_id
      })
    else
      _invalid -> {:error, :invalid_delivery_payload}
    end
  end

  defp provider_object("pull_request", payload),
    do: nested_object(payload, "pull_request", "pull_request")

  defp provider_object("pull_request_review", payload),
    do: nested_object(payload, "pull_request", "pull_request")

  defp provider_object("pull_request_review_comment", payload),
    do: nested_object(payload, "comment", "review_comment")

  defp provider_object("check_run", payload),
    do: nested_object(payload, "check_run", "check_run")

  defp provider_object(_event_name, _payload), do: {:error, :unsupported_event}

  defp nested_object(payload, key, object_type) do
    case Map.get(payload, key) do
      %{"node_id" => node_id} when is_binary(node_id) and node_id != "" ->
        {:ok, {object_type, node_id}}

      %{"id" => id} when is_integer(id) and id > 0 ->
        {:ok, {object_type, Integer.to_string(id)}}

      _invalid ->
        {:error, :invalid_delivery_payload}
    end
  end

  defp operation_request(installation, credential_id, request, event_id) do
    Operations.new_system_operation_request(%{
      organization_id: installation.organization_id,
      workspace_id: installation.workspace_id,
      principal_id: installation.service_principal_id,
      action: :integration_reconcile,
      authority_basis: "github_installation:#{installation.id}",
      causation_key: "domain_event:#{event_id}",
      idempotency_scope: "github:object",
      idempotency_key: "#{request.object_type}:#{request.object_id}:#{request.delivery_id}",
      credential_id: credential_id
    })
  end

  defp normalize_result({:error, {class, code}}, job)
       when class in [:authorization, :configuration] do
    DurableDelivery.normalize_worker_result({:error, {:terminal, code}}, job)
  end

  defp normalize_result({:error, {:retryable, _code, %DateTime{} = retry_at}}, job) do
    if job.attempt >= job.max_attempts do
      {:cancel, "attempts_exhausted"}
    else
      delay = retry_at |> DateTime.diff(DateTime.utc_now(), :second) |> max(1) |> min(3_600)
      {:snooze, delay}
    end
  end

  defp normalize_result(result, job),
    do: DurableDelivery.normalize_worker_result(result, job)

  defp safe_code(code) when is_atom(code), do: code
  defp safe_code(_code), do: :invalid_worker_result
end
