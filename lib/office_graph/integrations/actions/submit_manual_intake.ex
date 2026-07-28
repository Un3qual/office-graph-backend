defmodule OfficeGraph.Integrations.Actions.SubmitManualIntake do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.CommandSupport.{CommandError, TypedId}
  alias OfficeGraph.Integrations
  alias OfficeGraph.Integrations.CommandResults.SubmitManualIntake
  alias OfficeGraph.Operations

  @impl true
  def run(input, _opts, %{actor: session_context}) when is_map(session_context) do
    {idempotency_key, attrs} = Map.pop!(input.arguments, :idempotency_key)

    with {:ok, operation} <-
           Operations.start_command(
             session_context,
             :manual_intake_submit,
             idempotency_key,
             attrs
           ),
         {:ok, intake} <- Integrations.submit_manual_intake(session_context, operation, attrs) do
      proposed_change_ids = Enum.map(intake.proposed_changes, & &1.id)

      SubmitManualIntake.new(
        command: "submit_manual_intake",
        operation_id: operation.id,
        normalized_event: intake.normalized_event,
        proposed_changes: intake.proposed_changes,
        affected_ids:
          [
            TypedId.new!(
              type: "normalized_intake_event",
              id: intake.normalized_event.id
            )
          ] ++
            Enum.map(
              proposed_change_ids,
              &TypedId.new!(type: "proposed_graph_change", id: &1)
            )
      )
    else
      {:error, error} -> {:error, CommandError.new(error)}
    end
  end

  def run(_input, _opts, _context), do: {:error, CommandError.new(:forbidden)}
end
