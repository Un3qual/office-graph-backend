defmodule OfficeGraphWeb.JsonApi.OperatorCommands.IntakeController do
  use OfficeGraphWeb, :controller

  alias OfficeGraph.Integrations
  alias OfficeGraph.Operations
  alias OfficeGraph.ProposedChanges
  alias OfficeGraphWeb.JsonApi.Common.Errors
  alias OfficeGraphWeb.JsonApi.OperatorCommands.{Input, Serializer}
  alias OfficeGraphWeb.RequestSession

  def submit_manual_intake(conn, params) do
    command = "submit_manual_intake"

    with {:ok, parsed} <- Input.parse(:submit_manual_intake, params),
         {:ok, session_context} <- request_session(conn),
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

      Serializer.render(
        conn,
        command,
        operation.id,
        [typed_id("normalized_intake_event", intake.normalized_event.id)] ++
          Enum.map(proposed_change_ids, &typed_id("proposed_graph_change", &1)),
        %{
          normalized_event_id: intake.normalized_event.id,
          proposed_change_ids: proposed_change_ids
        }
      )
    else
      error -> Errors.render(conn, error, command: command)
    end
  end

  def apply_proposed_changes(conn, params) do
    command = "apply_proposed_changes"

    with {:ok, parsed} <- Input.parse(:apply_proposed_changes, params),
         {:ok, session_context} <- request_session(conn),
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
        ] ++ Enum.map(proposed_changes, &typed_id("proposed_graph_change", &1.id))

      Serializer.render(conn, command, operation.id, affected_ids, %{
        signal: id_result(applied.signal),
        task: id_result(applied.task),
        review_finding: id_result(applied.review_finding),
        verification_check: %{
          id: applied.verification_check.id,
          graph_item_id: applied.verification_check.graph_item_id
        }
      })
    else
      error -> Errors.render(conn, error, command: command)
    end
  end

  defp request_session(conn) do
    conn
    |> Ash.PlugHelpers.get_actor()
    |> RequestSession.resolve()
  end

  defp id_result(resource), do: %{id: resource.id}
  defp typed_id(type, id), do: %{type: type, id: id}
end
