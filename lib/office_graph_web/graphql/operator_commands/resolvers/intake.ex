defmodule OfficeGraphWeb.GraphQL.OperatorCommands.Resolvers.Intake do
  @moduledoc false

  alias OfficeGraph.Integrations
  alias OfficeGraph.Operations
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
end
