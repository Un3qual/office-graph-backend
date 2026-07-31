defmodule OfficeGraph.GitHubIntegration.WebhookReceiptResult do
  @moduledoc false

  use Ash.TypedStruct

  typed_struct do
    field :status, :atom,
      allow_nil?: false,
      constraints: [one_of: [:created, :replayed]]
  end
end

defmodule OfficeGraph.GitHubIntegration.WebhookReceiptCommands do
  @moduledoc false

  @behaviour Ash.Resource.Actions.Implementation

  alias OfficeGraph.{DurableDelivery, Integrations, Operations}

  alias OfficeGraph.GitHubIntegration.{
    ActionSupport,
    Installation,
    InstallationCredential,
    StorageResult,
    WebhookReceiptPersistence,
    WebhookReceiptResult,
    WebhookWorker
  }

  alias OfficeGraph.Integrations.IntegrationCredential

  require Ash.Query

  @impl true
  def run(input, [mode: :record], _context) do
    case persist(input.arguments) do
      {:ok, result} -> {:ok, result}
      {:error, error} -> ActionSupport.rollback(Installation, error)
    end
  end

  def run(_input, _opts, _context), do: {:error, :forbidden}

  def record(
        %Installation{} = installation,
        %InstallationCredential{} = credential_binding,
        delivery_id,
        event_name,
        raw_body,
        pull_request_ids
      ) do
    StorageResult.run(fn ->
      Installation
      |> Ash.ActionInput.for_action(:record_webhook_receipt, %{
        installation_id: installation.id,
        credential_binding_id: credential_binding.id,
        credential_id: credential_binding.credential_id,
        delivery_id: delivery_id,
        event_name: event_name,
        raw_body: raw_body,
        pull_request_ids: pull_request_ids
      })
      |> Ash.run_action(authorize?: false)
      |> ActionSupport.normalize_action_result()
    end)
  end

  defp persist(attrs) do
    with {:ok, installation} <- locked_active_installation(attrs.installation_id),
         {:ok, _credential} <-
           locked_active_credential(
             installation,
             attrs.credential_binding_id,
             attrs.credential_id
           ),
         {:ok, request} <- operation_request(installation, attrs),
         {:ok, operation} <- Operations.start_system_operation(request),
         :ok <- persistence_ready(:provider_source),
         {:ok, source} <-
           Integrations.ensure_provider_source(
             "github_app:#{installation.app_slug}",
             "GitHub App #{installation.app_slug}"
           ),
         :ok <- persistence_ready(:archive),
         {:ok, archive, archive_state} <-
           Integrations.archive_system_delivery(operation, source, %{
             external_delivery_id: attrs.delivery_id,
             body: attrs.raw_body,
             provider_event: attrs.event_name,
             external_installation_id: installation.external_installation_id
           }),
         {:ok, status} <-
           record_delivery_effects(
             archive_state,
             installation,
             operation,
             archive.id,
             attrs
           ) do
      {:ok, WebhookReceiptResult.new!(status: status)}
    end
  end

  defp locked_active_installation(installation_id) do
    Installation
    |> Ash.Query.filter(id == ^installation_id and lifecycle_state == "active")
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %Installation{} = installation} -> {:ok, installation}
      {:ok, nil} -> {:error, :unknown_installation}
      {:error, error} -> {:error, error}
    end
  end

  defp locked_active_credential(installation, binding_id, credential_id) do
    binding_query =
      InstallationCredential
      |> Ash.Query.filter(
        id == ^binding_id and installation_id == ^installation.id and
          credential_id == ^credential_id and purpose == "webhook_secret"
      )
      |> Ash.Query.lock(:for_update)

    with {:ok, %InstallationCredential{}} <-
           Ash.read_one(binding_query, authorize?: false),
         {:ok, %IntegrationCredential{} = credential} <-
           active_credential(installation, credential_id) do
      {:ok, credential}
    else
      {:ok, nil} -> {:error, :unknown_installation}
      {:error, error} -> {:error, error}
    end
  end

  defp active_credential(installation, credential_id) do
    IntegrationCredential
    |> Ash.Query.filter(
      id == ^credential_id and organization_id == ^installation.organization_id and
        status == "active"
    )
    |> credential_workspace_scope(installation.workspace_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
  end

  defp credential_workspace_scope(query, nil),
    do: Ash.Query.filter(query, is_nil(workspace_id))

  defp credential_workspace_scope(query, workspace_id),
    do: Ash.Query.filter(query, workspace_id == ^workspace_id)

  defp operation_request(installation, attrs) do
    Operations.new_system_operation_request(%{
      organization_id: installation.organization_id,
      workspace_id: installation.workspace_id,
      principal_id: installation.webhook_principal_id,
      action: :provider_webhook_receive,
      authority_basis: "github_installation:#{installation.id}",
      causation_key: "github_delivery:#{attrs.delivery_id}",
      idempotency_scope: "github:delivery",
      idempotency_key: attrs.delivery_id,
      credential_id: attrs.credential_id
    })
  end

  defp record_delivery_effects(:replayed, _installation, _operation, _archive_id, _attrs),
    do: {:ok, :replayed}

  defp record_delivery_effects(:created, installation, operation, archive_id, attrs) do
    with {:ok, event} <-
           DurableDelivery.record_system_and_enqueue(operation, %{
             event_key: "github-delivery:#{attrs.delivery_id}",
             event_kind: "provider_delivery.received"
           }),
         {:ok, _jobs} <-
           enqueue_webhooks(
             installation,
             attrs.delivery_id,
             attrs.event_name,
             archive_id,
             event.id,
             attrs.pull_request_ids
           ) do
      {:ok, :created}
    end
  end

  defp enqueue_webhooks(
         installation,
         delivery_id,
         event_name,
         archive_id,
         event_id,
         pull_request_ids
       ) do
    pull_request_ids
    |> case do
      [] -> [nil]
      ids -> ids
    end
    |> Enum.reduce_while({:ok, []}, fn pull_request_id, {:ok, jobs} ->
      case enqueue_webhook(
             installation,
             delivery_id,
             event_name,
             archive_id,
             event_id,
             pull_request_id
           ) do
        {:ok, job} -> {:cont, {:ok, [job | jobs]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp enqueue_webhook(
         installation,
         delivery_id,
         event_name,
         archive_id,
         event_id,
         pull_request_id
       ) do
    args = %{
      "delivery_id" => delivery_id,
      "event_name" => event_name,
      "installation_id" => installation.id,
      "archive_id" => archive_id,
      "event_id" => event_id,
      "organization_id" => installation.organization_id,
      "workspace_id" => installation.workspace_id
    }

    args =
      if is_nil(pull_request_id),
        do: args,
        else: Map.put(args, "pull_request_id", pull_request_id)

    args
    |> WebhookWorker.new()
    |> Oban.insert()
  end

  defp persistence_ready(stage) do
    case WebhookReceiptPersistence.before_write(stage) do
      :ok -> :ok
      {:error, _error} -> {:error, :integration_storage_unavailable}
    end
  end
end
