defmodule OfficeGraph.Runs do
  @moduledoc """
  Public boundary for work-run, observation, and run-event records.
  """

  use Boundary,
    deps: [
      OfficeGraph.Authorization,
      OfficeGraph.Operations,
      OfficeGraph.Repo,
      OfficeGraph.WorkGraph,
      OfficeGraph.WorkPackets
    ],
    exports: []

  alias OfficeGraph.Authorization
  alias OfficeGraph.Repo
  alias OfficeGraph.Runs.{ExecutionObservation, Run, RunRequiredCheck}
  alias OfficeGraph.WorkPackets.WorkPacketRequiredCheck

  require Ash.Query

  @work_run_start_action "work_run.start"
  @execution_observation_record_action "execution_observation.record"

  def start_run(session_context, operation, packet_version, attrs) when is_map(attrs) do
    with :ok <- validate_operation_context(session_context, operation),
         :ok <- validate_operation_action(operation, @work_run_start_action),
         :ok <- validate_scope(session_context, packet_version),
         :ok <- validate_packet_version_ready(packet_version),
         :ok <-
           Authorization.authorize_operation(session_context, operation, :work_run_start,
             organization_id: session_context.organization_id
           ) do
      required_checks = packet_required_checks(packet_version.id)
      run_id = Ecto.UUID.generate()
      now = DateTime.utc_now()

      Repo.transaction(fn ->
        run =
          ash_create!(
            Run,
            %{
              id: run_id,
              organization_id: session_context.organization_id,
              workspace_id: session_context.workspace_id,
              work_packet_id: packet_version.work_packet_id,
              work_packet_version_id: packet_version.id,
              operation_id: operation.id,
              initiator_principal_id: session_context.principal_id,
              objective: packet_version.objective,
              authority_posture: attrs[:authority_posture],
              source_surface: attrs[:source_surface],
              reason: attrs[:reason],
              state: "running",
              aggregate_state: "running",
              execution_state: "pending",
              verification_state: "unverified",
              started_at: now
            }
          )

        run_required_checks =
          Enum.map(required_checks, fn required_check ->
            ash_create!(
              RunRequiredCheck,
              %{
                id: Ecto.UUID.generate(),
                run_id: run.id,
                verification_check_id: required_check.verification_check_id,
                organization_id: session_context.organization_id,
                workspace_id: session_context.workspace_id,
                state: "pending"
              }
            )
          end)

        %{run: run, required_checks: run_required_checks}
      end)
    end
    |> normalize_transaction_result()
  end

  def record_observation(session_context, operation, run, attrs) when is_map(attrs) do
    with :ok <- validate_operation_context(session_context, operation),
         :ok <- validate_operation_action(operation, @execution_observation_record_action),
         :ok <- validate_scope(session_context, run),
         :ok <-
           Authorization.authorize_operation(
             session_context,
             operation,
             :execution_observation_record,
             organization_id: session_context.organization_id
           ) do
      case existing_observation(session_context, attrs) do
        {:ok, nil} ->
          create_observation(session_context, operation, run, attrs)

        {:ok, observation} ->
          {:ok, %{observation: observation, run: run}}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  def set_run_verified(run) do
    run
    |> Ash.Changeset.for_update(:set_lifecycle_state, %{
      state: "verified",
      aggregate_state: "verified",
      execution_state: "completed",
      verification_state: "verified",
      completed_at: run.completed_at || DateTime.utc_now()
    })
    |> Ash.update(authorize?: false, return_notifications?: true)
    |> unwrap_ash_result()
  end

  def mark_required_check_satisfied(run_id, verification_check_id) do
    RunRequiredCheck
    |> Ash.Query.filter(run_id == ^run_id and verification_check_id == ^verification_check_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, required_check} ->
        required_check
        |> Ash.Changeset.for_update(:mark_satisfied, %{})
        |> Ash.update(authorize?: false, return_notifications?: true)
        |> unwrap_ash_result()

      {:error, error} ->
        {:error, error}
    end
  end

  def required_checks_for_run(run_id) do
    RunRequiredCheck
    |> Ash.Query.filter(run_id == ^run_id)
    |> Ash.read(authorize?: false)
  end

  defp create_observation(session_context, operation, run, attrs) do
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      observation =
        ash_create!(
          ExecutionObservation,
          %{
            id: Ecto.UUID.generate(),
            organization_id: session_context.organization_id,
            workspace_id: session_context.workspace_id,
            work_run_id: run.id,
            operation_id: operation.id,
            verification_check_id: attrs[:verification_check_id],
            graph_item_id: attrs[:graph_item_id],
            source_kind: attrs[:source_kind],
            source_identity: attrs[:source_identity],
            idempotency_key: attrs[:idempotency_key],
            observed_status: attrs[:observed_status],
            normalized_status: attrs[:normalized_status],
            source_recorded_at: attrs[:source_recorded_at],
            ingested_at: now,
            freshness_state: attrs[:freshness_state],
            trust_basis: attrs[:trust_basis],
            rationale: attrs[:rationale],
            metadata: Map.new(attrs[:metadata] || %{})
          }
        )

      run = update_run_after_observation!(run, observation)

      %{observation: observation, run: run}
    end)
    |> normalize_transaction_result()
  end

  defp update_run_after_observation!(run, %{normalized_status: "succeeded"}) do
    run
    |> Ash.Changeset.for_update(:set_lifecycle_state, %{
      state: "awaiting_verification",
      aggregate_state: "awaiting_verification",
      execution_state: "completed",
      verification_state: "missing_evidence",
      completed_at: DateTime.utc_now()
    })
    |> Ash.update!(authorize?: false, return_notifications?: true)
    |> unwrap_notification_result()
  end

  defp update_run_after_observation!(run, _observation) do
    run
    |> Ash.Changeset.for_update(:set_lifecycle_state, %{
      state: "running",
      aggregate_state: "running",
      execution_state: "pending",
      verification_state: run.verification_state || "unverified"
    })
    |> Ash.update!(authorize?: false, return_notifications?: true)
    |> unwrap_notification_result()
  end

  defp existing_observation(_session_context, %{idempotency_key: key}) when key in [nil, ""] do
    {:ok, nil}
  end

  defp existing_observation(session_context, attrs) do
    key = attrs[:idempotency_key]

    ExecutionObservation
    |> Ash.Query.filter(
      organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id and
        source_kind == ^attrs[:source_kind] and
        source_identity == ^attrs[:source_identity] and
        idempotency_key == ^key
    )
    |> Ash.read_one(authorize?: false)
  end

  defp packet_required_checks(packet_version_id) do
    WorkPacketRequiredCheck
    |> Ash.Query.filter(work_packet_version_id == ^packet_version_id)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!(authorize?: false)
  end

  defp validate_packet_version_ready(%{lifecycle_state: "ready"}), do: :ok

  defp validate_packet_version_ready(%{id: id}), do: {:error, {:packet_version_not_ready, id}}
  defp validate_packet_version_ready(_packet_version), do: {:error, :missing_packet_version}

  defp validate_scope(session_context, record) do
    if record.organization_id == session_context.organization_id and
         record.workspace_id == session_context.workspace_id do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp validate_operation_context(session_context, operation)
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

  defp validate_operation_context(_session_context, _operation), do: {:error, :forbidden}

  defp validate_operation_action(operation, expected_action) do
    case operation.action do
      ^expected_action -> :ok
      _other -> {:error, {:invalid_operation_action, operation.id, expected_action}}
    end
  end

  defp ash_create!(resource, attrs) do
    resource
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create!(authorize?: false, return_notifications?: true)
    |> unwrap_notification_result()
  end

  defp unwrap_ash_result({:ok, record, _notifications}), do: {:ok, record}
  defp unwrap_ash_result({:ok, record}), do: {:ok, record}
  defp unwrap_ash_result({:error, error}), do: {:error, error}

  defp unwrap_notification_result({record, _notifications}), do: record
  defp unwrap_notification_result(record), do: record

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, error}), do: {:error, error}
  defp normalize_transaction_result(other), do: other
end
