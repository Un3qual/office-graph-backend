defmodule OfficeGraph.Verification.Waiver do
  @moduledoc false

  alias OfficeGraph.Authorization
  alias OfficeGraph.Operations
  alias OfficeGraph.Repo
  alias OfficeGraph.Runs
  alias OfficeGraph.Runs.{Run, RunRequiredCheck}
  alias OfficeGraph.WorkGraph.{VerificationCheck, VerificationResult}

  import OfficeGraph.Verification.CommandSupport,
    only: [
      fetch_scoped!: 3,
      lock_operation!: 1,
      lock_scoped!: 3,
      normalize_transaction_result: 1,
      trace!: 4
    ]

  require Ash.Query

  @verification_waive_action "verification.waive"

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
      waive_required_check_record(
        session_context,
        operation,
        %{run_id: run.id, required_check_id: required_check.id},
        attrs
      )
    end
  end

  defp waive_required_check_record(session_context, operation, target, attrs) do
    Repo.transaction(fn ->
      _operation = lock_operation!(operation.id)
      run = lock_scoped!(Run, session_context, target.run_id)
      required_checks = lock_run_required_checks!(run.id)

      case existing_waiver_for_operation(session_context, operation) do
        {:ok, nil} ->
          waive_locked_required_check!(
            session_context,
            operation,
            run,
            required_checks,
            target.required_check_id,
            attrs
          )

        {:ok, verification_result} ->
          replay_waiver!(run, required_checks, verification_result, target.required_check_id)

        {:error, error} ->
          Repo.rollback(error)
      end
    end)
    |> normalize_transaction_result()
  end

  defp waive_locked_required_check!(
         session_context,
         operation,
         run,
         required_checks,
         required_check_id,
         attrs
       ) do
    required_check = validate_pending_required_check!(run, required_checks, required_check_id)
    validate_expected_run_state!(run, attrs)

    case Runs.validate_required_check_contract(run, required_check) do
      :ok -> :ok
      {:error, error} -> Repo.rollback(error)
    end

    verification_check =
      fetch_scoped!(VerificationCheck, session_context, required_check.verification_check_id)

    verification_result =
      Repo.ash_create!(
        VerificationResult,
        %{
          id: Ecto.UUID.generate(),
          organization_id: session_context.organization_id,
          workspace_id: session_context.workspace_id,
          verification_check_id: required_check.verification_check_id,
          evidence_item_id: nil,
          operation_id: operation.id,
          work_run_id: run.id,
          work_packet_version_id: run.work_packet_version_id,
          target_graph_item_id: verification_check.graph_item_id,
          actor_principal_id: session_context.principal_id,
          policy_basis: attrs[:policy_basis],
          reason: attrs[:reason],
          recorded_at: DateTime.utc_now(),
          result: "waived"
        }
      )

    %{run: updated_run, required_check: updated_required_check} =
      case Runs.apply_waived_verification_result(run, verification_result) do
        {:ok, result} -> result
        {:error, error} -> Repo.rollback(error)
      end

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
      updated_required_check.id
    )

    %{
      verification_result: verification_result,
      required_check: updated_required_check,
      run: updated_run
    }
  end

  defp replay_waiver!(run, required_checks, verification_result, required_check_id) do
    required_check =
      Enum.find(required_checks, &(&1.id == required_check_id)) ||
        Repo.rollback({:run_required_check_mismatch, run.id, required_check_id})

    if verification_result.result == "waived" and
         verification_result.work_run_id == run.id and
         verification_result.verification_check_id == required_check.verification_check_id do
      %{
        verification_result: verification_result,
        required_check: required_check,
        run: run
      }
    else
      Repo.rollback({:verification_waiver_operation_conflict, verification_result.id})
    end
  end

  defp validate_pending_required_check!(run, required_checks, required_check_id) do
    case Enum.find(required_checks, &(&1.id == required_check_id)) do
      nil ->
        Repo.rollback({:run_required_check_mismatch, run.id, required_check_id})

      %{state: "pending"} = required_check ->
        required_check

      required_check ->
        Repo.rollback({:run_required_check_not_pending, required_check.id, required_check.state})
    end
  end

  defp validate_expected_run_state!(run, attrs) do
    if run.execution_state == attrs[:expected_execution_state] and
         run.verification_state == attrs[:expected_verification_state] do
      :ok
    else
      Repo.rollback({:stale_work_run_state, run.id, run.execution_state, run.verification_state})
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

  defp lock_run_required_checks!(run_id) do
    RunRequiredCheck
    |> Ash.Query.filter(run_id == ^run_id)
    |> Ash.Query.sort(position: :asc, id: :asc)
    |> Ash.Query.lock(:for_update)
    |> Ash.read!(authorize?: false)
  end
end
