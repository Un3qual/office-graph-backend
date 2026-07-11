defmodule OfficeGraphWeb.GraphQL.OperatorCommands.Resolvers.Verification do
  @moduledoc false

  alias OfficeGraph.Operations
  alias OfficeGraph.Verification
  alias OfficeGraphWeb.GraphQL.Common.Errors
  alias OfficeGraphWeb.GraphQL.OperatorCommands.Input
  alias OfficeGraphWeb.RequestSession

  def create_candidate(%{input: input}, resolution) do
    with {:ok, parsed} <- Input.parse(:create_evidence_candidate, input),
         {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
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
      {:ok,
       %{
         command: "create_evidence_candidate",
         operation_id: operation.id,
         affected_ids: [typed_id("evidence_candidate", candidate.id)],
         evidence_candidate: candidate
       }}
    else
      error -> Errors.to_absinthe(error)
    end
  end

  def accept_evidence(%{input: input}, resolution) do
    with {:ok, parsed} <- Input.parse(:accept_evidence, input),
         {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
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

      {:ok,
       %{
         command: "accept_evidence",
         operation_id: operation.id,
         affected_ids: affected_ids,
         evidence_candidate: accepted.candidate,
         evidence_item: accepted.evidence_item,
         verification_result: accepted.verification_result,
         run: accepted.work_run
       }}
    else
      error -> Errors.to_absinthe(error)
    end
  end

  def waive_check(%{input: input}, resolution) do
    with {:ok, parsed} <- Input.parse(:waive_verification_check, input),
         {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
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
      {:ok,
       %{
         command: "waive_verification_check",
         operation_id: operation.id,
         affected_ids: [
           typed_id("verification_result", waived.verification_result.id),
           typed_id("run_required_check", waived.required_check.id),
           typed_id("work_run", waived.run.id)
         ],
         verification_result: waived.verification_result,
         required_check: waived.required_check,
         run: waived.run
       }}
    else
      error -> Errors.to_absinthe(error)
    end
  end

  defp optional_typed_id(_type, nil), do: []
  defp optional_typed_id(type, id) when is_binary(id), do: [typed_id(type, id)]
  defp optional_typed_id(type, resource), do: [typed_id(type, resource.id)]

  defp typed_id(type, id), do: %{type: type, id: id}
end
