defmodule OfficeGraph.GitHubIntegration.OutboundCommands do
  @moduledoc false

  @behaviour Ash.Resource.Actions.Implementation

  alias OfficeGraph.{Audit, Authorization, CommandSupport, Operations, Revisions}

  alias OfficeGraph.GitHubIntegration.{
    ActionSupport,
    Installation,
    OutboundAction,
    OutboundWorker,
    PermissionEntry,
    RecordLoader,
    StorageResult,
    SyncOutcome
  }

  alias OfficeGraph.SoftwareProving.{CheckRun, ReviewComment}

  alias OfficeGraph.SoftwareProving.GitHub.{
    CheckRunExtension,
    ReviewCommentExtension
  }

  require Ash.Query

  @impl true
  def run(input, [mode: :persist], %{actor: session_context}) when is_map(session_context) do
    case persist_records(session_context, input.arguments) do
      {:ok, action} -> {:ok, action}
      {:error, error} -> ActionSupport.rollback(OutboundAction, error)
    end
  end

  def run(_input, _opts, _context), do: {:error, :forbidden}

  def reply_to_review(session_context, operation, attrs) when is_map(attrs) do
    with :ok <- Operations.validate_operation_context(session_context, operation),
         :ok <- Operations.validate_operation_action(operation, "github.review.reply"),
         :ok <- Operations.validate_command_replay(operation, attrs),
         {:ok, normalized} <- normalize_reply(attrs) do
      persist_and_enqueue(
        session_context,
        operation,
        "review_reply",
        normalized
      )
    end
  end

  def reply_to_review(_session_context, _operation, _attrs), do: {:error, :forbidden}

  def update_check(session_context, operation, attrs) when is_map(attrs) do
    with :ok <- Operations.validate_operation_context(session_context, operation),
         :ok <- Operations.validate_operation_action(operation, "github.check.update"),
         :ok <- Operations.validate_command_replay(operation, attrs),
         {:ok, normalized} <- normalize_check(attrs) do
      persist_and_enqueue(
        session_context,
        operation,
        "check_update",
        normalized
      )
    end
  end

  def update_check(_session_context, _operation, _attrs), do: {:error, :forbidden}

  defp persist_and_enqueue(session_context, operation, action_kind, normalized) do
    result =
      StorageResult.run(fn ->
        attrs =
          normalized
          |> Map.new()
          |> Map.put(:operation_id, operation.id)
          |> Map.put(:action_kind, action_kind)

        OutboundAction
        |> Ash.ActionInput.for_action(:persist_outbound_contract, attrs)
        |> Ash.run_action(actor: session_context, authorize?: false)
        |> ActionSupport.normalize_action_result()
        |> preserve_command_error()
      end)

    case result do
      {:ok, {:command_error, error}} -> {:error, error}
      result -> result
    end
  end

  defp preserve_command_error({:error, {kind, _detail} = error})
       when kind in [:authorization, :stale_version],
       do: {:ok, {:command_error, error}}

  defp preserve_command_error(result), do: result

  defp persist_records(session_context, attrs) do
    with {:ok, operation} <- Operations.lock_operation(attrs.operation_id),
         {:ok, existing} <- action_by_operation(operation.id) do
      case existing do
        nil -> create_for_kind(session_context, operation, attrs)
        action -> replay_action(session_context, operation, action, attrs.action_kind)
      end
    end
  end

  defp replay_action(session_context, operation, action, action_kind) do
    with :ok <-
           authorize(
             session_context,
             operation,
             capability(action_kind),
             action.workspace_id
           ) do
      validate_existing_action(action, session_context, action_kind)
    end
  end

  defp create_for_kind(session_context, operation, %{action_kind: "review_reply"} = attrs) do
    with {:ok, installation} <- active_installation(session_context, attrs.installation_id),
         :ok <-
           authorize(
             session_context,
             operation,
             :github_review_reply,
             installation.workspace_id
           ),
         :ok <- require_permission(installation, "pull_requests"),
         {:ok, target} <- review_target(installation, attrs),
         :ok <- require_version(target.record, attrs.expected_provider_version),
         :ok <- require_installation_provenance(installation, target.record) do
      create_action(session_context, operation, installation, target, attrs)
    end
  end

  defp create_for_kind(session_context, operation, %{action_kind: "check_update"} = attrs) do
    with {:ok, installation} <- active_installation(session_context, attrs.installation_id),
         :ok <-
           authorize(
             session_context,
             operation,
             :github_check_update,
             installation.workspace_id
           ),
         :ok <- require_permission(installation, "checks"),
         {:ok, target} <- check_target(installation, attrs),
         :ok <- require_version(target.record, attrs.expected_provider_version),
         :ok <- require_installation_provenance(installation, target.record) do
      create_action(session_context, operation, installation, target, attrs)
    end
  end

  defp create_for_kind(_session_context, _operation, _attrs), do: {:error, :forbidden}

  defp capability("review_reply"), do: :github_review_reply
  defp capability("check_update"), do: :github_check_update

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
              organization_id == session_context.organization_id do
    if workspace_id in [nil, session_context.workspace_id],
      do: {:ok, action},
      else: {:error, :forbidden}
  end

  defp validate_existing_action(_action, _session_context, _action_kind),
    do: {:error, :forbidden}

  defp authorize(session_context, operation, capability, workspace_id) do
    StorageResult.run(fn ->
      Authorization.authorize_operation(session_context, operation, capability,
        organization_id: session_context.organization_id,
        workspace_id: workspace_id
      )
    end)
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
    query =
      Installation
      |> Ash.Query.filter(id == ^installation_id)
      |> Ash.Query.lock(:for_update)

    case RecordLoader.read_one(Installation, query, authorize?: false) do
      {:ok,
       %Installation{
         lifecycle_state: "active",
         organization_id: organization_id,
         workspace_id: workspace_id
       } = installation}
      when organization_id == session_context.organization_id and
             workspace_id in [nil, session_context.workspace_id] ->
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
    |> Ash.Query.lock(:for_update)
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

  defp review_target(installation, normalized) do
    with {:ok, record} <-
           scoped_target(ReviewComment, normalized.review_comment_id, installation),
         :ok <- require_replyable_review_comment(record),
         {:ok, extension} <- review_comment_extension(record.id) do
      {:ok, %{record: record, node_id: extension.node_id}}
    end
  end

  defp require_replyable_review_comment(%ReviewComment{
         state: "published",
         parent_comment_id: nil
       }),
       do: :ok

  defp require_replyable_review_comment(_record), do: {:error, :forbidden}

  defp check_target(installation, normalized) do
    with {:ok, record} <- scoped_target(CheckRun, normalized.check_run_id, installation),
         {:ok, extension} <- check_run_extension(record.id) do
      {:ok, %{record: record, node_id: extension.node_id}}
    end
  end

  defp scoped_target(resource, id, installation) do
    query =
      resource
      |> Ash.Query.filter(id == ^id)
      |> Ash.Query.lock(:for_update)

    case RecordLoader.read_one(resource, query, authorize?: false) do
      {:ok, %{organization_id: organization_id, workspace_id: workspace_id} = record}
      when organization_id == installation.organization_id and
             workspace_id == installation.workspace_id ->
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
    |> Ash.Query.lock(:for_update)
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
    |> Ash.Query.lock(:for_update)
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
      |> Ash.Query.lock(:for_update)
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

  defp create_action(session_context, operation, installation, target, attrs) do
    target_type =
      if(attrs.action_kind == "review_reply", do: "review_comment", else: "check_run")

    command_attrs =
      case attrs.action_kind do
        "review_reply" ->
          %{
            target_node_id: target.node_id,
            reply_body: attrs.body
          }

        "check_update" ->
          %{
            target_node_id: target.node_id,
            check_status: attrs.status,
            check_conclusion: attrs.conclusion,
            details_url: attrs.details_url
          }
      end

    create_attrs =
      Map.merge(
        %{
          installation_id: installation.id,
          operation_id: operation.id,
          principal_id: session_context.principal_id,
          organization_id: session_context.organization_id,
          workspace_id: installation.workspace_id,
          action_kind: attrs.action_kind,
          target_type: target_type,
          target_id: target.record.id,
          expected_provider_version: attrs.expected_provider_version
        },
        command_attrs
      )

    with {:ok, action} <-
           OutboundAction
           |> Ash.Changeset.for_create(:create, create_attrs)
           |> Ash.create(authorize?: false, return_notifications?: true)
           |> CommandSupport.normalize_ash_write(),
         {:ok, _job} <- enqueue(action) do
      event = "github.#{attrs.action_kind}.request"

      _audit =
        Audit.record!(
          operation,
          event,
          "github_outbound_action",
          action.id
        )

      _revision =
        Revisions.record!(
          operation,
          "github_outbound_action",
          action.id,
          event,
          event
        )

      {:ok, action}
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
    |> Ash.Query.lock(:for_update)
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
