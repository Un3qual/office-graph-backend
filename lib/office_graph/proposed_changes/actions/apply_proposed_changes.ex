defmodule OfficeGraph.ProposedChanges.Actions.ApplyProposedChanges do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.CommandSupport.{CommandError, TypedId}
  alias OfficeGraph.Operations
  alias OfficeGraph.ProposedChanges
  alias OfficeGraph.ProposedChanges.CommandResults.ApplyProposedChanges

  @impl true
  def run(input, _opts, %{actor: session_context}) when is_map(session_context) do
    {idempotency_key, command_input} = Map.pop!(input.arguments, :idempotency_key)

    with {:ok, operation} <-
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
      ApplyProposedChanges.new(
        command: "apply_proposed_changes",
        operation_id: operation.id,
        signal: applied.signal,
        task: applied.task,
        review_finding: applied.review_finding,
        verification_check: applied.verification_check,
        affected_ids:
          [
            typed_id("signal", applied.signal.id),
            typed_id("task", applied.task.id),
            typed_id("review_finding", applied.review_finding.id),
            typed_id("verification_check", applied.verification_check.id)
          ] ++
            Enum.map(
              proposed_changes,
              &typed_id("proposed_graph_change", &1.id)
            )
      )
    else
      {:error, error} -> {:error, CommandError.new(error)}
    end
  end

  def run(_input, _opts, _context), do: {:error, CommandError.new(:forbidden)}

  defp typed_id(type, id), do: TypedId.new!(type: type, id: id)
end
