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
    skeleton_read: "skeleton.read"
  }

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
      upsert?: not is_nil(idempotency_key),
      upsert_identity: :unique_idempotency_key,
      upsert_fields: []
    )
    |> case do
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
end
