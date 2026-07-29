defmodule OfficeGraph.Verification.Waiver do
  @moduledoc false

  alias OfficeGraph.Authorization
  alias OfficeGraph.CommandSupport
  alias OfficeGraph.Operations
  alias OfficeGraph.Runs
  alias OfficeGraph.Runs.{Run, RunRequiredCheck}
  alias OfficeGraph.Verification.WaiverActionResult
  alias OfficeGraph.WorkGraph.{VerificationCheck, VerificationResult}

  import OfficeGraph.Verification.CommandSupport, only: [fetch_scoped: 3, trace!: 4]

  require Ash.Query

  @behaviour Ash.Resource.Actions.Implementation

  @verification_waive_action "verification.waive"

  @impl true
  def run(input, [mode: :persist_waiver], %{actor: session_context})
      when is_map(session_context) do
    attrs = input.arguments

    case Operations.lock_operation(attrs.operation_id) do
      {:ok, operation} ->
        case waive_required_check_contract(session_context, operation, attrs) do
          {:ok, result} -> WaiverActionResult.waived(result)
          {:rejected, error} -> WaiverActionResult.rejected(error)
          {:error, error} -> {:error, error}
        end

      {:error, error} ->
        WaiverActionResult.rejected(error)
    end
  end

  def run(_input, _opts, _context), do: {:error, :forbidden}

  def execute(session_context, operation, run, required_check, attrs)
      when is_map(run) and is_map(required_check) and is_map(attrs) do
    command_input =
      attrs
      |> Map.put(:run_id, run.id)
      |> Map.put(:run_required_check_id, required_check.id)

    with :ok <- Operations.validate_operation_context(session_context, operation),
         :ok <- Operations.validate_operation_action(operation, @verification_waive_action),
         :ok <- Operations.validate_command_replay(operation, command_input),
         :ok <-
           Authorization.authorize_operation(
             session_context,
             operation,
             :verification_waive,
             organization_id: session_context.organization_id
           ),
         :ok <- validate_waiver_attrs(attrs) do
      VerificationResult
      |> Ash.ActionInput.for_action(
        :persist_waiver_contract,
        attrs
        |> Map.put(:operation_id, operation.id)
        |> Map.put(:run_id, run.id)
        |> Map.put(:required_check_id, required_check.id)
      )
      |> Ash.run_action(actor: session_context, authorize?: false)
      |> CommandSupport.normalize_action_result()
      |> case do
        {:ok, %WaiverActionResult{} = result} ->
          WaiverActionResult.to_public_result(result)

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp waive_required_check_contract(session_context, operation, attrs) do
    with {:ok, run} <- lock_scoped(Run, session_context, attrs.run_id),
         {:ok, required_checks} <- lock_run_required_checks(run.id) do
      case existing_waiver_for_operation(session_context, operation) do
        {:ok, nil} ->
          prepare_and_persist_waiver(
            session_context,
            operation,
            run,
            required_checks,
            attrs
          )

        {:ok, verification_result} ->
          replay_waiver(run, required_checks, verification_result, attrs.required_check_id)

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp prepare_and_persist_waiver(
         session_context,
         operation,
         run,
         required_checks,
         attrs
       ) do
    with {:ok, required_check} <-
           validate_pending_required_check(run, required_checks, attrs.required_check_id),
         :ok <- validate_expected_run_state(run, attrs),
         :ok <- Runs.validate_required_check_contract(run, required_check),
         {:ok, verification_check} <-
           fetch_scoped(
             VerificationCheck,
             session_context,
             required_check.verification_check_id
           ) do
      persist_waiver(
        session_context,
        operation,
        run,
        required_check,
        verification_check,
        attrs
      )
    else
      {:error, error} -> {:rejected, error}
    end
  end

  defp persist_waiver(
         session_context,
         operation,
         run,
         required_check,
         verification_check,
         attrs
       ) do
    with {:ok, verification_result} <-
           VerificationResult
           |> Ash.Changeset.for_create(:create, %{
             organization_id: session_context.organization_id,
             workspace_id: session_context.workspace_id,
             verification_check_id: required_check.verification_check_id,
             evidence_item_id: nil,
             operation_id: operation.id,
             work_run_id: run.id,
             work_packet_version_id: run.work_packet_version_id,
             target_graph_item_id: verification_check.graph_item_id,
             actor_principal_id: session_context.principal_id,
             policy_basis: attrs.policy_basis,
             reason: attrs.reason,
             recorded_at: DateTime.utc_now(),
             result: "waived"
           })
           |> Ash.create(authorize?: false, return_notifications?: true)
           |> CommandSupport.normalize_ash_write(),
         {:ok, %{run: updated_run, required_check: updated_required_check}} <-
           Runs.apply_waived_verification_result(run, verification_result),
         :ok <-
           trace_waiver(operation, verification_result, updated_required_check) do
      {:ok,
       %{
         verification_result: verification_result,
         required_check: updated_required_check,
         run: updated_run
       }}
    end
  end

  defp trace_waiver(operation, verification_result, required_check) do
    trace!(
      operation,
      "verification_result.waive",
      "verification_result",
      verification_result.id
    )

    trace!(
      operation,
      "run_required_check.waive",
      "run_required_check",
      required_check.id
    )

    :ok
  end

  defp replay_waiver(run, required_checks, verification_result, required_check_id) do
    with {:ok, required_check} <-
           find_required_check(run, required_checks, required_check_id) do
      if verification_result.result == "waived" and
           verification_result.work_run_id == run.id and
           verification_result.verification_check_id == required_check.verification_check_id do
        {:ok,
         %{
           verification_result: verification_result,
           required_check: required_check,
           run: run
         }}
      else
        {:rejected, {:verification_waiver_operation_conflict, verification_result.id}}
      end
    else
      {:error, error} -> {:rejected, error}
    end
  end

  defp validate_pending_required_check(run, required_checks, required_check_id) do
    with {:ok, required_check} <-
           find_required_check(run, required_checks, required_check_id) do
      case required_check do
        %{state: "pending"} ->
          {:ok, required_check}

        required_check ->
          {:error, {:run_required_check_not_pending, required_check.id, required_check.state}}
      end
    end
  end

  defp find_required_check(run, required_checks, required_check_id) do
    case Enum.find(required_checks, &(&1.id == required_check_id)) do
      nil -> {:error, {:run_required_check_mismatch, run.id, required_check_id}}
      required_check -> {:ok, required_check}
    end
  end

  defp validate_expected_run_state(run, attrs) do
    if run.execution_state == attrs.expected_execution_state and
         run.verification_state == attrs.expected_verification_state do
      :ok
    else
      {:error, {:stale_work_run_state, run.id, run.execution_state, run.verification_state}}
    end
  end

  defp validate_waiver_attrs(attrs) do
    Enum.find_value([:reason, :policy_basis], :ok, fn field ->
      case attrs[field] do
        value when is_binary(value) ->
          if String.trim(value) == "", do: {:error, {:invalid_waiver_input, field}}

        _other ->
          {:error, {:invalid_waiver_input, field}}
      end
    end)
  end

  defp existing_waiver_for_operation(session_context, operation) do
    VerificationResult
    |> Ash.Query.filter(
      organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id and operation_id == ^operation.id
    )
    |> Ash.read_one(authorize?: false)
  end

  defp lock_scoped(resource, session_context, id) do
    Operations.lock_scoped_target(resource, session_context, id)
  end

  defp lock_run_required_checks(run_id) do
    RunRequiredCheck
    |> Ash.Query.filter(run_id == ^run_id)
    |> Ash.Query.sort(position: :asc, id: :asc)
    |> Ash.Query.lock(:for_update)
    |> Ash.read(authorize?: false)
  end
end
