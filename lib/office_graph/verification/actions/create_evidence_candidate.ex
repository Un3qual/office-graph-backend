defmodule OfficeGraph.Verification.Actions.CreateEvidenceCandidate do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.CommandSupport.CommandError
  alias OfficeGraph.Operations
  alias OfficeGraph.Verification
  alias OfficeGraph.Verification.CommandResults.CreateEvidenceCandidate

  @impl true
  def run(input, _opts, %{actor: session_context}) when is_map(session_context) do
    {idempotency_key, attrs} = Map.pop!(input.arguments, :idempotency_key)

    with {:ok, operation} <-
           Operations.start_command(
             session_context,
             :evidence_candidate_create,
             idempotency_key,
             attrs
           ),
         {:ok, candidate} <-
           Verification.create_evidence_candidate(session_context, operation, attrs) do
      CreateEvidenceCandidate.from_result(operation, candidate)
    else
      {:error, error} -> {:error, CommandError.new(error)}
    end
  end

  def run(_input, _opts, _context), do: {:error, CommandError.new(:forbidden)}
end
