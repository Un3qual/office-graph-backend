defmodule OfficeGraph.GitHubIntegration.WebhookWorker do
  @moduledoc false

  @max_attempts 10
  @terminal_retry_delay_seconds 5

  use Oban.Worker,
    queue: :integrations,
    max_attempts: @max_attempts,
    unique: [period: :infinity, fields: [:worker, :queue, :args], states: :all]

  alias OfficeGraph.{DurableDelivery, Integrations, Operations}
  alias OfficeGraph.DurableDelivery.DomainEvent

  alias OfficeGraph.GitHubIntegration.{
    Installation,
    InstallationCredential,
    RecordLoader,
    Reconciler,
    ReconciliationRequest
  }

  require Ash.Query

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "delivery_id" => delivery_id,
          "installation_id" => installation_id,
          "event_id" => event_id,
          "organization_id" => organization_id,
          "workspace_id" => workspace_id
        },
        meta: %{
          "terminal_phase" => "pre_operation",
          "terminal_failure_code" => failure_code,
          "terminal_cancel_code" => cancel_code,
          "terminal_installation_id" => installation_id,
          "terminal_delivery_id" => delivery_id
        }
      })
      when is_binary(failure_code) and is_binary(cancel_code) and is_binary(delivery_id) and
             is_binary(installation_id) and is_binary(event_id) and is_binary(organization_id) and
             (is_binary(workspace_id) or is_nil(workspace_id)) do
    with {:ok, failure_code} <- persisted_pre_operation_failure_code(failure_code) do
      persist_pre_operation_terminal_failure(
        event_id,
        organization_id,
        workspace_id,
        installation_id,
        delivery_id,
        failure_code,
        cancel_code
      )
    else
      {:error, :invalid_retry_failure_code} ->
        {:cancel, "invalid_github_webhook_terminalization"}
    end
  end

  @impl Oban.Worker
  def perform(
        %Oban.Job{
          args: %{
            "event_id" => event_id,
            "organization_id" => organization_id,
            "workspace_id" => workspace_id
          },
          meta: %{
            "terminal_failure_code" => failure_code,
            "terminal_cancel_code" => cancel_code,
            "terminal_operation_id" => operation_id,
            "terminal_installation_id" => installation_id,
            "terminal_object_type" => object_type,
            "terminal_object_id" => object_id,
            "terminal_delivery_id" => delivery_id
          }
        } = job
      )
      when is_binary(failure_code) and is_binary(operation_id) and is_binary(installation_id) and
             is_binary(object_type) and is_binary(object_id) and is_binary(delivery_id) and
             is_binary(cancel_code) and is_binary(event_id) and is_binary(organization_id) and
             (is_binary(workspace_id) or is_nil(workspace_id)) do
    with {:ok, request} <-
           ReconciliationRequest.new(%{
             installation_id: installation_id,
             object_type: object_type,
             object_id: object_id,
             delivery_id: delivery_id
           }),
         {:ok, operation} <- Operations.read_operation(operation_id) do
      persist_terminal_failure(job, operation, request, failure_code, cancel_code)
    else
      {:error, _error} ->
        retry_terminal_failure()
    end
  end

  @impl Oban.Worker
  def perform(
        %Oban.Job{
          args:
            %{
              "delivery_id" => delivery_id,
              "installation_id" => installation_id,
              "archive_id" => archive_id,
              "event_id" => event_id,
              "organization_id" => organization_id,
              "workspace_id" => workspace_id
            } = args
        } = job
      )
      when is_binary(delivery_id) and is_binary(installation_id) and is_binary(archive_id) and
             is_binary(event_id) and is_binary(organization_id) and
             (is_binary(workspace_id) or is_nil(workspace_id)) do
    with {:ok, installation} <- load_installation(installation_id, organization_id, workspace_id),
         {:ok, archive} <- load_archive(archive_id, delivery_id, installation),
         {:ok, credential_id} <- private_key_credential(installation.id),
         {:ok, request} <-
           reconciliation_request(
             archive,
             installation,
             delivery_id,
             Map.get(args, "pull_request_id")
           ),
         {:ok, operation_request} <-
           operation_request(installation, credential_id, request, event_id),
         {:ok, operation} <- Operations.start_system_operation(operation_request) do
      operation
      |> Reconciler.reconcile(request)
      |> normalize_result(job, operation, request)
    else
      {:error, :integration_storage_unavailable} ->
        normalize_pre_operation_storage_failure(job)

      {:error, code} ->
        failure_code = safe_pre_operation_failure_code(code)

        stage_and_persist_pre_operation_terminal_failure(
          job,
          failure_code,
          Atom.to_string(failure_code)
        )
    end
  end

  def perform(_job), do: {:cancel, "invalid_github_webhook_job"}

  defp load_archive(archive_id, delivery_id, installation) do
    case Integrations.provider_delivery_archive(
           installation.organization_id,
           installation.workspace_id,
           archive_id,
           delivery_id,
           record_loader: RecordLoader
         ) do
      {:ok, %{metadata: %{"installation_id" => external_installation_id}} = archive}
      when external_installation_id == installation.external_installation_id ->
        {:ok, archive}

      {:error, :integration_storage_unavailable} = error ->
        error

      _missing_or_mismatch ->
        {:error, :invalid_delivery_archive}
    end
  end

  defp load_installation(installation_id, organization_id, workspace_id) do
    case RecordLoader.get(Installation, installation_id,
           authorize?: false,
           not_found_error?: false
         ) do
      {:ok,
       %Installation{
         lifecycle_state: "active",
         organization_id: ^organization_id,
         workspace_id: ^workspace_id
       } = installation} ->
        {:ok, installation}

      {:ok, _missing_or_cross_scope} ->
        {:error, :installation_revoked}

      {:error, _storage_error} ->
        {:error, :integration_storage_unavailable}
    end
  end

  defp private_key_credential(installation_id) do
    query =
      Ash.Query.filter(
        InstallationCredential,
        installation_id == ^installation_id and purpose == "app_private_key"
      )

    case RecordLoader.read_one(InstallationCredential, query, authorize?: false) do
      {:ok, %InstallationCredential{credential_id: credential_id}} -> {:ok, credential_id}
      {:ok, _missing} -> {:error, :invalid_credential}
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  defp reconciliation_request(archive, installation, delivery_id, pull_request_id) do
    event_name = Map.get(archive.metadata, "event")

    with {:ok, payload} <- Jason.decode(archive.body),
         {:ok, {object_type, object_id}} <- provider_object(event_name, payload),
         {:ok, pull_request_id} <-
           validate_pull_request_scope(event_name, payload, pull_request_id) do
      ReconciliationRequest.new(%{
        installation_id: installation.id,
        object_type: object_type,
        object_id: object_id,
        pull_request_id: pull_request_id,
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

  defp provider_object("pull_request_review_thread", payload),
    do: nested_object(payload, "pull_request", "pull_request")

  defp provider_object("pull_request_review_comment", %{"action" => "deleted"} = payload),
    do: nested_object(payload, "pull_request", "pull_request")

  defp provider_object("pull_request_review_comment", payload),
    do: nested_object(payload, "comment", "review_comment")

  defp provider_object("check_run", payload),
    do: nested_object(payload, "check_run", "check_run")

  defp provider_object(_event_name, _payload), do: {:error, :unsupported_event}

  defp validate_pull_request_scope("check_run", payload, pull_request_id)
       when is_binary(pull_request_id) and pull_request_id != "" do
    pull_request_ids =
      payload
      |> get_in(["check_run", "pull_requests"])
      |> List.wrap()
      |> Enum.map(&pull_request_identity/1)

    if pull_request_id in pull_request_ids,
      do: {:ok, pull_request_id},
      else: {:error, :invalid_delivery_payload}
  end

  defp validate_pull_request_scope("check_run", payload, nil) do
    case get_in(payload, ["check_run", "pull_requests"]) do
      [] -> {:ok, nil}
      _associated_or_invalid -> {:error, :invalid_delivery_payload}
    end
  end

  defp validate_pull_request_scope("check_run", _payload, _pull_request_id),
    do: {:error, :invalid_delivery_payload}

  defp validate_pull_request_scope(_event_name, _payload, nil), do: {:ok, nil}

  defp validate_pull_request_scope(_event_name, _payload, _pull_request_id),
    do: {:error, :invalid_delivery_payload}

  defp pull_request_identity(%{"node_id" => node_id})
       when is_binary(node_id) and node_id != "",
       do: node_id

  defp pull_request_identity(%{"id" => id}) when is_integer(id) and id > 0,
    do: Integer.to_string(id)

  defp pull_request_identity(_pull_request), do: nil

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
      idempotency_key: reconciliation_idempotency_key(request),
      credential_id: credential_id
    })
  end

  defp reconciliation_idempotency_key(%{pull_request_id: pull_request_id} = request)
       when is_binary(pull_request_id),
       do:
         "#{request.object_type}:#{request.object_id}:pull_request:#{pull_request_id}:#{request.delivery_id}"

  defp reconciliation_idempotency_key(request),
    do: "#{request.object_type}:#{request.object_id}:#{request.delivery_id}"

  defp normalize_result(result, job),
    do: DurableDelivery.normalize_worker_result(result, job)

  defp normalize_result({:error, {class, code}}, job, operation, request)
       when class in [:terminal, :authorization, :configuration] do
    case DurableDelivery.normalize_worker_result({:error, {:terminal, code}}, job) do
      {:cancel, cancel_code} ->
        stage_and_persist_terminal_failure(job, operation, request, safe_code(code), cancel_code)

      other ->
        other
    end
  end

  defp normalize_result(
         {:error, {:retryable, code, %DateTime{} = retry_at}},
         job,
         operation,
         request
       ) do
    job = retry_budget(job)

    if job.attempt >= job.max_attempts do
      stage_and_persist_terminal_failure(job, operation, request, code)
    else
      delay = retry_at |> DateTime.diff(DateTime.utc_now(), :second) |> max(1) |> min(3_600)
      {:snooze, delay}
    end
  end

  defp normalize_result(
         {:error, {:retryable, code}} = result,
         job,
         operation,
         request
       ) do
    job = retry_budget(job)

    case DurableDelivery.normalize_worker_result(result, job) do
      {:cancel, "attempts_exhausted"} ->
        stage_and_persist_terminal_failure(job, operation, request, code)

      other ->
        other
    end
  end

  defp normalize_result(result, job, _operation, _request), do: normalize_result(result, job)

  defp stage_and_persist_terminal_failure(
         job,
         operation,
         request,
         failure_code,
         cancel_code \\ "attempts_exhausted"
       ) do
    case stage_terminal_failure(job, operation, request, failure_code, cancel_code) do
      :ok ->
        persist_terminal_failure(
          job,
          operation,
          request,
          Atom.to_string(failure_code),
          cancel_code
        )

      {:error, _error} ->
        retry_terminal_failure()
    end
  end

  defp stage_terminal_failure(job, operation, request, failure_code, cancel_code) do
    stage_terminal_metadata(job, %{
      "terminal_failure_code" => Atom.to_string(failure_code),
      "terminal_cancel_code" => cancel_code,
      "terminal_operation_id" => operation.id,
      "terminal_installation_id" => request.installation_id,
      "terminal_object_type" => request.object_type,
      "terminal_object_id" => request.object_id,
      "terminal_delivery_id" => request.delivery_id
    })
  end

  defp stage_terminal_metadata(job, metadata) do
    meta = Map.merge(job.meta || %{}, metadata)

    case Oban.update_job(job, %{meta: meta}) do
      {:ok, _updated_job} -> :ok
      {:error, error} -> {:error, error}
    end
  rescue
    error in [
      DBConnection.ConnectionError,
      Ecto.ConstraintError,
      Ecto.StaleEntryError,
      Postgrex.Error
    ] ->
      {:error, error}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp persist_terminal_failure(
         %Oban.Job{
           args: %{
             "event_id" => event_id,
             "organization_id" => organization_id,
             "workspace_id" => workspace_id
           }
         },
         operation,
         request,
         failure_code,
         cancel_code
       ) do
    scope = %{organization_id: organization_id, workspace_id: workspace_id}

    with {:ok, _outcome} <- Reconciler.finalize_failure(operation, request, failure_code),
         :ok <- DurableDelivery.mark_processing_failed(event_id, scope, failure_code) do
      {:cancel, cancel_code}
    else
      {:error, _error} -> retry_terminal_failure()
    end
  end

  defp normalize_pre_operation_storage_failure(job) do
    case DurableDelivery.normalize_worker_result(
           {:error, {:retryable, :integration_storage_unavailable}},
           retry_budget(job)
         ) do
      {:cancel, "attempts_exhausted"} ->
        stage_and_persist_pre_operation_terminal_failure(
          job,
          :integration_storage_unavailable
        )

      other ->
        other
    end
  end

  defp stage_and_persist_pre_operation_terminal_failure(
         %Oban.Job{
           args: %{
             "delivery_id" => delivery_id,
             "installation_id" => installation_id,
             "event_id" => event_id,
             "organization_id" => organization_id,
             "workspace_id" => workspace_id
           }
         } = job,
         failure_code,
         cancel_code \\ "attempts_exhausted"
       ) do
    metadata = %{
      "terminal_phase" => "pre_operation",
      "terminal_failure_code" => Atom.to_string(failure_code),
      "terminal_cancel_code" => cancel_code,
      "terminal_installation_id" => installation_id,
      "terminal_delivery_id" => delivery_id
    }

    case stage_terminal_metadata(job, metadata) do
      :ok ->
        persist_pre_operation_terminal_failure(
          event_id,
          organization_id,
          workspace_id,
          installation_id,
          delivery_id,
          failure_code,
          cancel_code
        )

      {:error, _error} ->
        retry_terminal_failure()
    end
  end

  defp persist_pre_operation_terminal_failure(
         event_id,
         organization_id,
         workspace_id,
         installation_id,
         delivery_id,
         failure_code,
         cancel_code
       ) do
    scope = %{organization_id: organization_id, workspace_id: workspace_id}

    with {:ok, operation} <- receipt_operation(event_id, scope),
         {:ok, _outcome} <-
           Reconciler.exhaust_pre_operation(
             operation,
             installation_id,
             delivery_id,
             failure_code
           ),
         :ok <-
           DurableDelivery.mark_processing_failed(
             event_id,
             scope,
             Atom.to_string(failure_code)
           ) do
      {:cancel, cancel_code}
    else
      {:error, _error} -> retry_terminal_failure()
    end
  end

  defp receipt_operation(event_id, scope) do
    %{organization_id: organization_id, workspace_id: workspace_id} = scope

    case RecordLoader.get(DomainEvent, event_id,
           authorize?: false,
           not_found_error?: false
         ) do
      {:ok,
       %DomainEvent{
         organization_id: ^organization_id,
         workspace_id: ^workspace_id,
         operation_kind: "system",
         event_kind: "provider_delivery.received",
         operation_id: operation_id
       }} ->
        Operations.read_operation(operation_id)

      {:ok, _missing_or_cross_scope} ->
        {:error, :forbidden}

      {:error, _storage_error} ->
        {:error, :integration_storage_unavailable}
    end
  end

  defp retry_terminal_failure, do: {:snooze, @terminal_retry_delay_seconds}

  @pre_operation_failure_codes ~w(
    provider_rate_limited
    provider_unavailable
    integration_storage_unavailable
    installation_revoked
    invalid_credential
    invalid_delivery_archive
    invalid_delivery_payload
    invalid_worker_result
  )a

  defp persisted_pre_operation_failure_code(code) when is_binary(code) do
    case Enum.find(@pre_operation_failure_codes, &(Atom.to_string(&1) == code)) do
      nil -> {:error, :invalid_retry_failure_code}
      failure_code -> {:ok, failure_code}
    end
  end

  defp safe_pre_operation_failure_code(code) when code in @pre_operation_failure_codes, do: code
  defp safe_pre_operation_failure_code(_code), do: :invalid_worker_result

  defp retry_budget(%Oban.Job{} = job), do: %{job | max_attempts: @max_attempts}

  defp safe_code(code) when is_atom(code), do: code
  defp safe_code(_code), do: :invalid_worker_result
end
