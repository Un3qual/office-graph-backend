defmodule OfficeGraph.Operations do
  @moduledoc """
  Public boundary for operation correlation and mutation context.
  """

  use Boundary, deps: [OfficeGraph.Identity], exports: []

  require Ash.Query

  alias OfficeGraph.Identity
  alias OfficeGraph.Operations.OperationCorrelation

  @actions %{
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
    verification_waive: "verification.waive",
    skeleton_read: "skeleton.read"
  }

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
    action_name = Map.fetch!(@actions, action)
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
