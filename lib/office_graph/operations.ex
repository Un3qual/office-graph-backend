defmodule OfficeGraph.Operations do
  @moduledoc """
  Public boundary for operation correlation and mutation context.
  """

  use Boundary, deps: [OfficeGraph.Authorization, OfficeGraph.Identity], exports: []

  require Ash.Query

  alias OfficeGraph.Identity
  alias OfficeGraph.Operations.{OperationCorrelation, SystemOperationRequest}

  @human_actions %{
    manual_intake_submit: "manual_intake.submit",
    proposed_change_apply: "proposed_change.apply",
    evidence_link: "evidence.link",
    verification_complete: "verification.complete",
    work_packet_create: "work_packet.create",
    work_packet_version_create: "work_packet.version.create",
    work_run_start: "work_run.start",
    execution_observation_record: "execution_observation.record",
    evidence_candidate_create: "evidence_candidate.create",
    evidence_accept: "evidence.accept",
    graph_relationship_create: "graph_relationship.create",
    graph_relationship_supersede: "graph_relationship.supersede",
    graph_relationship_archive: "graph_relationship.archive",
    graph_relationship_restore: "graph_relationship.restore",
    graph_relationship_cross_workspace: "graph_relationship.cross_workspace",
    github_installation_bind: "github.installation.bind",
    github_review_reply: "github.review.reply",
    github_check_update: "github.check.update",
    integration_reconcile: "integration.reconcile",
    verification_waive: "verification.waive",
    skeleton_read: "skeleton.read"
  }

  @system_actions %{
    integration_reconcile: "integration.reconcile",
    provider_webhook_receive: "provider.webhook.receive",
    system_conformance: "system.conformance"
  }

  def new_system_operation_request(attrs) do
    SystemOperationRequest.new(attrs, @system_actions)
  end

  def start_system_operation(%SystemOperationRequest{} = request) do
    with :ok <-
           OfficeGraph.Authorization.authorize_system_principal(
             request.principal_id,
             request.organization_id,
             request.workspace_id,
             request.action
           ),
         {:ok, operation} <- find_or_create_system_operation(request),
         :ok <- validate_system_replay(operation, request) do
      {:ok, operation}
    end
  end

  def start_system_operation(_request), do: {:error, :invalid_system_operation_request}

  def validate_system_operation(operation, action) when is_map(operation) and is_atom(action) do
    with {:ok, expected_action} <- Map.fetch(@system_actions, action),
         true <- operation.operation_kind == "system",
         true <- operation.action == expected_action,
         true <- is_binary(operation.organization_id),
         true <- is_binary(operation.principal_id),
         true <- is_binary(operation.authority_basis),
         true <- is_binary(operation.causation_key),
         true <- is_binary(operation.idempotency_scope),
         :ok <-
           OfficeGraph.Authorization.authorize_system_principal(
             operation.principal_id,
             operation.organization_id,
             operation.workspace_id,
             action
           ) do
      :ok
    else
      _invalid -> {:error, :forbidden}
    end
  end

  def validate_system_operation(_operation, _action), do: {:error, :forbidden}

  def start_command(session_context, action, idempotency_key, input)
      when is_binary(idempotency_key) and idempotency_key != "" do
    digest = command_input_digest(input)

    with {:ok, operation} <-
           start_operation(session_context, action,
             idempotency_key: idempotency_key,
             metadata: %{"command_input_digest" => digest}
           ),
         :ok <- validate_command_replay(operation, input) do
      {:ok, operation}
    end
  end

  def validate_command_replay(operation, input) when is_map(operation) do
    expected_digest =
      operation
      |> Map.get(:metadata, %{})
      |> command_digest_from_metadata()

    if expected_digest == command_input_digest(input) do
      :ok
    else
      {:error, {:command_idempotency_conflict, Map.fetch!(operation, :id)}}
    end
  end

  def validate_operation_context(session_context, operation)
      when is_map(session_context) and is_map(operation) do
    if operation.principal_id == session_context.principal_id and
         operation.session_id == session_context.session_id and
         operation.organization_id == session_context.organization_id and
         operation.workspace_id == session_context.workspace_id do
      :ok
    else
      {:error, :forbidden}
    end
  end

  def validate_operation_context(_session_context, _operation), do: {:error, :forbidden}

  def validate_operation_action(operation, expected_action) do
    case operation.action do
      ^expected_action -> :ok
      _other -> {:error, {:invalid_operation_action, operation.id, expected_action}}
    end
  end

  def read_command_target(resource, action, session_context, id) do
    resource
    |> Ash.Query.filter(id == ^id)
    |> Ash.Query.for_read(action)
    |> Ash.read_one(actor: session_context)
    |> case do
      {:ok, nil} -> {:error, {:not_found, resource, id}}
      result -> result
    end
  end

  def lock_scoped_target(resource, session_context, id) do
    resource
    |> Ash.Query.filter(
      id == ^id and organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, {:not_found, resource, id}}
      result -> result
    end
  end

  def lock_operation(operation_id) do
    OperationCorrelation
    |> Ash.Query.filter(id == ^operation_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, {:not_found, OperationCorrelation, operation_id}}
      {:ok, operation} -> {:ok, operation}
      {:error, error} -> {:error, error}
    end
  end

  def start_operation(session_context, action, attrs \\ []) do
    action_name = Map.fetch!(@human_actions, action)
    correlation_id = Keyword.get_lazy(attrs, :correlation_id, &Ecto.UUID.generate/0)
    idempotency_key = attrs[:idempotency_key]

    with :ok <- Identity.validate_session_context(session_context) do
      case existing_operation(session_context, action_name, idempotency_key) do
        {:ok, nil} ->
          create_operation(session_context, action_name, correlation_id, idempotency_key, attrs)

        {:ok, operation} ->
          {:ok, operation}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp find_or_create_system_operation(request) do
    case existing_system_operation(request) do
      {:ok, nil} -> create_system_operation(request)
      {:ok, operation} -> {:ok, operation}
      {:error, error} -> {:error, error}
    end
  end

  defp existing_system_operation(request) do
    OperationCorrelation
    |> Ash.Query.filter(
      operation_kind == "system" and
        organization_id == ^request.organization_id and
        principal_id == ^request.principal_id and
        action == ^request.action_name and
        idempotency_scope == ^request.idempotency_scope and
        idempotency_key == ^request.idempotency_key
    )
    |> scope_system_operation_workspace(request.workspace_id)
    |> Ash.read_one(authorize?: false)
  end

  defp scope_system_operation_workspace(query, nil),
    do: Ash.Query.filter(query, is_nil(workspace_id))

  defp scope_system_operation_workspace(query, workspace_id),
    do: Ash.Query.filter(query, workspace_id == ^workspace_id)

  defp create_system_operation(request) do
    attrs = %{
      id: Ecto.UUID.generate(),
      operation_kind: "system",
      principal_id: request.principal_id,
      session_id: nil,
      organization_id: request.organization_id,
      workspace_id: request.workspace_id,
      action: request.action_name,
      correlation_id: Ecto.UUID.generate(),
      idempotency_key: request.idempotency_key,
      authority_basis: request.authority_basis,
      causation_key: request.causation_key,
      idempotency_scope: request.idempotency_scope,
      credential_id: request.credential_id,
      subject_kind: request.subject_kind,
      subject_id: request.subject_id,
      subject_version: request.subject_version,
      metadata: %{}
    }

    OperationCorrelation
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create(
      authorize?: false,
      return_notifications?: true,
      upsert?: true,
      upsert_identity: :unique_system_idempotency,
      upsert_fields: []
    )
    |> case do
      {:ok, operation, _notifications} -> {:ok, operation}
      {:ok, operation} -> {:ok, operation}
      {:error, error} -> refetch_system_operation_after_conflict(request, error)
    end
  end

  defp refetch_system_operation_after_conflict(request, error) do
    case existing_system_operation(request) do
      {:ok, nil} -> {:error, error}
      {:ok, operation} -> {:ok, operation}
      {:error, _refetch_error} -> {:error, error}
    end
  end

  defp validate_system_replay(operation, request) do
    matching? =
      Enum.all?(
        [
          {:operation_kind, "system"},
          {:principal_id, request.principal_id},
          {:organization_id, request.organization_id},
          {:workspace_id, request.workspace_id},
          {:action, request.action_name},
          {:authority_basis, request.authority_basis},
          {:causation_key, request.causation_key},
          {:idempotency_scope, request.idempotency_scope},
          {:idempotency_key, request.idempotency_key},
          {:credential_id, request.credential_id},
          {:subject_kind, request.subject_kind},
          {:subject_id, request.subject_id},
          {:subject_version, request.subject_version}
        ],
        fn {field, expected} -> Map.get(operation, field) == expected end
      )

    if matching?,
      do: :ok,
      else: {:error, {:system_idempotency_conflict, operation.id}}
  end

  defp existing_operation(_session_context, _action_name, nil), do: {:ok, nil}

  defp existing_operation(session_context, action_name, idempotency_key) do
    OperationCorrelation
    |> Ash.Query.filter(
      organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id and
        principal_id == ^session_context.principal_id and
        session_id == ^session_context.session_id and
        action == ^action_name and
        idempotency_key == ^idempotency_key
    )
    |> Ash.read_one(authorize?: false)
  end

  defp create_operation(session_context, action_name, correlation_id, idempotency_key, attrs) do
    operation_attrs = %{
      id: Ecto.UUID.generate(),
      principal_id: session_context.principal_id,
      session_id: session_context.session_id,
      organization_id: session_context.organization_id,
      workspace_id: session_context.workspace_id,
      action: action_name,
      correlation_id: correlation_id,
      idempotency_key: idempotency_key,
      metadata: Map.new(attrs[:metadata] || %{})
    }

    OperationCorrelation
    |> Ash.Changeset.for_create(:create, operation_attrs)
    |> Ash.create(
      authorize?: false,
      return_notifications?: true,
      upsert?: not is_nil(idempotency_key),
      upsert_identity: :unique_idempotency_key,
      upsert_fields: []
    )
    |> case do
      {:ok, operation, _notifications} ->
        {:ok, operation}

      {:ok, operation} ->
        {:ok, operation}

      {:error, error} ->
        refetch_existing_operation_after_conflict(
          session_context,
          action_name,
          idempotency_key,
          error
        )
    end
  end

  defp refetch_existing_operation_after_conflict(
         _session_context,
         _action_name,
         nil,
         error
       ) do
    {:error, error}
  end

  defp refetch_existing_operation_after_conflict(
         session_context,
         action_name,
         idempotency_key,
         error
       ) do
    case existing_operation(session_context, action_name, idempotency_key) do
      {:ok, nil} -> {:error, error}
      {:ok, operation} -> {:ok, operation}
      {:error, _refetch_error} -> {:error, error}
    end
  end

  defp command_input_digest(input) do
    input
    |> normalize_command_input()
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp normalize_command_input(value) when is_map(value) and not is_struct(value) do
    value
    |> Enum.map(fn {key, nested_value} ->
      {to_string(key), normalize_command_input(nested_value)}
    end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp normalize_command_input(value) when is_list(value),
    do: Enum.map(value, &normalize_command_input/1)

  defp normalize_command_input(value), do: value

  defp command_digest_from_metadata(%{"command_input_digest" => digest}), do: digest
  defp command_digest_from_metadata(%{command_input_digest: digest}), do: digest

  defp command_digest_from_metadata(_metadata), do: nil
end
