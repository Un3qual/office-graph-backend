defmodule OfficeGraph.Verification.Actions.AcceptEvidence do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.CommandSupport.CommandError
  alias OfficeGraph.Operations
  alias OfficeGraph.Verification
  alias OfficeGraph.Verification.CommandResults.AcceptEvidence

  @impl true
  def run(input, _opts, %{actor: session_context}) when is_map(session_context) do
    {idempotency_key, command_input} = Map.pop!(input.arguments, :idempotency_key)

    with {:ok, operation} <-
           Operations.start_command(
             session_context,
             :evidence_accept,
             idempotency_key,
             command_input
           ),
         {candidate_id, attrs} <- Map.pop!(command_input, :evidence_candidate_id),
         {:ok, candidate} <-
           Verification.get_candidate_for_accept_command(session_context, candidate_id),
         {:ok, result} <-
           Verification.accept_evidence_candidate(session_context, operation, candidate, attrs) do
      AcceptEvidence.from_result(operation, result)
    else
      {:error, error} -> {:error, CommandError.new(error)}
    end
  end

  def run(_input, _opts, _context), do: {:error, CommandError.new(:forbidden)}
end
