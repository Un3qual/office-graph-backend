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
  alias OfficeGraph.Operations
  alias OfficeGraph.Operations.OperationCorrelation
  alias OfficeGraph.Repo
  alias OfficeGraph.Runs.{ExecutionObservation, Run, RunRequiredCheck}
  alias OfficeGraph.WorkGraph.{EvidenceItem, VerificationResult}

  alias OfficeGraph.WorkPackets.{
    WorkPacket,
    WorkPacketRequiredCheck,
    WorkPacketVersion
  }

  require Ash.Query

  @work_run_start_action "work_run.start"
  @execution_observation_record_action "execution_observation.record"

  def graphql_node_type(%Run{}), do: :work_run
  def graphql_node_type(_value), do: nil

  def graphql_node(session_context, :work_run, id) do
    Ash.get(Run, id, actor: session_context, not_found_error?: false)
  end

  def graphql_node(_session_context, _type, _id), do: {:ok, nil}

  def start_run(session_context, operation, packet_version, attrs) when is_map(attrs) do
    with :ok <- Operations.validate_operation_context(session_context, operation),
         :ok <- Operations.validate_operation_action(operation, @work_run_start_action),
         :ok <-
           Authorization.authorize_operation(session_context, operation, :work_run_start,
             organization_id: session_context.organization_id
           ) do
      create_run_records(session_context, operation, packet_version, attrs)
    end
  end

  def record_observation(session_context, operation, run, attrs) when is_map(attrs) do
    with :ok <- Operations.validate_operation_context(session_context, operation),
         :ok <-
           Operations.validate_operation_action(operation, @execution_observation_record_action),
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

  def apply_accepted_verification_result(run, %{result: "passed"} = verification_result) do
    Repo.transaction(fn ->
      locked_run = lock_run!(run.id)

      _required_check =
        mark_required_check_satisfied_in_locked_run!(
          locked_run.id,
          verification_result.verification_check_id
        )

      required_checks = lock_required_checks_for_run!(locked_run.id)
      maybe_set_run_verified!(locked_run, required_checks)
    end)
    |> normalize_transaction_result()
  end

  def apply_accepted_verification_result(run, %{result: "failed"}) do
    Repo.transaction(fn ->
      locked_run = lock_run!(run.id)

      if run_verified?(locked_run) do
        Repo.rollback({:work_run_already_verified, locked_run.id})
      else
        set_run_verification_failed!(locked_run)
      end
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
         {:ok, required_checks} <- read_run_required_checks(run),
         {:ok, observations} <- read_observations(run),
         {:ok, evidence_items} <- read_evidence_items(run),
         {:ok, verification_results} <- read_verification_results(run) do
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

    Repo.transaction(fn ->
      maybe_lock_observation_idempotency_key!(session_context, attrs)
      _operation = lock_operation!(operation.id)
      run = lock_scoped_run!(session_context, run.id)

      case existing_observation_for_operation(session_context, operation) do
        {:ok, nil} ->
          case existing_observation(session_context, attrs) do
            {:ok, nil} ->
              create_observation!(session_context, operation, run, attrs)

            {:ok, observation} ->
              replay_source_observation!(observation, run, attrs)

            {:error, error} ->
              Repo.rollback(error)
          end

        {:ok, observation} ->
          replay_operation_observation!(observation, run, attrs)

        {:error, error} ->
          Repo.rollback(error)
      end
    end)
    |> normalize_transaction_result()
  end

  defp create_observation!(session_context, operation, run, attrs) do
    observation =
      Repo.ash_create!(
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

    Repo.transaction(fn ->
      _operation = lock_operation!(operation.id)

      packet_version =
        case reload_packet_version(session_context, packet_version) do
          {:ok, packet_version} -> packet_version
          {:error, error} -> Repo.rollback(error)
        end

      case existing_run_result(session_context, operation, packet_version, attrs) do
        {:ok, nil} ->
          required_checks = packet_required_checks(packet_version)

          create_run_records!(
            session_context,
            operation,
            packet_version,
            attrs,
            required_checks,
            run_id
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
         run_id
       ) do
    run =
      Repo.ash_create!(
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
          reason: attrs[:reason]
        }
      )

    run_required_checks =
      Enum.map(required_checks, fn required_check ->
        Repo.ash_create!(
          RunRequiredCheck,
          %{
            id: Ecto.UUID.generate(),
            run_id: run.id,
            verification_check_id: required_check.verification_check_id,
            organization_id: session_context.organization_id,
            workspace_id: session_context.workspace_id
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
    cond do
      run_verified?(run) -> run
      run_failed?(run) -> run
      true -> update_run_failed!(run)
    end
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
      observation.source_kind == attrs[:source_kind] and
      observation.source_identity == attrs[:source_identity] and
      observation.idempotency_key == attrs[:idempotency_key] and
      observation.verification_check_id == attrs[:verification_check_id] and
      observation.graph_item_id == attrs[:graph_item_id] and
      observation.observed_status == attrs[:observed_status] and
      observation.normalized_status == attrs[:normalized_status] and
      observation.source_recorded_at == attrs[:source_recorded_at] and
      observation.freshness_state == attrs[:freshness_state] and
      observation.trust_basis == attrs[:trust_basis] and
      observation.rationale == attrs[:rationale] and
      observation.metadata == Map.new(attrs[:metadata] || %{})
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

  defp replay_operation_observation!(observation, run, attrs) do
    if same_observation_replay?(observation, run, attrs) do
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

  defp maybe_lock_observation_idempotency_key!(_session_context, %{idempotency_key: nil}), do: :ok

  defp maybe_lock_observation_idempotency_key!(session_context, attrs) do
    lock_observation_idempotency_key!(session_context, attrs)
  end

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
    case Operations.lock_operation(operation_id) do
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
    run
    |> Ash.Changeset.for_update(:set_lifecycle_state, %{
      state: "verified",
      aggregate_state: "verified",
      execution_state: "completed",
      verification_state: "verified",
      completed_at: run.completed_at || DateTime.utc_now()
    })
    |> Ash.update!(authorize?: false, return_notifications?: true)
    |> unwrap_notification_result()
  end

  defp set_run_verification_failed!(run) do
    run
    |> Ash.Changeset.for_update(:set_lifecycle_state, %{
      state: "failed",
      aggregate_state: "failed",
      execution_state: run.execution_state || "completed",
      verification_state: "failed",
      completed_at: run.completed_at || DateTime.utc_now()
    })
    |> Ash.update!(authorize?: false, return_notifications?: true)
    |> unwrap_notification_result()
  end

  defp run_failed?(run) do
    run.state == "failed" or run.aggregate_state == "failed" or run.execution_state == "failed" or
      run.verification_state == "failed"
  end

  defp run_verified?(run) do
    run.state == "verified" or run.aggregate_state == "verified" or
      run.verification_state == "verified"
  end

  defp packet_required_checks(packet_version) do
    WorkPacketRequiredCheck
    |> Ash.Query.filter(
      work_packet_version_id == ^packet_version.id and
        organization_id == ^packet_version.organization_id and
        workspace_id == ^packet_version.workspace_id
    )
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!(authorize?: false)
  end

  defp existing_run_result(session_context, operation, packet_version, attrs) do
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
        with {:ok, required_checks} <- read_run_required_checks(run) do
          replay_run_result!(%{run: run, required_checks: required_checks}, packet_version, attrs)
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp replay_run_result!(%{run: run} = run_result, packet_version, attrs) do
    if same_run_replay?(run, packet_version, attrs) do
      {:ok, run_result}
    else
      Repo.rollback({:work_run_operation_conflict, run.id})
    end
  end

  defp same_run_replay?(run, packet_version, attrs) do
    run.work_packet_version_id == packet_version_id(packet_version) and
      run.authority_posture == attrs[:authority_posture] and
      run.source_surface == attrs[:source_surface] and
      run.reason == attrs[:reason]
  end

  defp packet_version_id(%{id: id}), do: id
  defp packet_version_id(_packet_version), do: nil

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

  defp read_run_required_checks(%Run{} = run) do
    RunRequiredCheck
    |> Ash.Query.filter(
      run_id == ^run.id and organization_id == ^run.organization_id and
        workspace_id == ^run.workspace_id
    )
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read(authorize?: false)
  end

  defp read_run_required_checks(run_id) do
    RunRequiredCheck
    |> Ash.Query.filter(run_id == ^run_id)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read(authorize?: false)
  end

  defp read_observations(%Run{} = run) do
    ExecutionObservation
    |> Ash.Query.filter(
      work_run_id == ^run.id and organization_id == ^run.organization_id and
        workspace_id == ^run.workspace_id
    )
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read(authorize?: false)
  end

  defp read_evidence_items(%Run{} = run) do
    EvidenceItem
    |> Ash.Query.filter(
      work_run_id == ^run.id and organization_id == ^run.organization_id and
        workspace_id == ^run.workspace_id
    )
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read(authorize?: false)
  end

  defp read_verification_results(%Run{} = run) do
    VerificationResult
    |> Ash.Query.filter(
      work_run_id == ^run.id and organization_id == ^run.organization_id and
        workspace_id == ^run.workspace_id
    )
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

  defp unwrap_notification_result({record, _notifications}), do: record
  defp unwrap_notification_result(record), do: record

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, error}), do: {:error, error}
  defp normalize_transaction_result(other), do: other
end
