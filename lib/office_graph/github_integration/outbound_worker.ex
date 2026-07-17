defmodule OfficeGraph.GitHubIntegration.OutboundWorker do
  @moduledoc false

  @max_attempts 10
  @terminal_retry_delay_seconds 5

  use Oban.Worker,
    queue: :integrations,
    max_attempts: @max_attempts,
    unique: [period: :infinity, fields: [:worker, :queue, :args], states: :all]

  alias OfficeGraph.{Audit, DurableDelivery, Operations, Repo, Revisions}

  alias OfficeGraph.GitHubIntegration.{
    Installation,
    InstallationCredential,
    OutboundAction,
    RecordLoader,
    SecretStore
  }

  alias OfficeGraph.SoftwareProving.{CheckRun, ReviewComment}

  require Ash.Query

  @impl Oban.Worker
  def perform(
        %Oban.Job{
          args: %{
            "action_id" => action_id,
            "organization_id" => organization_id,
            "workspace_id" => workspace_id
          },
          meta: %{"successful_action_id" => successful_action_id} = metadata
        } = job
      )
      when is_binary(action_id) and is_binary(organization_id) and
             (is_binary(workspace_id) or is_nil(workspace_id)) and
             successful_action_id == action_id do
    case successful_intent(metadata) do
      {:ok, response_id, response_version} ->
        persist_staged_successful_action(
          job,
          action_id,
          organization_id,
          workspace_id,
          response_id,
          response_version
        )

      {:error, code} ->
        finish_terminal_job(job, code, {:cancel, code})
    end
  end

  def perform(
        %Oban.Job{
          args: %{
            "action_id" => action_id,
            "organization_id" => organization_id,
            "workspace_id" => workspace_id
          },
          meta: %{"terminal_action_id" => terminal_action_id} = metadata
        } = job
      )
      when is_binary(action_id) and is_binary(organization_id) and
             (is_binary(workspace_id) or is_nil(workspace_id)) and
             terminal_action_id == action_id do
    case terminal_intent(metadata) do
      {:ok, failure_class, failure_code, result_code} ->
        persist_staged_terminal_action(
          job,
          action_id,
          organization_id,
          workspace_id,
          failure_class,
          failure_code,
          result_code
        )

      {:error, code} ->
        finish_terminal_job(job, code, {:cancel, code})
    end
  end

  def perform(
        %Oban.Job{
          args: %{
            "action_id" => action_id,
            "organization_id" => organization_id,
            "workspace_id" => workspace_id
          }
        } = job
      )
      when is_binary(action_id) and is_binary(organization_id) and
             (is_binary(workspace_id) or is_nil(workspace_id)) do
    with {:ok, action} <- action(action_id, organization_id, workspace_id) do
      perform_action(action, job)
    else
      {:error, :integration_storage_unavailable} ->
        normalize_action_lookup_failure(job, action_id)

      {:error, code} ->
        finish_terminal_job(job, code, {:cancel, safe_code(code)})
    end
  end

  def perform(_job), do: {:cancel, "invalid_github_outbound_job"}

  defp perform_action(%OutboundAction{state: "succeeded"} = action, _job) do
    case trace(action, "succeeded") do
      :ok -> :ok
      {:error, :integration_storage_unavailable} -> retry_completed_trace()
    end
  end

  defp perform_action(%OutboundAction{state: "terminal", failure_code: code} = action, job) do
    case trace(action, "terminal") do
      :ok ->
        finish_terminal_job(
          job,
          code || "terminal_failure",
          {:cancel, code || "terminal_failure"}
        )

      {:error, :integration_storage_unavailable} ->
        retry_completed_trace()
    end
  end

  defp perform_action(action, job) do
    with {:ok, installation} <- active_installation(action),
         {:ok, credential_id} <- credential_binding(installation.id),
         {:ok, credential} <-
           SecretStore.resolve(credential_id, %{
             organization_id: action.organization_id,
             workspace_id: action.workspace_id
           }) do
      action
      |> call_adapter(installation, credential)
      |> record_adapter_result(action, job)
    else
      {:error, :forbidden} ->
        record_adapter_result({:error, :invalid_credential}, action, job)

      {:error, reason} when reason in [:invalid_secret_reference, :secret_not_found] ->
        record_adapter_result({:error, :invalid_credential}, action, job)

      {:error, reason} ->
        record_adapter_result({:error, reason}, action, job)
    end
  end

  defp action(action_id, organization_id, workspace_id) do
    case RecordLoader.get(OutboundAction, action_id,
           authorize?: false,
           not_found_error?: false
         ) do
      {:ok,
       %OutboundAction{organization_id: ^organization_id, workspace_id: ^workspace_id} = action} ->
        {:ok, action}

      {:ok, _missing_or_cross_scope} ->
        {:error, :invalid_github_outbound_job}

      {:error, _storage_error} ->
        {:error, :integration_storage_unavailable}
    end
  end

  defp active_installation(action) do
    case RecordLoader.get(Installation, action.installation_id,
           authorize?: false,
           not_found_error?: false
         ) do
      {:ok,
       %Installation{
         lifecycle_state: "active",
         organization_id: organization_id,
         workspace_id: workspace_id
       } = installation}
      when organization_id == action.organization_id and workspace_id == action.workspace_id ->
        {:ok, installation}

      {:ok, _missing_or_revoked} ->
        {:error, :installation_revoked}

      {:error, _storage_error} ->
        {:error, :integration_storage_unavailable}
    end
  end

  defp credential_binding(installation_id) do
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

  defp require_current_target_version(%OutboundAction{target_type: "review_comment"} = action),
    do: require_current_target_version(ReviewComment, action)

  defp require_current_target_version(%OutboundAction{target_type: "check_run"} = action),
    do: require_current_target_version(CheckRun, action)

  defp require_current_target_version(_action), do: {:error, :invalid_provider_response}

  defp require_current_target_version(resource, action) do
    case RecordLoader.get(resource, action.target_id,
           authorize?: false,
           not_found_error?: false
         ) do
      {:ok,
       %{
         organization_id: organization_id,
         workspace_id: workspace_id,
         provider_version: provider_version
       }}
      when organization_id == action.organization_id and workspace_id == action.workspace_id ->
        if provider_version == action.expected_provider_version,
          do: :ok,
          else: {:error, :stale_provider_version}

      {:ok, _missing_or_cross_scope} ->
        {:error, :invalid_provider_response}

      {:error, _storage_error} ->
        {:error, :integration_storage_unavailable}
    end
  end

  defp call_adapter(action, installation, credential) do
    adapter = Application.fetch_env!(:office_graph, :github_adapter)

    with {:ok, request} <- normalize_input(action.input) do
      request =
        request
        |> Map.put(:idempotency_key, action.id)
        |> Map.put(:expected_provider_version, action.expected_provider_version)
        |> Map.put(:external_installation_id, installation.external_installation_id)

      call_adapter(action, adapter, request, credential)
    end
  end

  defp call_adapter(
         %OutboundAction{action_kind: "review_reply"} = action,
         adapter,
         request,
         credential
       ) do
    case adapter.find_review_reply(request, credential) do
      {:ok, nil} ->
        with :ok <- require_current_target_version(action) do
          adapter.reply_to_review(request, credential)
        end

      {:ok, response} when is_map(response) ->
        {:ok, response}

      {:ok, _invalid} ->
        {:error, :invalid_provider_response}

      {:error, _reason} = error ->
        error
    end
  end

  defp call_adapter(
         %OutboundAction{action_kind: "check_update"} = action,
         adapter,
         request,
         credential
       ) do
    with :ok <- require_current_target_version(action) do
      adapter.update_check(request, credential)
    end
  end

  defp call_adapter(_action, _adapter, _request, _credential),
    do: {:error, :invalid_provider_response}

  defp record_adapter_result({:ok, response}, action, job) do
    with {:ok, response_id} <- response_value(response, :id),
         {:ok, response_version} <- optional_response_value(response, :version) do
      stage_and_persist_successful_action(job, action, response_id, response_version)
    else
      _invalid -> record_adapter_result({:error, :invalid_provider_response}, action, job)
    end
  end

  defp record_adapter_result({:error, reason}, action, job) do
    {failure_class, failure_code, result} = classify(reason, job)

    persisted_state = if match?({:cancel, _code}, result), do: :terminal, else: :retryable

    persisted_class =
      if result == {:cancel, "attempts_exhausted"}, do: :terminal, else: failure_class

    if persisted_state == :terminal do
      stage_and_persist_terminal_action(job, action, persisted_class, failure_code, result)
    else
      case update_action(action, %{
             state: Atom.to_string(persisted_state),
             failure_class: Atom.to_string(persisted_class),
             failure_code: Atom.to_string(failure_code),
             attempted_at: DateTime.utc_now(),
             completed_at: nil
           }) do
        {:ok, _updated} -> result
        {:error, :integration_storage_unavailable} -> retry_state_persistence_result(result)
      end
    end
  end

  defp retry_state_persistence_result({:snooze, _delay} = result), do: result

  defp retry_state_persistence_result(_result),
    do: {:error, "integration_storage_unavailable"}

  defp classify({:rate_limited, %DateTime{} = reset_at}, %Oban.Job{} = job) do
    job = retry_budget(job)

    result =
      if job.attempt >= job.max_attempts do
        {:cancel, "attempts_exhausted"}
      else
        delay = reset_at |> DateTime.diff(DateTime.utc_now(), :second) |> max(1) |> min(3_600)
        {:snooze, delay}
      end

    {:retryable, :provider_rate_limited, result}
  end

  defp classify(reason, job)
       when reason in [:network_error, :provider_unavailable, :unavailable] do
    result =
      DurableDelivery.normalize_worker_result(
        {:error, {:retryable, :provider_unavailable}},
        retry_budget(job)
      )

    {:retryable, :provider_unavailable, result}
  end

  defp classify(:integration_storage_unavailable, job) do
    result =
      DurableDelivery.normalize_worker_result(
        {:error, {:retryable, :integration_storage_unavailable}},
        retry_budget(job)
      )

    {:retryable, :integration_storage_unavailable, result}
  end

  defp classify(:adapter_unavailable, _job),
    do: {:configuration, :adapter_unavailable, {:cancel, "adapter_unavailable"}}

  defp classify(:installation_revoked, _job),
    do: {:terminal, :installation_revoked, {:cancel, "installation_revoked"}}

  defp classify(:invalid_credential, _job),
    do: {:terminal, :invalid_credential, {:cancel, "invalid_credential"}}

  defp classify(:permission_denied, _job),
    do: {:authorization, :permission_denied, {:cancel, "permission_denied"}}

  defp classify(:stale_provider_version, _job),
    do: {:terminal, :stale_provider_version, {:cancel, "stale_provider_version"}}

  defp classify(_reason, _job),
    do: {:terminal, :invalid_provider_response, {:cancel, "invalid_provider_response"}}

  defp retry_budget(%Oban.Job{} = job), do: %{job | max_attempts: @max_attempts}

  defp normalize_action_lookup_failure(job, action_id) do
    result =
      DurableDelivery.normalize_worker_result(
        {:error, {:retryable, :integration_storage_unavailable}},
        retry_budget(job)
      )

    case result do
      {:cancel, "attempts_exhausted"} -> stage_terminal_action(job, action_id)
      other -> other
    end
  end

  defp stage_terminal_action(job, action_id) do
    metadata =
      terminal_metadata(
        action_id,
        "terminal",
        "integration_storage_unavailable",
        "attempts_exhausted"
      )

    case stage_job_metadata(job, metadata) do
      :ok -> {:snooze, @terminal_retry_delay_seconds}
      {:error, _error} -> {:snooze, @terminal_retry_delay_seconds}
    end
  end

  defp stage_and_persist_terminal_action(
         job,
         action,
         failure_class,
         failure_code,
         {:cancel, result_code}
       ) do
    metadata =
      terminal_metadata(
        action.id,
        safe_code(failure_class),
        safe_code(failure_code),
        safe_code(result_code)
      )

    case stage_job_metadata(job, metadata) do
      :ok ->
        staged_job = %{job | meta: Map.merge(job.meta || %{}, metadata)}

        persist_terminal_action(
          staged_job,
          action,
          safe_code(failure_class),
          safe_code(failure_code),
          safe_code(result_code)
        )

      {:error, _error} ->
        {:snooze, @terminal_retry_delay_seconds}
    end
  end

  defp stage_and_persist_successful_action(job, action, response_id, response_version) do
    metadata = successful_metadata(action.id, response_id, response_version)

    case stage_job_metadata(job, metadata) do
      :ok ->
        staged_job = %{job | meta: Map.merge(job.meta || %{}, metadata)}
        persist_successful_action(staged_job, action, response_id, response_version)

      {:error, _error} ->
        {:snooze, @terminal_retry_delay_seconds}
    end
  end

  defp persist_staged_successful_action(
         job,
         action_id,
         organization_id,
         workspace_id,
         response_id,
         response_version
       ) do
    case action(action_id, organization_id, workspace_id) do
      {:ok, action} ->
        persist_successful_action(job, action, response_id, response_version)

      {:error, :integration_storage_unavailable} ->
        {:snooze, @terminal_retry_delay_seconds}

      {:error, code} ->
        finish_terminal_job(job, code, {:cancel, safe_code(code)})
    end
  end

  defp persist_successful_action(
         _job,
         %OutboundAction{
           state: "succeeded",
           provider_response_id: response_id,
           provider_response_version: response_version
         } = action,
         response_id,
         response_version
       ) do
    case trace(action, "succeeded") do
      :ok -> :ok
      {:error, :integration_storage_unavailable} -> retry_completed_trace()
    end
  end

  defp persist_successful_action(
         _job,
         %OutboundAction{state: state} = action,
         response_id,
         response_version
       )
       when state in ["pending", "retryable"] do
    attrs = %{
      state: "succeeded",
      provider_response_id: response_id,
      provider_response_version: response_version,
      failure_class: nil,
      failure_code: nil,
      attempted_at: DateTime.utc_now(),
      completed_at: DateTime.utc_now()
    }

    case update_action(action, attrs) do
      {:ok, updated} ->
        case trace(updated, "succeeded") do
          :ok -> :ok
          {:error, :integration_storage_unavailable} -> retry_completed_trace()
        end

      {:error, :integration_storage_unavailable} ->
        {:snooze, @terminal_retry_delay_seconds}
    end
  end

  defp persist_successful_action(job, _action, _response_id, _response_version) do
    finish_terminal_job(
      job,
      "invalid_provider_response",
      {:cancel, "invalid_provider_response"}
    )
  end

  defp persist_staged_terminal_action(
         job,
         action_id,
         organization_id,
         workspace_id,
         failure_class,
         failure_code,
         result_code
       ) do
    case action(action_id, organization_id, workspace_id) do
      {:ok, action} ->
        persist_terminal_action(
          job,
          action,
          failure_class,
          failure_code,
          result_code
        )

      {:error, :integration_storage_unavailable} ->
        {:snooze, @terminal_retry_delay_seconds}

      {:error, code} ->
        finish_terminal_job(job, code, {:cancel, safe_code(code)})
    end
  end

  defp persist_terminal_action(
         _job,
         %OutboundAction{state: "succeeded"} = action,
         _failure_class,
         _failure_code,
         _result_code
       ) do
    case trace(action, "succeeded") do
      :ok -> :ok
      {:error, :integration_storage_unavailable} -> retry_completed_trace()
    end
  end

  defp persist_terminal_action(
         job,
         %OutboundAction{state: "terminal"} = action,
         _failure_class,
         failure_code,
         result_code
       ) do
    case trace(action, "terminal") do
      :ok -> finish_terminal_job(job, action.failure_code || failure_code, {:cancel, result_code})
      {:error, :integration_storage_unavailable} -> retry_completed_trace()
    end
  end

  defp persist_terminal_action(job, action, failure_class, failure_code, result_code) do
    case update_action(action, %{
           state: "terminal",
           failure_class: failure_class,
           failure_code: failure_code,
           attempted_at: DateTime.utc_now(),
           completed_at: DateTime.utc_now()
         }) do
      {:ok, updated} ->
        case trace(updated, "terminal") do
          :ok -> finish_terminal_job(job, failure_code, {:cancel, result_code})
          {:error, :integration_storage_unavailable} -> retry_completed_trace()
        end

      {:error, :integration_storage_unavailable} ->
        {:snooze, @terminal_retry_delay_seconds}
    end
  end

  defp finish_terminal_job(%Oban.Job{} = job, failure_code, result) do
    case stage_terminal_failure(job, failure_code) do
      :ok -> result
      {:error, _error} -> {:snooze, @terminal_retry_delay_seconds}
    end
  end

  defp stage_terminal_failure(job, failure_code) do
    stage_job_metadata(job, %{"terminal_failure_code" => safe_code(failure_code)})
  end

  defp stage_job_metadata(job, metadata) do
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

  defp update_action(action, attrs) do
    action
    |> Ash.Changeset.for_update(:record_result, attrs)
    |> Ash.update(authorize?: false, return_notifications?: true)
    |> case do
      {:ok, updated, _notifications} -> {:ok, updated}
      {:ok, updated} -> {:ok, updated}
      {:error, _error} -> {:error, :integration_storage_unavailable}
    end
  rescue
    _error in [
      Ash.Error.Forbidden,
      Ash.Error.Framework,
      Ash.Error.Invalid,
      Ash.Error.Unknown,
      DBConnection.ConnectionError,
      Ecto.ConstraintError,
      Ecto.StaleEntryError,
      Postgrex.Error,
      RuntimeError
    ] ->
      {:error, :integration_storage_unavailable}
  catch
    _kind, _reason -> {:error, :integration_storage_unavailable}
  end

  defp trace(action, state) do
    operation = %{id: action.operation_id, principal_id: action.principal_id}
    event = "github.#{action.action_kind}.#{state}"

    Repo.transaction(fn ->
      with {:ok, _locked_operation} <- Operations.lock_operation(operation.id) do
        Audit.record_once!(operation, event, "github_outbound_action", action.id)
        Revisions.record_once!(operation, "github_outbound_action", action.id, event, event)
        :ok
      else
        {:error, error} -> Repo.rollback(error)
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, _error} -> {:error, :integration_storage_unavailable}
    end
  rescue
    _error in [
      Ash.Error.Forbidden,
      Ash.Error.Framework,
      Ash.Error.Invalid,
      Ash.Error.Unknown,
      DBConnection.ConnectionError,
      Ecto.ConstraintError,
      Ecto.StaleEntryError,
      Postgrex.Error,
      RuntimeError
    ] ->
      {:error, :integration_storage_unavailable}
  catch
    _kind, _reason -> {:error, :integration_storage_unavailable}
  end

  defp retry_completed_trace, do: {:snooze, @terminal_retry_delay_seconds}

  defp terminal_metadata(action_id, failure_class, failure_code, result_code) do
    %{
      "terminal_action_id" => action_id,
      "terminal_failure_class" => failure_class,
      "terminal_failure_code" => failure_code,
      "terminal_result_code" => result_code
    }
  end

  defp successful_metadata(action_id, response_id, response_version) do
    %{
      "successful_action_id" => action_id,
      "successful_provider_response_id" => response_id,
      "successful_provider_response_version" => response_version
    }
  end

  defp successful_intent(metadata) do
    response_id = Map.get(metadata, "successful_provider_response_id")
    response_version = Map.get(metadata, "successful_provider_response_version")

    if is_binary(response_id) and response_id != "" and
         (is_nil(response_version) or (is_binary(response_version) and response_version != "")) do
      {:ok, response_id, response_version}
    else
      {:error, "invalid_github_outbound_job"}
    end
  end

  defp terminal_intent(metadata) do
    failure_class = Map.get(metadata, "terminal_failure_class", "terminal")
    failure_code = Map.get(metadata, "terminal_failure_code", "integration_storage_unavailable")
    result_code = Map.get(metadata, "terminal_result_code", "attempts_exhausted")

    if failure_class in ~w(terminal authorization configuration) and
         Enum.all?([failure_code, result_code], &safe_metadata_code?/1) do
      {:ok, failure_class, failure_code, result_code}
    else
      {:error, "invalid_github_outbound_job"}
    end
  end

  defp safe_metadata_code?(code) when is_binary(code),
    do: Regex.match?(~r/^[a-z][a-z0-9_]*$/, code)

  defp safe_metadata_code?(_code), do: false

  defp response_value(response, key) when is_map(response) do
    case Map.get(response, key, Map.get(response, to_string(key))) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _invalid -> {:error, :invalid_provider_response}
    end
  end

  defp optional_response_value(response, key) do
    case Map.get(response, key, Map.get(response, to_string(key))) do
      nil -> {:ok, nil}
      value when is_binary(value) and value != "" -> {:ok, value}
      _invalid -> {:error, :invalid_provider_response}
    end
  end

  @input_keys %{
    "body" => :body,
    "conclusion" => :conclusion,
    "details_url" => :details_url,
    "expected_provider_version" => :expected_provider_version,
    "status" => :status,
    "target_node_id" => :target_node_id
  }

  defp normalize_input(input) when is_map(input) do
    Enum.reduce_while(input, {:ok, %{}}, fn {key, value}, {:ok, normalized} ->
      case Map.fetch(@input_keys, to_string(key)) do
        {:ok, atom_key} -> {:cont, {:ok, Map.put(normalized, atom_key, value)}}
        :error -> {:halt, {:error, :invalid_provider_response}}
      end
    end)
  end

  defp normalize_input(_input), do: {:error, :invalid_provider_response}

  defp safe_code(code) when is_atom(code), do: Atom.to_string(code)
  defp safe_code(code) when is_binary(code), do: code
end
