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
  alias OfficeGraph.Operations.OperationCorrelation
  alias OfficeGraph.Repo
  alias OfficeGraph.Runs.{ExecutionObservation, Run, RunRequiredCheck}
  alias OfficeGraph.WorkGraph.{EvidenceItem, GraphItem, VerificationCheck, VerificationResult}

  alias OfficeGraph.WorkPackets.{
    WorkPacket,
    WorkPacketRequiredCheck,
    WorkPacketSourceReference,
    WorkPacketVersion
  }

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
      create_run_records(session_context, operation, packet_version, attrs)
    end
  end

  def record_observation(session_context, operation, run, attrs) when is_map(attrs) do
    with :ok <- validate_operation_context(session_context, operation),
         :ok <- validate_operation_action(operation, @execution_observation_record_action),
         {:ok, run} <- reload_run(session_context, run),
         :ok <-
           Authorization.authorize_operation(
             session_context,
             operation,
             :execution_observation_record,
             organization_id: session_context.organization_id
           ) do
      create_observation(session_context, operation, run, attrs)
    end
  end

  def preflight_observation_idempotency(session_context, operation_idempotency_key, attrs)
      when is_map(attrs) do
    attrs = normalize_observation_attrs(attrs)

    with :ok <-
           Authorization.authorize(session_context, :execution_observation_record,
             organization_id: session_context.organization_id
           ) do
      case existing_observation(session_context, attrs) do
        {:ok, nil} ->
          :ok

        {:ok, observation} ->
          validate_preflight_observation_replay(
            session_context,
            observation,
            operation_idempotency_key,
            attrs
          )

        {:error, error} ->
          {:error, error}
      end
    end
  end

  def with_observation_idempotency_lock(session_context, attrs, fun)
      when is_map(attrs) and is_function(fun, 0) do
    attrs = normalize_observation_attrs(attrs)

    if is_nil(attrs[:idempotency_key]) do
      fun.()
    else
      lock_observation_idempotency_key!(session_context, attrs)
      fun.()
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
    attrs = normalize_observation_attrs(attrs)
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      _operation = lock_operation!(operation.id)
      run = lock_scoped_run!(session_context, run.id)

      case existing_observation_for_operation(session_context, operation) do
        {:ok, nil} ->
          validate_observation_references!(session_context, run, attrs)

          case existing_observation(session_context, attrs) do
            {:ok, nil} ->
              create_observation!(session_context, operation, run, attrs, now)

            {:ok, observation} ->
              replay_source_observation!(observation, run, attrs)

            {:error, error} ->
              Repo.rollback(error)
          end

        {:ok, observation} ->
          replay_operation_observation!(observation, run)

        {:error, error} ->
          Repo.rollback(error)
      end
    end)
    |> normalize_transaction_result()
  end

  defp create_observation!(session_context, operation, run, attrs, now) do
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
  end

  defp create_run_records(session_context, operation, packet_version, attrs) do
    run_id = Ecto.UUID.generate()
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      _operation = lock_operation!(operation.id)

      case existing_run_result(session_context, operation) do
        {:ok, nil} ->
          packet_version =
            case reload_packet_version(session_context, packet_version) do
              {:ok, packet_version} -> packet_version
              {:error, error} -> Repo.rollback(error)
            end

          case validate_packet_version_ready(packet_version) do
            :ok -> :ok
            {:error, error} -> Repo.rollback(error)
          end

          required_checks = packet_required_checks(packet_version.id)

          create_run_records!(
            session_context,
            operation,
            packet_version,
            attrs,
            required_checks,
            run_id,
            now
          )

        {:ok, run_result} ->
          run_result

        {:error, error} ->
          Repo.rollback(error)
      end
    end)
    |> normalize_transaction_result()
  end

  defp create_run_records!(
         session_context,
         operation,
         packet_version,
         attrs,
         required_checks,
         run_id,
         now
       ) do
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
  end

  defp update_run_after_observation!(run, %{normalized_status: "succeeded"}) do
    cond do
      run_failed?(run) ->
        run

      failed_observations_for_run?(run.id) ->
        update_run_failed!(run)

      run_verified?(run) ->
        run

      true ->
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
  end

  defp update_run_after_observation!(run, _observation) do
    update_run_failed!(run)
  end

  defp update_run_failed!(run) do
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

  defp existing_observation_for_operation(session_context, operation) do
    ExecutionObservation
    |> Ash.Query.filter(
      organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id and
        operation_id == ^operation.id
    )
    |> Ash.read_one(authorize?: false)
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
      observation.normalized_status == attrs[:normalized_status] and
      observation.freshness_state == attrs[:freshness_state] and
      observation.trust_basis == attrs[:trust_basis]
  end

  defp validate_preflight_observation_replay(
         session_context,
         observation,
         operation_idempotency_key,
         _attrs
       ) do
    with {:ok, true} <-
           observation_operation_idempotency_key_matches?(
             session_context,
             observation,
             operation_idempotency_key
           ) do
      :ok
    else
      _conflict -> {:error, {:observation_idempotency_conflict, observation.id}}
    end
  end

  defp observation_operation_idempotency_key_matches?(
         session_context,
         observation,
         operation_idempotency_key
       ) do
    OperationCorrelation
    |> Ash.Query.filter(
      id == ^observation.operation_id and
        organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id and
        principal_id == ^session_context.principal_id and
        session_id == ^session_context.session_id and
        action == ^@execution_observation_record_action and
        idempotency_key == ^operation_idempotency_key
    )
    |> Ash.exists?(authorize?: false)
    |> then(&{:ok, &1})
  end

  defp replay_operation_observation!(observation, run) do
    if observation.work_run_id == run.id do
      %{observation: observation, run: run}
    else
      Repo.rollback({:observation_operation_conflict, observation.id})
    end
  end

  defp replay_source_observation!(observation, run, attrs) do
    if same_observation_replay?(observation, run, attrs) do
      %{observation: observation, run: run}
    else
      Repo.rollback({:observation_idempotency_conflict, observation.id})
    end
  end

  defp normalize_observation_attrs(attrs) do
    Map.put(attrs, :idempotency_key, normalize_idempotency_key(attrs[:idempotency_key]))
  end

  defp normalize_idempotency_key(value) when is_binary(value) do
    if String.trim(value) == "" do
      nil
    else
      value
    end
  end

  defp normalize_idempotency_key(value), do: value

  defp lock_observation_idempotency_key!(session_context, attrs) do
    lock_key =
      [
        session_context.organization_id,
        session_context.workspace_id,
        attrs[:source_kind],
        attrs[:source_identity],
        attrs[:idempotency_key]
      ]
      |> Enum.join(":")

    Repo.query!("SELECT pg_advisory_xact_lock(98301, hashtext($1))", [lock_key])
  end

  defp failed_observations_for_run?(run_id) do
    ExecutionObservation
    |> Ash.Query.filter(work_run_id == ^run_id and normalized_status != "succeeded")
    |> Ash.exists?(authorize?: false)
  end

  defp lock_operation!(operation_id) do
    OperationCorrelation
    |> Ash.Query.filter(id == ^operation_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> Repo.rollback({:not_found, OperationCorrelation, operation_id})
      {:ok, operation} -> operation
      {:error, error} -> Repo.rollback(error)
    end
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

  defp run_verified?(run) do
    run.state == "verified" or run.aggregate_state == "verified" or
      run.verification_state == "verified"
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

  defp reload_run(_session_context, nil), do: {:error, :missing_work_run}

  defp reload_run(session_context, %{id: id}) do
    fetch_scoped(Run, session_context, id)
  end

  defp reload_run(_session_context, _run), do: {:error, :missing_work_run}

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

  defp validate_observation_references!(session_context, run, attrs) do
    case validate_observation_references(session_context, run, attrs) do
      :ok -> :ok
      {:error, error} -> Repo.rollback(error)
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

  defp validate_observation_graph_item(_run, nil, nil), do: :ok

  defp validate_observation_graph_item(run, nil, graph_item) do
    if graph_item_belongs_to_run?(run, graph_item.id) do
      :ok
    else
      {:error, {:graph_item_not_required, run.id, graph_item.id}}
    end
  end

  defp validate_observation_graph_item(_run, _verification_check, nil), do: :ok

  defp validate_observation_graph_item(run, verification_check, graph_item) do
    if graph_item.id == verification_check.graph_item_id do
      :ok
    else
      {:error, {:graph_item_not_required, run.id, graph_item.id}}
    end
  end

  defp graph_item_belongs_to_run?(run, graph_item_id) do
    packet_source_graph_item?(run.work_packet_version_id, graph_item_id) or
      required_check_graph_item?(run.id, graph_item_id)
  end

  defp packet_source_graph_item?(work_packet_version_id, graph_item_id) do
    WorkPacketSourceReference
    |> Ash.Query.filter(
      work_packet_version_id == ^work_packet_version_id and graph_item_id == ^graph_item_id
    )
    |> Ash.exists?(authorize?: false)
  end

  defp required_check_graph_item?(run_id, graph_item_id) do
    case read_run_required_checks(run_id) do
      {:ok, required_checks} ->
        Enum.any?(required_checks, fn required_check ->
          check_id = required_check.verification_check_id

          VerificationCheck
          |> Ash.Query.filter(id == ^check_id and graph_item_id == ^graph_item_id)
          |> Ash.exists?(authorize?: false)
        end)

      {:error, _error} ->
        false
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

  defp lock_scoped_run!(session_context, run_id) do
    Run
    |> Ash.Query.filter(id == ^run_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} ->
        Repo.rollback({:not_found, Run, run_id})

      {:ok, run} ->
        case validate_scope(session_context, run) do
          :ok -> run
          {:error, error} -> Repo.rollback(error)
        end

      {:error, error} ->
        Repo.rollback(error)
    end
  end

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
