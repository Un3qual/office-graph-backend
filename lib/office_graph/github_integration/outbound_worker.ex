defmodule OfficeGraph.GitHubIntegration.OutboundWorker do
  @moduledoc false

  @max_attempts 10
  @terminal_retry_delay_seconds 5

  use Oban.Worker,
    queue: :integrations,
    max_attempts: @max_attempts,
    unique: [period: :infinity, fields: [:worker, :queue, :args], states: :all]

  alias OfficeGraph.{Audit, DurableDelivery, Repo, Revisions}

  alias OfficeGraph.GitHubIntegration.{
    Installation,
    InstallationCredential,
    OutboundAction,
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
          }
        } = job
      )
      when is_binary(action_id) and is_binary(organization_id) and is_binary(workspace_id) do
    with {:ok, action} <- action(action_id, organization_id, workspace_id) do
      perform_action(action, job)
    else
      {:error, code} -> finish_terminal_job(job, code, {:cancel, safe_code(code)})
    end
  end

  def perform(_job), do: {:cancel, "invalid_github_outbound_job"}

  defp perform_action(%OutboundAction{state: "succeeded"}, _job), do: :ok

  defp perform_action(%OutboundAction{state: "terminal", failure_code: code}, job),
    do:
      finish_terminal_job(job, code || "terminal_failure", {:cancel, code || "terminal_failure"})

  defp perform_action(action, job) do
    with {:ok, installation} <- active_installation(action),
         {:ok, credential_id} <- credential_binding(installation.id),
         {:ok, credential} <-
           SecretStore.resolve(credential_id, %{
             organization_id: action.organization_id,
             workspace_id: action.workspace_id
           }),
         :ok <- require_current_target_version(action) do
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
    case Ash.get(OutboundAction, action_id, authorize?: false, not_found_error?: false) do
      {:ok,
       %OutboundAction{organization_id: ^organization_id, workspace_id: ^workspace_id} = action} ->
        {:ok, action}

      _missing_or_cross_scope ->
        {:error, :invalid_github_outbound_job}
    end
  end

  defp active_installation(action) do
    case Ash.get(Installation, action.installation_id,
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

      _missing_or_revoked ->
        {:error, :installation_revoked}
    end
  end

  defp credential_binding(installation_id) do
    InstallationCredential
    |> Ash.Query.filter(installation_id == ^installation_id and purpose == "app_private_key")
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %InstallationCredential{credential_id: credential_id}} -> {:ok, credential_id}
      _missing -> {:error, :invalid_credential}
    end
  end

  defp require_current_target_version(%OutboundAction{target_type: "review_comment"} = action),
    do: require_current_target_version(ReviewComment, action)

  defp require_current_target_version(%OutboundAction{target_type: "check_run"} = action),
    do: require_current_target_version(CheckRun, action)

  defp require_current_target_version(_action), do: {:error, :invalid_provider_response}

  defp require_current_target_version(resource, action) do
    case Ash.get(resource, action.target_id, authorize?: false, not_found_error?: false) do
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

      _missing_or_cross_scope ->
        {:error, :invalid_provider_response}
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

      case action.action_kind do
        "review_reply" -> find_or_create_review_reply(adapter, request, credential)
        "check_update" -> adapter.update_check(request, credential)
        _unsupported -> {:error, :invalid_provider_response}
      end
    end
  end

  defp find_or_create_review_reply(adapter, request, credential) do
    case adapter.find_review_reply(request, credential) do
      {:ok, nil} -> adapter.reply_to_review(request, credential)
      {:ok, response} when is_map(response) -> {:ok, response}
      {:ok, _invalid} -> {:error, :invalid_provider_response}
      {:error, _reason} = error -> error
    end
  end

  defp record_adapter_result({:ok, response}, action, job) do
    with {:ok, response_id} <- response_value(response, :id),
         {:ok, response_version} <- optional_response_value(response, :version) do
      updated =
        update_action!(action, %{
          state: "succeeded",
          provider_response_id: response_id,
          provider_response_version: response_version,
          failure_class: nil,
          failure_code: nil,
          attempted_at: DateTime.utc_now(),
          completed_at: DateTime.utc_now()
        })

      trace!(updated, "succeeded")
      :ok
    else
      _invalid -> record_adapter_result({:error, :invalid_provider_response}, action, job)
    end
  end

  defp record_adapter_result({:error, reason}, action, job) do
    {failure_class, failure_code, result} = classify(reason, job)

    persisted_state = if match?({:cancel, _code}, result), do: :terminal, else: :retryable

    persisted_class =
      if result == {:cancel, "attempts_exhausted"}, do: :terminal, else: failure_class

    updated =
      update_action!(action, %{
        state: Atom.to_string(persisted_state),
        failure_class: Atom.to_string(persisted_class),
        failure_code: Atom.to_string(failure_code),
        attempted_at: DateTime.utc_now(),
        completed_at: if(persisted_state == :terminal, do: DateTime.utc_now())
      })

    if persisted_state == :terminal do
      trace!(updated, "terminal")
      finish_terminal_job(job, failure_code, result)
    else
      result
    end
  end

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

  defp classify(:adapter_unavailable, _job),
    do: {:configuration, :adapter_unavailable, {:cancel, "adapter_unavailable"}}

  defp classify(:installation_revoked, _job),
    do: {:terminal, :installation_revoked, {:cancel, "installation_revoked"}}

  defp classify(:invalid_credential, _job),
    do: {:terminal, :invalid_credential, {:cancel, "invalid_credential"}}

  defp classify(:permission_denied, _job),
    do: {:terminal, :permission_denied, {:cancel, "permission_denied"}}

  defp classify(:stale_provider_version, _job),
    do: {:terminal, :stale_provider_version, {:cancel, "stale_provider_version"}}

  defp classify(_reason, _job),
    do: {:terminal, :invalid_provider_response, {:cancel, "invalid_provider_response"}}

  defp retry_budget(%Oban.Job{} = job), do: %{job | max_attempts: @max_attempts}

  defp finish_terminal_job(%Oban.Job{} = job, failure_code, result) do
    case stage_terminal_failure(job, failure_code) do
      :ok -> result
      {:error, _error} -> {:snooze, @terminal_retry_delay_seconds}
    end
  end

  defp stage_terminal_failure(job, failure_code) do
    meta = Map.put(job.meta || %{}, "terminal_failure_code", safe_code(failure_code))

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

  defp update_action!(action, attrs) do
    action
    |> Ash.Changeset.for_update(:record_result, attrs)
    |> Repo.ash_update!()
  end

  defp trace!(action, state) do
    operation = %{id: action.operation_id, principal_id: action.principal_id}
    event = "github.#{action.action_kind}.#{state}"
    Audit.record!(operation, event, "github_outbound_action", action.id)
    Revisions.record!(operation, "github_outbound_action", action.id, event, event)
  end

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
