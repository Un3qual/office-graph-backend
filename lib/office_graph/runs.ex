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
  alias OfficeGraph.Runs.{ExecutionObservation, ObservationStateReducer, Run, RunRequiredCheck}
  alias OfficeGraph.WorkGraph.{EvidenceItem, VerificationResult}

  alias OfficeGraph.WorkPackets.{
    WorkPacket,
    WorkPacketRequiredCheck,
    WorkPacketSourceReference,
    WorkPacketVersion
  }

  require Ash.Query

  @work_run_start_action "work_run.start"
  @execution_observation_record_action "execution_observation.record"

  def record_agent_observation(operation, execution, context_package, step_key, summary) do
    with true <- is_binary(step_key) and is_binary(summary),
         :ok <- validate_agent_output(operation, execution, context_package, step_key) do
      ExecutionObservation
      |> Ash.Query.filter(execution_id == ^execution.id and step_key == ^step_key)
      |> Ash.Query.lock(:for_update)
      |> Ash.read_one!(authorize?: false)
      |> case do
        nil ->
          Repo.ash_create!(ExecutionObservation, %{
            id: Ecto.UUID.generate(),
            organization_id: execution.organization_id,
            workspace_id: execution.workspace_id,
            work_run_id: execution.run_id,
            operation_id: operation.id,
            execution_id: execution.id,
            context_package_id: context_package.id,
            step_key: step_key,
            graph_item_id: execution.graph_item_id,
            source_kind: "agent_execution",
            source_identity: execution.id,
            idempotency_key: step_key,
            observed_status: "reported",
            normalized_status: "succeeded",
            freshness_state: "fresh",
            trust_basis: "agent_reported",
            rationale: summary,
            metadata: %{"classification" => "observation"}
          })

        observation ->
          if observation.operation_id == operation.id and
               observation.context_package_id == context_package.id and
               observation.rationale == summary,
             do: observation,
             else: Repo.rollback(:agent_observation_replay_conflict)
      end
    else
      false -> {:error, :invalid_agent_output}
      {:error, _reason} = error -> error
    end
  end

  defp validate_agent_output(operation, execution, context_package, step_key) do
    Operations.validate_agent_output_operation(operation, execution, context_package, step_key)
  end

  def graphql_node_type(%Run{}), do: :work_run
  def graphql_node_type(_value), do: nil

  def graphql_node(session_context, :work_run, id) do
    Ash.get(Run, id, actor: session_context, not_found_error?: false)
  end

  def graphql_node(_session_context, _type, _id), do: {:ok, nil}

  def get_packet_version_for_start_command(session_context, id) do
    Operations.read_command_target(
      WorkPacketVersion,
      :read_for_run_start_command,
      session_context,
      id
    )
  end

  def get_run_for_observation_command(session_context, id) do
    Operations.read_command_target(Run, :read_for_observation_command, session_context, id)
  end

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

  def active_run?(run) do
    run.state not in ["failed", "verified"] and
      run.aggregate_state not in ["failed", "verified"] and
      run.verification_state not in ["failed", "verified"]
  end

  def agent_context(authority, run_id, graph_item_id)
      when is_map(authority) and is_binary(run_id) and is_binary(graph_item_id) do
    with {:ok, principal_id, organization_id, workspace_id} <- agent_scope(authority),
         :ok <-
           Authorization.authorize_system_principal(
             principal_id,
             organization_id,
             workspace_id,
             :skeleton_read
           ),
         {:ok, run} <- fetch_agent_run(run_id, organization_id, workspace_id),
         true <- active_run?(run),
         :ok <- validate_run_graph_item(run, graph_item_id),
         {:ok, packet} <- fetch_agent_record(WorkPacket, run.work_packet_id, run),
         {:ok, packet_version} <-
           fetch_agent_record(WorkPacketVersion, run.work_packet_version_id, run),
         :ok <- validate_agent_autonomy(run, packet_version, Map.get(authority, :autonomy_mode)),
         {:ok, required_checks} <- read_run_required_checks(run),
         {:ok, observations} <- read_observations(run),
         {:ok, evidence_items} <- read_evidence_items(run),
         {:ok, verification_results} <- read_verification_results(run) do
      {:ok,
       %{
         run: run,
         packet: packet,
         packet_version: packet_version,
         required_checks: required_checks,
         observations: observations,
         evidence_items: evidence_items,
         verification_results: verification_results
       }}
    else
      {:error, :integration_storage_unavailable} = error -> error
      _missing_or_invalid -> {:error, :forbidden}
    end
  end

  def agent_context(_authority, _run_id, _graph_item_id), do: {:error, :forbidden}

  def revalidate_agent_authority(execution, autonomy_mode)
      when is_map(execution) and is_binary(autonomy_mode) do
    with run_id when is_binary(run_id) <- Map.get(execution, :run_id),
         graph_item_id when is_binary(graph_item_id) <- Map.get(execution, :graph_item_id),
         organization_id when is_binary(organization_id) <- Map.get(execution, :organization_id),
         workspace_id when is_binary(workspace_id) <- Map.get(execution, :workspace_id),
         {:ok, run} <- fetch_agent_run(run_id, organization_id, workspace_id),
         true <- active_run?(run),
         :ok <- validate_run_graph_item(run, graph_item_id),
         {:ok, packet_version} <-
           fetch_agent_record(WorkPacketVersion, run.work_packet_version_id, run),
         :ok <- validate_agent_autonomy(run, packet_version, autonomy_mode) do
      :ok
    else
      {:error, :integration_storage_unavailable} = error -> error
      _missing_or_changed -> {:error, :run_authority_revoked}
    end
  end

  def revalidate_agent_authority(_execution, _autonomy_mode),
    do: {:error, :run_authority_revoked}

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
    case apply_required_check_result(run, verification_result, :mark_satisfied) do
      {:ok, %{run: run}} -> {:ok, run}
      {:error, error} -> {:error, error}
    end
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

  def apply_waived_verification_result(run, %{result: "waived"} = verification_result) do
    apply_required_check_result(run, verification_result, :mark_waived)
  end

  defp apply_required_check_result(run, verification_result, action) do
    Repo.transaction(fn ->
      locked_run = lock_run!(run.id)

      required_check =
        mark_required_check_in_locked_run!(
          locked_run.id,
          verification_result.verification_check_id,
          action
        )

      required_checks = lock_required_checks_for_run!(locked_run.id)
      updated_run = maybe_set_run_verified!(locked_run, required_checks)

      %{run: updated_run, required_check: required_check}
    end)
    |> normalize_transaction_result()
  end

  def required_checks_for_run(run_id) do
    RunRequiredCheck
    |> Ash.Query.filter(run_id == ^run_id)
    |> Ash.read(authorize?: false)
  end

  def validate_required_check_contract(run, required_check) do
    WorkPacketRequiredCheck
    |> Ash.Query.filter(
      work_packet_version_id == ^run.work_packet_version_id and
        verification_check_id == ^required_check.verification_check_id and
        organization_id == ^run.organization_id and workspace_id == ^run.workspace_id
    )
    |> Ash.exists?(authorize?: false)
    |> case do
      true -> :ok
      false -> {:error, {:required_check_outside_packet_contract, run.id, required_check.id}}
    end
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

  def get_projection_summary(session_context, run_id, limit)
      when is_integer(limit) and limit > 0 do
    with {:ok, run} <- get_projection_run(session_context, run_id),
         {:ok, packet} <- fetch_scoped(WorkPacket, session_context, run.work_packet_id),
         {:ok, packet_version} <-
           fetch_scoped(WorkPacketVersion, session_context, run.work_packet_version_id),
         {:ok, required_checks} <- read_run_required_checks(run, limit),
         {:ok, observations} <- read_observations(run, limit),
         {:ok, evidence_items} <- read_evidence_items(run, limit),
         {:ok, verification_results} <- read_verification_results(run, limit),
         {:ok, child_counts} <- projection_child_counts(run) do
      {:ok,
       %{
         packet: packet,
         packet_version: packet_version,
         run: run,
         required_checks: required_checks,
         observations: observations,
         evidence_items: evidence_items,
         verification_results: verification_results,
         missing_evidence: missing_evidence(required_checks, verification_results),
         child_counts: child_counts
       }}
    end
  end

  def get_projection_run(session_context, run_id) do
    with :ok <-
           Authorization.authorize(session_context, :skeleton_read,
             organization_id: session_context.organization_id
           ),
         {:ok, run} <- fetch_scoped(Run, session_context, run_id) do
      {:ok, run}
    end
  end

  def get_verification_outcome_summary(session_context, run_id) do
    with {:ok, run} <- get_projection_run(session_context, run_id),
         {:ok, required_checks} <- read_run_required_checks(run),
         {:ok, verification_results} <- read_verification_results(run),
         {:ok, child_counts} <- projection_child_counts(run) do
      {:ok,
       %{
         run: run,
         verification_results: verification_results,
         missing_evidence: missing_evidence(required_checks, verification_results),
         child_counts: child_counts
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

  defp agent_scope(authority) do
    with principal_id when is_binary(principal_id) <- Map.get(authority, :agent_principal_id),
         organization_id when is_binary(organization_id) <- Map.get(authority, :organization_id),
         workspace_id when is_binary(workspace_id) <- Map.get(authority, :workspace_id) do
      {:ok, principal_id, organization_id, workspace_id}
    else
      _invalid -> {:error, :forbidden}
    end
  end

  defp fetch_agent_run(run_id, organization_id, workspace_id) do
    Run
    |> Ash.Query.filter(
      id == ^run_id and organization_id == ^organization_id and workspace_id == ^workspace_id
    )
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %Run{} = run} -> {:ok, run}
      {:ok, nil} -> {:error, :forbidden}
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  defp fetch_agent_record(resource, id, run) do
    resource
    |> Ash.Query.filter(
      id == ^id and organization_id == ^run.organization_id and workspace_id == ^run.workspace_id
    )
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, :forbidden}
      {:ok, record} -> {:ok, record}
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  defp validate_run_graph_item(run, graph_item_id) do
    WorkPacketSourceReference
    |> Ash.Query.filter(
      work_packet_version_id == ^run.work_packet_version_id and
        graph_item_id == ^graph_item_id and organization_id == ^run.organization_id and
        workspace_id == ^run.workspace_id
    )
    |> Ash.exists(authorize?: false)
    |> case do
      {:ok, true} -> :ok
      {:ok, false} -> {:error, :forbidden}
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  defp validate_agent_autonomy(run, packet_version, autonomy_mode) do
    if run.authority_posture == autonomy_mode and
         packet_version.autonomy_posture == autonomy_mode do
      :ok
    else
      {:error, :forbidden}
    end
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
          validate_fresh_run_start!(session_context, packet_version)
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

  defp validate_fresh_run_start!(session_context, packet_version) do
    packet = lock_run_start_packet!(session_context, packet_version.work_packet_id)

    if packet.current_version_id != packet_version.id do
      Repo.rollback({:stale_packet_version, packet.id, packet.current_version_id})
    end

    case active_run_for_packet_version(session_context, packet_version.id) do
      nil -> :ok
      active_run -> Repo.rollback({:active_work_run, packet_version.id, active_run.id})
    end
  end

  defp lock_run_start_packet!(session_context, packet_id) do
    case Operations.lock_scoped_target(WorkPacket, session_context, packet_id) do
      {:ok, packet} -> packet
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp active_run_for_packet_version(session_context, packet_version_id) do
    Run
    |> Ash.Query.filter(
      work_packet_version_id == ^packet_version_id and
        organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.Query.sort(inserted_at: :desc, id: :desc)
    |> Ash.read!(authorize?: false)
    |> Enum.find(&active_run?/1)
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

    run_required_check_inputs =
      required_checks
      |> Enum.with_index()
      |> Enum.map(fn {required_check, position} ->
        %{
          id: Ecto.UUID.generate(),
          run_id: run.id,
          verification_check_id: required_check.verification_check_id,
          organization_id: session_context.organization_id,
          workspace_id: session_context.workspace_id,
          position: position
        }
      end)

    run_required_checks =
      Repo.ash_bulk_create!(RunRequiredCheck, run_required_check_inputs)

    %{run: run, required_checks: run_required_checks}
  end

  defp update_run_after_observation!(run, observation) do
    case ObservationStateReducer.next_state(
           run,
           observation.normalized_status,
           failed_observations_for_run?(run.id)
         ) do
      :preserve ->
        run

      :failed ->
        update_run_failed!(run)

      :awaiting_verification ->
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

  defp mark_required_check_in_locked_run!(run_id, verification_check_id, action) do
    RunRequiredCheck
    |> Ash.Query.filter(run_id == ^run_id and verification_check_id == ^verification_check_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} ->
        nil

      {:ok, required_check} ->
        required_check
        |> Ash.Changeset.for_update(action, %{})
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

      required_checks != [] and
          Enum.all?(required_checks, &(&1.state in ["satisfied", "waived"])) ->
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
    |> Ash.Query.sort(position: :asc, inserted_at: :asc, id: :asc)
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

  defp read_run_required_checks(run, limit \\ nil)

  defp read_run_required_checks(%Run{} = run, limit) do
    RunRequiredCheck
    |> Ash.Query.filter(
      run_id == ^run.id and organization_id == ^run.organization_id and
        workspace_id == ^run.workspace_id
    )
    |> Ash.Query.sort(position: :asc, inserted_at: :asc, id: :asc)
    |> read_run_children(limit)
  end

  defp read_run_required_checks(run_id, nil) do
    RunRequiredCheck
    |> Ash.Query.filter(run_id == ^run_id)
    |> Ash.Query.sort(position: :asc, inserted_at: :asc, id: :asc)
    |> Ash.read(authorize?: false)
  end

  defp read_observations(run, limit \\ nil),
    do: read_work_run_children(ExecutionObservation, run, limit)

  defp read_evidence_items(run, limit \\ nil),
    do: read_work_run_children(EvidenceItem, run, limit)

  defp read_verification_results(run, limit \\ nil),
    do: read_work_run_children(VerificationResult, run, limit)

  defp read_work_run_children(resource, %Run{} = run, limit) do
    resource
    |> Ash.Query.filter(
      work_run_id == ^run.id and organization_id == ^run.organization_id and
        workspace_id == ^run.workspace_id
    )
    |> Ash.Query.sort(run_child_sort(limit))
    |> read_run_children(limit)
  end

  defp run_child_sort(nil), do: [inserted_at: :asc]
  defp run_child_sort(_limit), do: [inserted_at: :asc, id: :asc]

  defp read_run_children(query, nil), do: Ash.read(query, authorize?: false)

  defp read_run_children(query, limit) do
    query
    |> Ash.Query.limit(limit)
    |> Ash.read(authorize?: false)
  end

  defp projection_child_counts(%Run{} = run) do
    sql = """
    SELECT
      (SELECT count(*) FROM run_required_checks WHERE run_id = $1 AND organization_id = $2 AND workspace_id = $3),
      (SELECT count(*) FROM execution_observations WHERE work_run_id = $1 AND organization_id = $2 AND workspace_id = $3),
      (SELECT count(*) FROM evidence_candidates WHERE work_run_id = $1 AND organization_id = $2 AND workspace_id = $3),
      (SELECT count(*) FROM evidence_items WHERE work_run_id = $1 AND organization_id = $2 AND workspace_id = $3),
      (SELECT count(*) FROM verification_results WHERE work_run_id = $1 AND organization_id = $2 AND workspace_id = $3),
      (SELECT count(*) FROM run_required_checks WHERE run_id = $1 AND organization_id = $2 AND workspace_id = $3 AND state = 'pending'),
      (SELECT count(*)
       FROM evidence_candidates ec
       WHERE ec.work_run_id = $1
         AND ec.organization_id = $2
         AND ec.workspace_id = $3
         AND ec.candidate_state = 'candidate'
         AND ec.freshness_state = 'fresh'
         AND ec.trust_basis IN ('owner_attested', 'signed_provider_payload')
         AND EXISTS (
           SELECT 1 FROM run_required_checks rrc
           WHERE rrc.run_id = $1
             AND rrc.organization_id = $2
             AND rrc.workspace_id = $3
             AND rrc.state = 'pending'
             AND rrc.verification_check_id = ec.verification_check_id
         ))
    """

    params = [
      Ecto.UUID.dump!(run.id),
      Ecto.UUID.dump!(run.organization_id),
      Ecto.UUID.dump!(run.workspace_id)
    ]

    with {:ok,
          %{
            rows: [
              [required, observations, candidates, items, results, missing, pending_candidates]
            ]
          }} <-
           Repo.query(sql, params) do
      {:ok,
       %{
         required_checks: required,
         observations: observations,
         evidence_candidates: candidates,
         evidence_items: items,
         verification_results: results,
         missing_evidence: missing,
         pending_evidence_candidates: pending_candidates
       }}
    end
  end

  defp missing_evidence(required_checks, verification_results) do
    completed_check_ids =
      verification_results
      |> Enum.filter(&(&1.result in ["passed", "waived"]))
      |> MapSet.new(& &1.verification_check_id)

    failed_check_ids =
      verification_results
      |> Enum.filter(&(&1.result == "failed"))
      |> MapSet.new(& &1.verification_check_id)

    required_checks
    |> Enum.reject(fn required_check ->
      required_check.state == "waived" or
        MapSet.member?(completed_check_ids, required_check.verification_check_id)
    end)
    |> Enum.map(fn required_check ->
      %{
        verification_check_id: required_check.verification_check_id,
        reason: missing_evidence_reason(required_check, failed_check_ids)
      }
    end)
  end

  defp missing_evidence_reason(required_check, failed_check_ids) do
    if MapSet.member?(failed_check_ids, required_check.verification_check_id) do
      "failed_check"
    else
      "missing_accepted_evidence"
    end
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
