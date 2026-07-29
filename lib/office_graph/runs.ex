defmodule OfficeGraph.Runs do
  @moduledoc """
  Public boundary for work-run, observation, and run-event records.
  """

  use Boundary,
    deps: [
      OfficeGraph.Authorization,
      OfficeGraph.CommandSupport,
      OfficeGraph.Operations,
      OfficeGraph.WorkGraph,
      OfficeGraph.WorkPackets
    ],
    exports: []

  alias OfficeGraph.Authorization
  alias OfficeGraph.Operations
  alias OfficeGraph.Operations.OperationCorrelation

  alias OfficeGraph.Runs.{
    ExecutionObservation,
    ObservationStateReducer,
    Run,
    RunMutationResult,
    RunRequiredCheck
  }

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

  defguardp is_run_business_error(error)
            when error in [
                   :agent_observation_replay_conflict,
                   :forbidden,
                   :missing_packet_version
                 ] or
                   (is_tuple(error) and
                      elem(error, 0) in [
                        :active_work_run,
                        :not_found,
                        :observation_idempotency_conflict,
                        :observation_operation_conflict,
                        :stale_packet_version,
                        :work_run_already_verified,
                        :work_run_operation_conflict
                      ])

  @behaviour Ash.Resource.Actions.Implementation

  @impl true
  def run(input, [mode: :start_run], %{actor: session_context})
      when is_map(session_context) do
    attrs = input.arguments

    with {:ok, operation} <- Operations.lock_operation(attrs.operation_id) do
      case create_run_records(
             session_context,
             operation,
             %{id: attrs.packet_version_id},
             Map.drop(attrs, [:operation_id, :packet_version_id])
           ) do
        {:ok, %{run: run, required_checks: required_checks}} ->
          RunMutationResult.started(run, required_checks)

        {:error, error} when is_run_business_error(error) ->
          RunMutationResult.rejected(error)

        {:error, error} ->
          {:error, error}
      end
    end
  end

  def run(input, [mode: :record_observation], %{actor: session_context})
      when is_map(session_context) do
    attrs = input.arguments

    with {:ok, operation} <- Operations.lock_operation(attrs.operation_id) do
      case create_observation(
             session_context,
             operation,
             %{id: attrs.run_id},
             Map.drop(attrs, [:operation_id, :run_id])
           ) do
        {:ok, %{observation: observation, run: run}} ->
          RunMutationResult.observed(observation, run)

        {:error, error} when is_run_business_error(error) ->
          RunMutationResult.rejected(error)

        {:error, error} ->
          {:error, error}
      end
    end
  end

  def run(input, [mode: :apply_verification], _context) do
    attrs = input.arguments

    case apply_verification_result(attrs.run_id, attrs.result, attrs.verification_check_id) do
      {:ok, %{run: run, required_check: required_check}} ->
        RunMutationResult.verified(run, required_check)

      {:ok, run} ->
        RunMutationResult.verified(run)

      {:error, error} when is_run_business_error(error) ->
        RunMutationResult.rejected(error)

      {:error, error} ->
        {:error, error}
    end
  end

  def run(_input, _opts, _context), do: {:error, :forbidden}

  def record_agent_observation(operation, execution, context_package, step_key, summary) do
    with true <- is_binary(step_key) and is_binary(summary),
         :ok <- validate_agent_output(operation, execution, context_package, step_key) do
      ExecutionObservation
      |> Ash.Changeset.for_create(:create, %{
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
        classification: "observation"
      })
      |> Ash.create!(
        authorize?: false,
        return_notifications?: true,
        upsert?: true,
        upsert_identity: :unique_source_idempotency_key,
        upsert_fields: []
      )
      |> record_without_notifications()
      |> validate_agent_observation_replay(operation, context_package, summary)
    else
      false -> {:error, :invalid_agent_output}
      {:error, _reason} = error -> error
    end
  end

  defp validate_agent_observation_replay(observation, operation, context_package, summary) do
    if observation.operation_id == operation.id and
         observation.context_package_id == context_package.id and
         observation.rationale == summary do
      observation
    else
      {:error, :agent_observation_replay_conflict}
    end
  end

  defp validate_agent_output(operation, execution, context_package, step_key) do
    Operations.validate_agent_output_operation(operation, execution, context_package, step_key)
  end

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
           ),
         {:ok, packet_version_id} <- require_packet_version_id(packet_version) do
      Run
      |> Ash.ActionInput.for_action(
        :persist_run_contract,
        attrs
        |> Map.put(:operation_id, operation.id)
        |> Map.put(:packet_version_id, packet_version_id)
      )
      |> Ash.run_action(actor: session_context, authorize?: false)
      |> case do
        {:ok, %RunMutationResult{} = result} -> RunMutationResult.to_start_result(result)
        {:error, error} -> {:error, error}
      end
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
      Run
      |> Ash.ActionInput.for_action(
        :persist_observation_contract,
        attrs
        |> normalize_observation_attrs()
        |> Map.put(:operation_id, operation.id)
        |> Map.put(:run_id, run.id)
      )
      |> Ash.run_action(actor: session_context, authorize?: false)
      |> case do
        {:ok, %RunMutationResult{} = result} ->
          RunMutationResult.to_observation_result(result)

        {:error, error} ->
          {:error, error}
      end
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

  def apply_accepted_verification_result(run, %{result: "passed"} = verification_result) do
    run_verification_action(run, verification_result)
    |> case do
      {:ok, %RunMutationResult{} = result} -> RunMutationResult.to_run_result(result)
      {:error, error} -> {:error, error}
    end
  end

  def apply_accepted_verification_result(run, %{result: "failed"} = verification_result) do
    run_verification_action(run, verification_result)
    |> case do
      {:ok, %RunMutationResult{} = result} -> RunMutationResult.to_run_result(result)
      {:error, error} -> {:error, error}
    end
  end

  def apply_waived_verification_result(run, %{result: "waived"} = verification_result) do
    run_verification_action(run, verification_result)
    |> case do
      {:ok, %RunMutationResult{} = result} -> RunMutationResult.to_verification_result(result)
      {:error, error} -> {:error, error}
    end
  end

  defp run_verification_action(run, verification_result) do
    Run
    |> Ash.ActionInput.for_action(:apply_verification_result, %{
      run_id: run.id,
      result: verification_result.result,
      verification_check_id: Map.get(verification_result, :verification_check_id)
    })
    |> Ash.run_action(authorize?: false)
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
           fetch_projection_packet_version(session_context, run.work_packet_version_id),
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

  def validate_conversation_scope(session_context, run_id, graph_item_id)
      when is_binary(run_id) and is_binary(graph_item_id) do
    with {:ok, run} <- get_projection_run(session_context, run_id),
         :ok <- validate_run_graph_item(run, graph_item_id) do
      {:ok, run}
    end
  end

  def validate_conversation_scope(_session_context, _run_id, _graph_item_id),
    do: {:error, :forbidden}

  def validate_agent_invocation_scope(run, graph_item_id, autonomy_mode)
      when is_binary(graph_item_id) and is_binary(autonomy_mode) do
    with true <- active_run?(run),
         :ok <- validate_run_graph_item(run, graph_item_id),
         {:ok, packet_version} <-
           fetch_agent_record(WorkPacketVersion, run.work_packet_version_id, run),
         :ok <- validate_agent_autonomy(run, packet_version, autonomy_mode) do
      :ok
    else
      false -> {:error, :forbidden}
      {:error, _reason} = error -> error
    end
  end

  def validate_agent_invocation_scope(_run, _graph_item_id, _autonomy_mode),
    do: {:error, :forbidden}

  defp create_observation(session_context, operation, run, attrs) do
    attrs = normalize_observation_attrs(attrs)

    with {:ok, run} <- lock_scoped_run(session_context, run.id),
         {:ok, operation_observation} <-
           existing_observation_for_operation(session_context, operation) do
      case operation_observation do
        nil ->
          create_or_replay_source_observation(session_context, operation, run, attrs)

        observation ->
          replay_operation_observation(observation, run, attrs)
      end
    end
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

  defp create_or_replay_source_observation(session_context, operation, run, attrs) do
    case existing_observation(session_context, attrs) do
      {:ok, nil} ->
        create_observation_record(session_context, operation, run, attrs)

      {:ok, observation} ->
        replay_source_observation(observation, run, attrs)

      {:error, error} ->
        {:error, error}
    end
  end

  defp create_observation_record(session_context, operation, run, attrs) do
    changeset =
      Ash.Changeset.for_create(ExecutionObservation, :create, %{
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
        classification: attrs[:classification]
      })

    create_opts =
      [
        authorize?: false,
        return_notifications?: true
      ] ++ observation_upsert_opts(attrs)

    case Ash.create(changeset, create_opts) do
      {:ok, observation, _notifications} when observation.operation_id == operation.id ->
        with {:ok, run} <- update_run_after_observation(run, observation) do
          {:ok, %{observation: observation, run: run}}
        end

      {:ok, observation, _notifications} ->
        replay_source_observation(observation, run, attrs)

      {:error, error} ->
        {:error, error}
    end
  end

  defp observation_upsert_opts(%{idempotency_key: idempotency_key})
       when is_binary(idempotency_key) do
    [
      upsert?: true,
      upsert_identity: :unique_source_idempotency_key,
      upsert_fields: []
    ]
  end

  defp observation_upsert_opts(_attrs), do: []

  defp create_run_records(session_context, operation, packet_version, attrs) do
    with {:ok, packet_version} <- reload_packet_version(session_context, packet_version),
         {:ok, existing_result} <-
           existing_run_result(session_context, operation, packet_version, attrs) do
      case existing_result do
        nil ->
          with :ok <- validate_fresh_run_start(session_context, packet_version),
               {:ok, required_checks} <- packet_required_checks(packet_version) do
            create_run_contract(
              session_context,
              operation,
              packet_version,
              attrs,
              required_checks
            )
          end

        run_result ->
          {:ok, run_result}
      end
    end
  end

  defp validate_fresh_run_start(session_context, packet_version) do
    with {:ok, packet} <-
           Operations.lock_scoped_target(
             WorkPacket,
             session_context,
             packet_version.work_packet_id
           ),
         :ok <- validate_current_packet_version(packet, packet_version),
         {:ok, nil} <- active_run_for_packet_version(session_context, packet_version.id) do
      :ok
    else
      {:ok, %Run{} = active_run} ->
        {:error, {:active_work_run, packet_version.id, active_run.id}}

      {:error, error} ->
        {:error, error}
    end
  end

  defp validate_current_packet_version(packet, packet_version) do
    if packet.current_version_id == packet_version.id do
      :ok
    else
      {:error, {:stale_packet_version, packet.id, packet.current_version_id}}
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
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, runs} -> {:ok, Enum.find(runs, &active_run?/1)}
      {:error, error} -> {:error, error}
    end
  end

  defp create_run_contract(
         session_context,
         operation,
         packet_version,
         attrs,
         required_checks
       ) do
    with {:ok, run, _run_notifications} <-
           Run
           |> Ash.Changeset.for_create(:create, %{
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
           })
           |> Ash.create(authorize?: false, return_notifications?: true),
         {:ok, run_required_checks} <-
           create_run_required_checks(session_context, run, required_checks) do
      {:ok, %{run: run, required_checks: run_required_checks}}
    end
  end

  defp create_run_required_checks(session_context, run, required_checks) do
    inputs =
      required_checks
      |> Enum.with_index()
      |> Enum.map(fn {required_check, position} ->
        %{
          run_id: run.id,
          verification_check_id: required_check.verification_check_id,
          organization_id: session_context.organization_id,
          workspace_id: session_context.workspace_id,
          position: position
        }
      end)

    case Ash.bulk_create(inputs, RunRequiredCheck, :create,
           authorize?: false,
           return_errors?: true,
           return_notifications?: true,
           return_records?: true,
           sorted?: true,
           stop_on_error?: true,
           transaction: false
         ) do
      %Ash.BulkResult{status: :success, records: records} ->
        {:ok, records}

      %Ash.BulkResult{errors: errors} when is_list(errors) and errors != [] ->
        {:error, Ash.Error.to_error_class(errors)}

      %Ash.BulkResult{status: status} ->
        {:error, {:run_required_check_create_failed, status}}
    end
  end

  defp update_run_after_observation(run, observation) do
    case ObservationStateReducer.next_state(
           run,
           observation.normalized_status,
           failed_observations_for_run?(run.id)
         ) do
      :preserve ->
        {:ok, run}

      :failed ->
        update_run_failed(run)

      :awaiting_verification ->
        run
        |> Ash.Changeset.for_update(:set_lifecycle_state, %{
          state: "awaiting_verification",
          aggregate_state: "awaiting_verification",
          execution_state: "completed",
          verification_state: "missing_evidence",
          completed_at: DateTime.utc_now()
        })
        |> Ash.update(authorize?: false, return_notifications?: true)
        |> normalize_ash_write()
    end
  end

  defp update_run_failed(run) do
    run
    |> Ash.Changeset.for_update(:set_lifecycle_state, %{
      state: "failed",
      aggregate_state: "failed",
      execution_state: "failed",
      verification_state: "failed",
      completed_at: DateTime.utc_now()
    })
    |> Ash.update(authorize?: false, return_notifications?: true)
    |> normalize_ash_write()
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
      observation.classification == attrs[:classification]
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

  defp replay_operation_observation(observation, run, attrs) do
    if same_observation_replay?(observation, run, attrs) do
      {:ok, %{observation: observation, run: run}}
    else
      {:error, {:observation_operation_conflict, observation.id}}
    end
  end

  defp replay_source_observation(observation, run, attrs) do
    if same_observation_replay?(observation, run, attrs) do
      {:ok, %{observation: observation, run: run}}
    else
      {:error, {:observation_idempotency_conflict, observation.id}}
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

  defp failed_observations_for_run?(run_id) do
    ExecutionObservation
    |> Ash.Query.filter(work_run_id == ^run_id and normalized_status != "succeeded")
    |> Ash.exists?(authorize?: false)
  end

  defp apply_verification_result(run_id, "failed", _verification_check_id) do
    with {:ok, run} <- lock_run(run_id) do
      if run_verified?(run) do
        {:error, {:work_run_already_verified, run.id}}
      else
        set_run_verification_failed(run)
      end
    end
  end

  defp apply_verification_result(run_id, result, verification_check_id)
       when result in ["passed", "waived"] do
    action = if result == "passed", do: :mark_satisfied, else: :mark_waived

    with {:ok, run} <- lock_run(run_id),
         {:ok, required_check} <-
           mark_required_check_in_locked_run(run.id, verification_check_id, action),
         {:ok, required_checks} <- lock_required_checks_for_run(run.id),
         {:ok, updated_run} <- maybe_set_run_verified(run, required_checks) do
      {:ok, %{run: updated_run, required_check: required_check}}
    end
  end

  defp lock_run(run_id) do
    Run
    |> Ash.Query.filter(id == ^run_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, {:not_found, Run, run_id}}
      {:ok, run} -> {:ok, run}
      {:error, error} -> {:error, error}
    end
  end

  defp lock_required_checks_for_run(run_id) do
    RunRequiredCheck
    |> Ash.Query.filter(run_id == ^run_id)
    |> Ash.Query.sort(id: :asc)
    |> Ash.Query.lock(:for_update)
    |> Ash.read(authorize?: false)
  end

  defp mark_required_check_in_locked_run(run_id, verification_check_id, action) do
    RunRequiredCheck
    |> Ash.Query.filter(run_id == ^run_id and verification_check_id == ^verification_check_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, required_check} ->
        required_check
        |> Ash.Changeset.for_update(action, %{})
        |> Ash.update(authorize?: false, return_notifications?: true)
        |> normalize_ash_write()

      {:error, error} ->
        {:error, error}
    end
  end

  defp maybe_set_run_verified(run, required_checks) do
    cond do
      run_failed?(run) ->
        {:ok, run}

      required_checks != [] and
          Enum.all?(required_checks, &(&1.state in ["satisfied", "waived"])) ->
        set_run_verified(run)

      true ->
        {:ok, run}
    end
  end

  defp set_run_verified(run) do
    run
    |> Ash.Changeset.for_update(:set_lifecycle_state, %{
      state: "verified",
      aggregate_state: "verified",
      execution_state: "completed",
      verification_state: "verified",
      completed_at: run.completed_at || DateTime.utc_now()
    })
    |> Ash.update(authorize?: false, return_notifications?: true)
    |> normalize_ash_write()
  end

  defp set_run_verification_failed(run) do
    run
    |> Ash.Changeset.for_update(:set_lifecycle_state, %{
      state: "failed",
      aggregate_state: "failed",
      execution_state: run.execution_state || "completed",
      verification_state: "failed",
      completed_at: run.completed_at || DateTime.utc_now()
    })
    |> Ash.update(authorize?: false, return_notifications?: true)
    |> normalize_ash_write()
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
    |> Ash.read(authorize?: false)
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
          replay_run_result(%{run: run, required_checks: required_checks}, packet_version, attrs)
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp replay_run_result(%{run: run} = run_result, packet_version, attrs) do
    if same_run_replay?(run, packet_version, attrs) do
      {:ok, run_result}
    else
      {:error, {:work_run_operation_conflict, run.id}}
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

  defp require_packet_version_id(%{id: id}) when is_binary(id), do: {:ok, id}
  defp require_packet_version_id(_packet_version), do: {:error, :missing_packet_version}

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
    with {:ok, run} <-
           Ash.load(
             run,
             [
               :required_check_count,
               :observation_count,
               :evidence_candidate_count,
               :evidence_item_count,
               :verification_result_count,
               :missing_evidence_count,
               :pending_evidence_candidate_count
             ],
             authorize?: false
           ) do
      {:ok,
       %{
         required_checks: run.required_check_count,
         observations: run.observation_count,
         evidence_candidates: run.evidence_candidate_count,
         evidence_items: run.evidence_item_count,
         verification_results: run.verification_result_count,
         missing_evidence: run.missing_evidence_count,
         pending_evidence_candidates: run.pending_evidence_candidate_count
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

  defp fetch_projection_packet_version(_session_context, nil), do: {:ok, nil}

  defp fetch_projection_packet_version(session_context, id),
    do: fetch_scoped(WorkPacketVersion, session_context, id)

  defp lock_scoped_run(session_context, run_id) do
    Run
    |> Ash.Query.filter(id == ^run_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} ->
        {:error, {:not_found, Run, run_id}}

      {:ok, run} ->
        case validate_scope(session_context, run) do
          :ok -> {:ok, run}
          {:error, error} -> {:error, error}
        end

      {:error, error} ->
        {:error, error}
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

  defp record_without_notifications({record, _notifications}), do: record
  defp record_without_notifications(record), do: record

  defp normalize_ash_write({:ok, record, _notifications}), do: {:ok, record}
  defp normalize_ash_write({:ok, record}), do: {:ok, record}
  defp normalize_ash_write({:error, error}), do: {:error, error}
end
