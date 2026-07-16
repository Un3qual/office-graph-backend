defmodule OfficeGraph.GitHubIntegration.OutboundCommands do
  @moduledoc false

  alias OfficeGraph.{Audit, Authorization, Operations, Repo, Revisions}

  alias OfficeGraph.GitHubIntegration.{
    Installation,
    OutboundAction,
    OutboundWorker,
    PermissionEntry,
    RecordLoader,
    SyncOutcome
  }

  alias OfficeGraph.SoftwareProving.{CheckRun, ReviewComment}

  alias OfficeGraph.SoftwareProving.GitHub.{
    CheckRunExtension,
    ReviewCommentExtension
  }

  require Ash.Query

  def reply_to_review(session_context, operation, attrs) when is_map(attrs) do
    with :ok <- Operations.validate_operation_context(session_context, operation),
         :ok <- Operations.validate_operation_action(operation, "github.review.reply"),
         :ok <- Operations.validate_command_replay(operation, attrs),
         :ok <- authorize(session_context, operation, :github_review_reply),
         {:ok, normalized} <- normalize_reply(attrs) do
      replay_or_execute(session_context, operation, "review_reply", fn ->
        execute_review_reply(session_context, operation, normalized)
      end)
    end
  end

  def reply_to_review(_session_context, _operation, _attrs), do: {:error, :forbidden}

  defp execute_review_reply(session_context, operation, normalized) do
    with {:ok, installation} <- active_installation(session_context, normalized.installation_id),
         :ok <- require_permission(installation, "pull_requests"),
         {:ok, target} <- review_target(session_context, normalized),
         :ok <- require_version(target.record, normalized.expected_provider_version),
         :ok <- require_installation_provenance(installation, target.record) do
      persist_and_enqueue(
        session_context,
        operation,
        installation,
        target,
        "review_reply",
        normalized
      )
    end
  end

  def update_check(session_context, operation, attrs) when is_map(attrs) do
    with :ok <- Operations.validate_operation_context(session_context, operation),
         :ok <- Operations.validate_operation_action(operation, "github.check.update"),
         :ok <- Operations.validate_command_replay(operation, attrs),
         :ok <- authorize(session_context, operation, :github_check_update),
         {:ok, normalized} <- normalize_check(attrs) do
      replay_or_execute(session_context, operation, "check_update", fn ->
        execute_check_update(session_context, operation, normalized)
      end)
    end
  end

  def update_check(_session_context, _operation, _attrs), do: {:error, :forbidden}

  defp execute_check_update(session_context, operation, normalized) do
    with {:ok, installation} <- active_installation(session_context, normalized.installation_id),
         :ok <- require_permission(installation, "checks"),
         {:ok, target} <- check_target(session_context, normalized),
         :ok <- require_version(target.record, normalized.expected_provider_version),
         :ok <- require_installation_provenance(installation, target.record) do
      persist_and_enqueue(
        session_context,
        operation,
        installation,
        target,
        "check_update",
        normalized
      )
    end
  end

  defp replay_or_execute(session_context, operation, action_kind, execute) do
    case action_by_operation(operation.id) do
      {:ok, nil} -> execute.()
      {:ok, action} -> validate_existing_action(action, session_context, action_kind)
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  defp validate_existing_action(
         %OutboundAction{
           action_kind: action_kind,
           principal_id: principal_id,
           organization_id: organization_id,
           workspace_id: workspace_id
         } = action,
         session_context,
         action_kind
       )
       when principal_id == session_context.principal_id and
              organization_id == session_context.organization_id and
              workspace_id == session_context.workspace_id,
       do: {:ok, action}

  defp validate_existing_action(_action, _session_context, _action_kind),
    do: {:error, :forbidden}

  defp authorize(session_context, operation, capability) do
    Authorization.authorize_operation(session_context, operation, capability,
      organization_id: session_context.organization_id
    )
  end

  defp normalize_reply(attrs) do
    with {:ok, installation_id} <- required_uuid(attrs, :installation_id),
         {:ok, review_comment_id} <- required_uuid(attrs, :review_comment_id),
         {:ok, body} <- required_raw_string(attrs, :body),
         {:ok, expected_provider_version} <- required_string(attrs, :expected_provider_version) do
      {:ok,
       %{
         installation_id: installation_id,
         review_comment_id: review_comment_id,
         body: body,
         expected_provider_version: expected_provider_version
       }}
    end
  end

  defp normalize_check(attrs) do
    with {:ok, installation_id} <- required_uuid(attrs, :installation_id),
         {:ok, check_run_id} <- required_uuid(attrs, :check_run_id),
         {:ok, status} <- one_of_string(attrs, :status, ~w(queued in_progress completed)),
         {:ok, conclusion} <- check_conclusion(attrs, status),
         {:ok, details_url} <- required_string(attrs, :details_url),
         {:ok, expected_provider_version} <- required_string(attrs, :expected_provider_version) do
      {:ok,
       %{
         installation_id: installation_id,
         check_run_id: check_run_id,
         status: status,
         conclusion: conclusion,
         details_url: details_url,
         expected_provider_version: expected_provider_version
       }}
    end
  end

  defp check_conclusion(attrs, "completed") do
    one_of_string(
      attrs,
      :conclusion,
      ~w(success failure neutral cancelled skipped timed_out action_required)
    )
  end

  defp check_conclusion(attrs, status) when status in ~w(queued in_progress) do
    case fetch(attrs, :conclusion) do
      nil -> {:ok, nil}
      _conclusion -> {:error, {:invalid_field, :conclusion}}
    end
  end

  defp active_installation(session_context, installation_id) do
    case RecordLoader.get(Installation, installation_id,
           authorize?: false,
           not_found_error?: false
         ) do
      {:ok,
       %Installation{
         lifecycle_state: "active",
         organization_id: organization_id,
         workspace_id: workspace_id
       } = installation}
      when organization_id == session_context.organization_id and
             workspace_id == session_context.workspace_id ->
        {:ok, installation}

      {:ok, _missing_or_cross_scope} ->
        {:error, :forbidden}

      {:error, _storage_error} ->
        {:error, :integration_storage_unavailable}
    end
  end

  defp require_permission(installation, permission_name) do
    PermissionEntry
    |> Ash.Query.filter(
      permission_snapshot_id == ^installation.current_permission_snapshot_id and
        name == ^permission_name
    )
    |> then(&RecordLoader.read_one(PermissionEntry, &1, authorize?: false))
    |> case do
      {:ok, %{access_level: access_level}} when access_level in ~w(write admin) ->
        :ok

      {:ok, _missing_or_insufficient} ->
        {:error, {:authorization, :installation_permission_missing}}

      {:error, _storage_error} ->
        {:error, :integration_storage_unavailable}
    end
  end

  defp review_target(session_context, normalized) do
    with {:ok, record} <-
           scoped_target(ReviewComment, normalized.review_comment_id, session_context),
         :ok <- require_replyable_review_comment(record),
         {:ok, extension} <- review_comment_extension(record.id) do
      {:ok, %{record: record, node_id: extension.node_id}}
    end
  end

  defp require_replyable_review_comment(%ReviewComment{state: "published"}), do: :ok
  defp require_replyable_review_comment(_record), do: {:error, :forbidden}

  defp check_target(session_context, normalized) do
    with {:ok, record} <- scoped_target(CheckRun, normalized.check_run_id, session_context),
         {:ok, extension} <- check_run_extension(record.id) do
      {:ok, %{record: record, node_id: extension.node_id}}
    end
  end

  defp scoped_target(resource, id, session_context) do
    case RecordLoader.get(resource, id, authorize?: false, not_found_error?: false) do
      {:ok, %{organization_id: organization_id, workspace_id: workspace_id} = record}
      when organization_id == session_context.organization_id and
             workspace_id == session_context.workspace_id ->
        {:ok, record}

      {:ok, _missing_or_cross_scope} ->
        {:error, :forbidden}

      {:error, _storage_error} ->
        {:error, :integration_storage_unavailable}
    end
  end

  defp review_comment_extension(id) do
    ReviewCommentExtension
    |> Ash.Query.filter(review_comment_id == ^id)
    |> then(&RecordLoader.read_one(ReviewCommentExtension, &1, authorize?: false))
    |> case do
      {:ok, nil} -> {:error, :forbidden}
      {:ok, extension} -> {:ok, extension}
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  defp check_run_extension(id) do
    CheckRunExtension
    |> Ash.Query.filter(check_run_id == ^id)
    |> then(&RecordLoader.read_one(CheckRunExtension, &1, authorize?: false))
    |> case do
      {:ok, nil} -> {:error, :forbidden}
      {:ok, extension} -> {:ok, extension}
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  defp require_version(%{provider_version: expected}, expected), do: :ok
  defp require_version(_record, _expected), do: {:error, {:stale_version, :provider_version}}

  defp require_installation_provenance(installation, %{pull_request_id: pull_request_id}) do
    if is_binary(pull_request_id) do
      SyncOutcome
      |> Ash.Query.filter(
        installation_id == ^installation.id and resource_type == "pull_request" and
          resource_id == ^pull_request_id and state in ["reconciled", "skipped_stale"]
      )
      |> Ash.Query.limit(1)
      |> then(&RecordLoader.read_one(SyncOutcome, &1, authorize?: false))
      |> case do
        {:ok, %SyncOutcome{}} -> :ok
        {:ok, nil} -> {:error, :forbidden}
        {:error, _storage_error} -> {:error, :integration_storage_unavailable}
      end
    else
      {:error, :forbidden}
    end
  end

  defp require_installation_provenance(_installation, _target), do: {:error, :forbidden}

  defp persist_and_enqueue(session_context, operation, installation, target, action_kind, attrs) do
    Repo.transaction(fn ->
      with {:ok, _locked_operation} <- Operations.lock_operation(operation.id),
           {:ok, existing} <- action_by_operation(operation.id) do
        case existing do
          nil ->
            create_action!(
              session_context,
              operation,
              installation,
              target,
              action_kind,
              attrs
            )

          action ->
            case validate_existing_action(action, session_context, action_kind) do
              {:ok, action} -> action
              {:error, error} -> Repo.rollback(error)
            end
        end
      else
        {:error, error} -> Repo.rollback(error)
      end
    end)
  end

  defp create_action!(session_context, operation, installation, target, action_kind, attrs) do
    target_type = if(action_kind == "review_reply", do: "review_comment", else: "check_run")

    input =
      attrs
      |> Map.drop([:installation_id, :review_comment_id, :check_run_id])
      |> Map.put(:target_node_id, target.node_id)

    action =
      Repo.ash_create!(OutboundAction, %{
        id: Ecto.UUID.generate(),
        installation_id: installation.id,
        operation_id: operation.id,
        principal_id: session_context.principal_id,
        organization_id: session_context.organization_id,
        workspace_id: session_context.workspace_id,
        action_kind: action_kind,
        target_type: target_type,
        target_id: target.record.id,
        expected_provider_version: attrs.expected_provider_version,
        input: input
      })

    case enqueue(action) do
      {:ok, _job} ->
        Audit.record!(
          operation,
          "github.#{action_kind}.request",
          "github_outbound_action",
          action.id
        )

        Revisions.record!(
          operation,
          "github_outbound_action",
          action.id,
          "github.#{action_kind}.request",
          "github.#{action_kind}.request"
        )

        action

      {:error, error} ->
        Repo.rollback(error)
    end
  end

  defp enqueue(action) do
    %{
      "action_id" => action.id,
      "organization_id" => action.organization_id,
      "workspace_id" => action.workspace_id
    }
    |> OutboundWorker.new()
    |> Oban.insert()
  end

  defp action_by_operation(operation_id) do
    OutboundAction
    |> Ash.Query.filter(operation_id == ^operation_id)
    |> then(&RecordLoader.read_one(OutboundAction, &1, authorize?: false))
  end

  defp required_uuid(attrs, key) do
    case fetch(attrs, key) do
      value when is_binary(value) ->
        case Ecto.UUID.cast(value) do
          {:ok, uuid} -> {:ok, uuid}
          :error -> {:error, {:invalid_field, key}}
        end

      _invalid ->
        {:error, {:invalid_field, key}}
    end
  end

  defp required_string(attrs, key) do
    case fetch(attrs, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> {:error, {:invalid_field, key}}
          normalized -> {:ok, normalized}
        end

      _invalid ->
        {:error, {:invalid_field, key}}
    end
  end

  defp required_raw_string(attrs, key) do
    case fetch(attrs, key) do
      value when is_binary(value) ->
        if String.trim(value) == "",
          do: {:error, {:invalid_field, key}},
          else: {:ok, value}

      _invalid ->
        {:error, {:invalid_field, key}}
    end
  end

  defp one_of_string(attrs, key, allowed) do
    with {:ok, value} <- required_string(attrs, key),
         true <- value in allowed do
      {:ok, value}
    else
      _invalid -> {:error, {:invalid_field, key}}
    end
  end

  defp fetch(attrs, key), do: Map.get(attrs, key, Map.get(attrs, to_string(key)))
end
