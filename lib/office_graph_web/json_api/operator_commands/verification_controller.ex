defmodule OfficeGraphWeb.JsonApi.OperatorCommands.VerificationController do
  use OfficeGraphWeb, :controller

  alias OfficeGraph.Operations
  alias OfficeGraph.Verification
  alias OfficeGraphWeb.JsonApi.Common.Errors
  alias OfficeGraphWeb.JsonApi.OperatorCommands.{Input, Serializer}
  alias OfficeGraphWeb.RequestSession

  def create_evidence_candidate(conn, params) do
    command = "create_evidence_candidate"

    with {:ok, parsed} <- Input.parse(:create_evidence_candidate, params),
         {:ok, session_context} <- request_session(conn),
         {idempotency_key, attrs} <- Map.pop!(parsed, :idempotency_key),
         {:ok, operation} <-
           Operations.start_command(
             session_context,
             :evidence_candidate_create,
             idempotency_key,
             attrs
           ),
         {:ok, candidate} <-
           Verification.create_evidence_candidate(session_context, operation, attrs) do
      Serializer.render(
        conn,
        command,
        operation.id,
        [typed_id("evidence_candidate", candidate.id)],
        %{
          evidence_candidate: %{
            id: candidate.id,
            candidate_state: candidate.candidate_state
          }
        }
      )
    else
      error -> Errors.render(conn, error, command: command)
    end
  end

  def accept_evidence(conn, params) do
    command = "accept_evidence"

    with {:ok, parsed} <- Input.parse(:accept_evidence, params),
         {:ok, session_context} <- request_session(conn),
         {idempotency_key, command_input} <- Map.pop!(parsed, :idempotency_key),
         {:ok, operation} <-
           Operations.start_command(
             session_context,
             :evidence_accept,
             idempotency_key,
             command_input
           ),
         {candidate_id, attrs} <- Map.pop!(command_input, :evidence_candidate_id),
         {:ok, candidate} <-
           Verification.get_candidate_for_accept_command(session_context, candidate_id),
         {:ok, accepted} <-
           Verification.accept_evidence_candidate(session_context, operation, candidate, attrs) do
      affected_ids =
        [
          typed_id("evidence_candidate", accepted.candidate.id),
          typed_id("evidence_item", accepted.evidence_item.id),
          typed_id("verification_result", accepted.verification_result.id)
        ] ++
          optional_typed_id("verification_check", accepted.affected_verification_check_id) ++
          optional_typed_id("run_required_check", accepted.affected_run_required_check_id) ++
          optional_typed_id("review_finding", accepted.affected_review_finding_id) ++
          optional_typed_id("task", accepted.affected_task_id) ++
          optional_typed_id("work_run", accepted.work_run)

      Serializer.render(conn, command, operation.id, affected_ids, %{
        evidence_candidate: %{
          id: accepted.candidate.id,
          candidate_state: accepted.candidate.candidate_state
        },
        evidence_item: %{id: accepted.evidence_item.id, state: accepted.evidence_item.state},
        verification_result: %{
          id: accepted.verification_result.id,
          result: accepted.verification_result.result
        },
        run: optional_run_result(accepted.work_run)
      })
    else
      error -> Errors.render(conn, error, command: command)
    end
  end

  def waive_verification_check(conn, params) do
    command = "waive_verification_check"

    with {:ok, parsed} <- Input.parse(:waive_verification_check, params),
         {:ok, session_context} <- request_session(conn),
         {idempotency_key, command_input} <- Map.pop!(parsed, :idempotency_key),
         {:ok, operation} <-
           Operations.start_command(
             session_context,
             :verification_waive,
             idempotency_key,
             command_input
           ),
         {run_id, command_input} <- Map.pop!(command_input, :run_id),
         {required_check_id, attrs} <- Map.pop!(command_input, :run_required_check_id),
         {:ok, run} <- Verification.get_run_for_waive_command(session_context, run_id),
         {:ok, required_check} <-
           Verification.get_required_check_for_waive_command(session_context, required_check_id),
         {:ok, waived} <-
           Verification.waive_required_check(
             session_context,
             operation,
             run,
             required_check,
             attrs
           ) do
      Serializer.render(
        conn,
        command,
        operation.id,
        [
          typed_id("verification_result", waived.verification_result.id),
          typed_id("run_required_check", waived.required_check.id),
          typed_id("work_run", waived.run.id)
        ],
        %{
          verification_result: %{
            id: waived.verification_result.id,
            result: waived.verification_result.result
          },
          required_check: %{
            id: waived.required_check.id,
            verification_check_id: waived.required_check.verification_check_id,
            state: waived.required_check.state
          },
          run: run_result(waived.run)
        }
      )
    else
      error -> Errors.render(conn, error, command: command)
    end
  end

  defp request_session(conn) do
    conn
    |> Ash.PlugHelpers.get_actor()
    |> RequestSession.resolve()
  end

  defp optional_run_result(nil), do: nil
  defp optional_run_result(run), do: run_result(run)

  defp run_result(run) do
    %{
      id: run.id,
      work_packet_version_id: run.work_packet_version_id,
      execution_state: run.execution_state,
      verification_state: run.verification_state,
      aggregate_state: run.aggregate_state
    }
  end

  defp optional_typed_id(_type, nil), do: []
  defp optional_typed_id(type, id) when is_binary(id), do: [typed_id(type, id)]
  defp optional_typed_id(type, resource), do: [typed_id(type, resource.id)]

  defp typed_id(type, id), do: %{type: type, id: id}
end
