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
  alias OfficeGraph.WorkGraph.{EvidenceItem, GraphItem, VerificationCheck, VerificationResult}
  alias OfficeGraph.WorkPackets.{WorkPacket, WorkPacketRequiredCheck, WorkPacketVersion}

  require Ash.Query

  @work_run_start_action "work_run.start"
  @execution_observation_record_action "execution_observation.record"

  def start_run(session_context, operation, packet_version, attrs) when is_map(attrs) do
    with :ok <- validate_operation_context(session_context, operation),
         :ok <- validate_operation_action(operation, @work_run_start_action),
         :ok <-
           Authorization.authorize_operation(session_context, operation, :work_run_start,
             organization_id: session_context.organization_id
           ) do
      with {:ok, nil} <- existing_run_result(session_context, operation),
           {:ok, packet_version} <- reload_packet_version(session_context, packet_version),
           :ok <- validate_packet_version_ready(packet_version) do
        create_run_records(session_context, operation, packet_version, attrs)
      else
        {:ok, run_result} -> {:ok, run_result}
        {:error, error} -> {:error, error}
      end
    end
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
           ),
         :ok <- validate_observation_references(session_context, run, attrs) do
      case existing_observation(session_context, attrs) do
        {:ok, nil} ->
          create_observation(session_context, operation, run, attrs)

        {:ok, observation} ->
          if same_observation_replay?(observation, run, attrs) do
            {:ok, %{observation: observation, run: run}}
          else
            {:error, {:observation_idempotency_conflict, observation.id}}
          end

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

  def set_run_verified_if_all_required_checks_satisfied(run) do
    Repo.transaction(fn ->
      locked_run = lock_run!(run.id)
      required_checks = lock_required_checks_for_run!(locked_run.id)

      maybe_set_run_verified!(locked_run, required_checks)
    end)
    |> normalize_transaction_result()
  end

  def set_run_verification_failed(run) do
    run
    |> Ash.Changeset.for_update(:set_lifecycle_state, %{
      state: "failed",
      aggregate_state: "failed",
      execution_state: run.execution_state || "completed",
      verification_state: "failed",
      completed_at: run.completed_at || DateTime.utc_now()
    })
    |> Ash.update(authorize?: false, return_notifications?: true)
    |> unwrap_ash_result()
  end

  def mark_required_check_satisfied(run_id, verification_check_id) do
    Repo.transaction(fn ->
      _run = lock_run!(run_id)
      mark_required_check_satisfied_in_locked_run!(run_id, verification_check_id)
    end)
    |> normalize_transaction_result()
  end

  def satisfy_required_check_and_verify_run(run, verification_check_id) do
    Repo.transaction(fn ->
      locked_run = lock_run!(run.id)

      _required_check =
        mark_required_check_satisfied_in_locked_run!(locked_run.id, verification_check_id)

      required_checks = lock_required_checks_for_run!(locked_run.id)
      maybe_set_run_verified!(locked_run, required_checks)
    end)
    |> normalize_transaction_result()
  end

  def required_checks_for_run(run_id) do
    RunRequiredCheck
    |> Ash.Query.filter(run_id == ^run_id)
    |> Ash.read(authorize?: false)
  end

  def get_summary(session_context, run_id) do
    with :ok <-
           Authorization.authorize(session_context, :skeleton_read,
             organization_id: session_context.organization_id
           ),
         {:ok, run} <- fetch_scoped(Run, session_context, run_id),
         {:ok, packet} <- fetch_scoped(WorkPacket, session_context, run.work_packet_id),
         {:ok, packet_version} <-
           fetch_scoped(WorkPacketVersion, session_context, run.work_packet_version_id),
         {:ok, required_checks} <- read_run_required_checks(run.id),
         {:ok, observations} <- read_observations(run.id),
         {:ok, evidence_items} <- read_evidence_items(run.id),
         {:ok, verification_results} <- read_verification_results(run.id) do
      {:ok,
       %{
         packet: packet,
         packet_version: packet_version,
         run: run,
         required_checks: required_checks,
         observations: observations,
         evidence_items: evidence_items,
         verification_results: verification_results,
         missing_evidence: missing_evidence(required_checks, verification_results)
       }}
    end
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

  defp create_run_records(session_context, operation, packet_version, attrs) do
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
      state: "failed",
      aggregate_state: "failed",
      execution_state: "failed",
      verification_state: "failed",
      completed_at: DateTime.utc_now()
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

  defp same_observation_replay?(observation, run, attrs) do
    observation.work_run_id == run.id and
      observation.verification_check_id == attrs[:verification_check_id] and
      observation.graph_item_id == attrs[:graph_item_id] and
      observation.observed_status == attrs[:observed_status] and
      observation.normalized_status == attrs[:normalized_status]
  end

  defp lock_run!(run_id) do
    Run
    |> Ash.Query.filter(id == ^run_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> Repo.rollback({:not_found, Run, run_id})
      {:ok, run} -> run
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp lock_required_checks_for_run!(run_id) do
    RunRequiredCheck
    |> Ash.Query.filter(run_id == ^run_id)
    |> Ash.Query.sort(id: :asc)
    |> Ash.Query.lock(:for_update)
    |> Ash.read!(authorize?: false)
  end

  defp mark_required_check_satisfied_in_locked_run!(run_id, verification_check_id) do
    RunRequiredCheck
    |> Ash.Query.filter(run_id == ^run_id and verification_check_id == ^verification_check_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} ->
        nil

      {:ok, required_check} ->
        required_check
        |> Ash.Changeset.for_update(:mark_satisfied, %{})
        |> Ash.update(authorize?: false, return_notifications?: true)
        |> case do
          {:ok, required_check, _notifications} -> required_check
          {:ok, required_check} -> required_check
          {:error, error} -> Repo.rollback(error)
        end

      {:error, error} ->
        Repo.rollback(error)
    end
  end

  defp maybe_set_run_verified!(run, required_checks) do
    cond do
      run_failed?(run) ->
        run

      required_checks != [] and Enum.all?(required_checks, &(&1.state == "satisfied")) ->
        set_run_verified!(run)

      true ->
        run
    end
  end

  defp set_run_verified!(run) do
    case set_run_verified(run) do
      {:ok, run} -> run
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp run_failed?(run) do
    run.state == "failed" or run.aggregate_state == "failed" or run.execution_state == "failed" or
      run.verification_state == "failed"
  end

  defp packet_required_checks(packet_version_id) do
    WorkPacketRequiredCheck
    |> Ash.Query.filter(work_packet_version_id == ^packet_version_id)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!(authorize?: false)
  end

  defp existing_run_result(session_context, operation) do
    Run
    |> Ash.Query.filter(
      organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id and
        operation_id == ^operation.id
    )
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, run} ->
        with {:ok, required_checks} <- read_run_required_checks(run.id) do
          {:ok, %{run: run, required_checks: required_checks}}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp reload_packet_version(_session_context, nil), do: {:error, :missing_packet_version}

  defp reload_packet_version(session_context, %{id: id}) do
    fetch_scoped(WorkPacketVersion, session_context, id)
  end

  defp reload_packet_version(_session_context, _packet_version),
    do: {:error, :missing_packet_version}

  defp validate_packet_version_ready(%{lifecycle_state: "ready"}), do: :ok

  defp validate_packet_version_ready(%{id: id}), do: {:error, {:packet_version_not_ready, id}}
  defp validate_packet_version_ready(_packet_version), do: {:error, :missing_packet_version}

  defp validate_observation_references(session_context, run, attrs) do
    with {:ok, verification_check} <-
           validate_observation_verification_check(
             session_context,
             run,
             attrs[:verification_check_id]
           ),
         {:ok, graph_item} <-
           validate_optional_graph_item(session_context, attrs[:graph_item_id]),
         :ok <- validate_observation_graph_item(run, verification_check, graph_item) do
      :ok
    end
  end

  defp validate_observation_verification_check(_session_context, _run, nil), do: {:ok, nil}

  defp validate_observation_verification_check(session_context, run, verification_check_id) do
    with {:ok, verification_check} <-
           fetch_scoped(VerificationCheck, session_context, verification_check_id),
         true <- run_requires_check?(run.id, verification_check.id) do
      {:ok, verification_check}
    else
      false -> {:error, {:verification_check_not_required, run.id, verification_check_id}}
      error -> error
    end
  end

  defp validate_optional_graph_item(_session_context, nil), do: {:ok, nil}

  defp validate_optional_graph_item(session_context, graph_item_id) do
    fetch_scoped(GraphItem, session_context, graph_item_id)
  end

  defp validate_observation_graph_item(_run, nil, _graph_item), do: :ok
  defp validate_observation_graph_item(_run, _verification_check, nil), do: :ok

  defp validate_observation_graph_item(run, verification_check, graph_item) do
    if graph_item.id == verification_check.graph_item_id do
      :ok
    else
      {:error, {:graph_item_not_required, run.id, graph_item.id}}
    end
  end

  defp run_requires_check?(run_id, verification_check_id) do
    RunRequiredCheck
    |> Ash.Query.filter(run_id == ^run_id and verification_check_id == ^verification_check_id)
    |> Ash.exists?(authorize?: false)
  end

  defp read_run_required_checks(run_id) do
    RunRequiredCheck
    |> Ash.Query.filter(run_id == ^run_id)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read(authorize?: false)
  end

  defp read_observations(run_id) do
    ExecutionObservation
    |> Ash.Query.filter(work_run_id == ^run_id)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read(authorize?: false)
  end

  defp read_evidence_items(run_id) do
    EvidenceItem
    |> Ash.Query.filter(work_run_id == ^run_id)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read(authorize?: false)
  end

  defp read_verification_results(run_id) do
    VerificationResult
    |> Ash.Query.filter(work_run_id == ^run_id)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read(authorize?: false)
  end

  defp missing_evidence(required_checks, verification_results) do
    passed_check_ids =
      verification_results
      |> Enum.filter(&(&1.result == "passed"))
      |> MapSet.new(& &1.verification_check_id)

    required_checks
    |> Enum.reject(&MapSet.member?(passed_check_ids, &1.verification_check_id))
    |> Enum.map(fn required_check ->
      %{
        verification_check_id: required_check.verification_check_id,
        reason: "missing_accepted_evidence"
      }
    end)
  end

  defp fetch_scoped(resource, session_context, id) do
    resource
    |> Ash.Query.filter(id == ^id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} ->
        {:error, {:not_found, resource, id}}

      {:ok, record} ->
        case validate_scope(session_context, record) do
          :ok -> {:ok, record}
          error -> error
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp validate_scope(_session_context, nil), do: {:error, :missing_packet_version}

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
    |> Ash.create(authorize?: false, return_notifications?: true)
    |> case do
      {:ok, record, notifications} -> unwrap_notification_result({record, notifications})
      {:ok, record} -> record
      {:error, error} -> Repo.rollback(error)
    end
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
