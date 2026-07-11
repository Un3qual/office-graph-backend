defmodule OfficeGraphWeb.GraphQL.OperatorCommands.Resolvers.Intake do
  @moduledoc false

  alias OfficeGraph.Integrations
  alias OfficeGraph.Operations
  alias OfficeGraph.ProposedChanges
  alias OfficeGraphWeb.GraphQL.Common.Errors
  alias OfficeGraphWeb.GraphQL.OperatorCommands.Input
  alias OfficeGraphWeb.RequestSession

  def submit(%{input: input}, resolution) do
    with {:ok, parsed} <- Input.parse(:submit_manual_intake, input),
         {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
         {idempotency_key, attrs} <- Map.pop!(parsed, :idempotency_key),
         {:ok, operation} <-
           Operations.start_command(
             session_context,
             :manual_intake_submit,
             idempotency_key,
             attrs
           ),
         {:ok, intake} <- Integrations.submit_manual_intake(session_context, operation, attrs) do
      proposed_change_ids = Enum.map(intake.proposed_changes, & &1.id)

      {:ok,
       %{
         command: "submit_manual_intake",
         operation_id: operation.id,
         normalized_event_id: intake.normalized_event.id,
         proposed_change_ids: proposed_change_ids,
         affected_ids:
           [%{type: "normalized_intake_event", id: intake.normalized_event.id}] ++
             Enum.map(proposed_change_ids, &%{type: "proposed_graph_change", id: &1})
       }}
    else
      error -> Errors.to_absinthe(error)
    end
  end

  def apply_proposed_changes(%{input: input}, resolution) do
    with {:ok, parsed} <- Input.parse(:apply_proposed_changes, input),
         {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
         {idempotency_key, command_input} <- Map.pop!(parsed, :idempotency_key),
         {:ok, operation} <-
           Operations.start_command(
             session_context,
             :proposed_change_apply,
             idempotency_key,
             command_input
           ),
         {:ok, proposed_changes} <-
           ProposedChanges.get_many(session_context, command_input.proposed_change_ids),
         {:ok, applied} <-
           ProposedChanges.apply_all(session_context, operation, %{
             normalized_event_id: command_input.normalized_event_id,
             proposed_changes: proposed_changes
           }) do
      affected_ids =
        [
          typed_id("signal", applied.signal.id),
          typed_id("task", applied.task.id),
          typed_id("review_finding", applied.review_finding.id),
          typed_id("verification_check", applied.verification_check.id)
        ] ++
          Enum.map(proposed_changes, &typed_id("proposed_graph_change", &1.id))

      {:ok,
       %{
         command: "apply_proposed_changes",
         operation_id: operation.id,
         affected_ids: affected_ids,
         signal: applied.signal,
         task: applied.task,
         review_finding: applied.review_finding,
         verification_check: applied.verification_check
       }}
    else
      error -> Errors.to_absinthe(error)
    end
  end

  defp typed_id(type, id), do: %{type: type, id: id}
end
