defmodule OfficeGraph.Verification.Actions.WaiveVerificationCheck do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.CommandSupport.CommandError
  alias OfficeGraph.Operations
  alias OfficeGraph.Verification
  alias OfficeGraph.Verification.CommandResults.WaiveVerificationCheck

  @impl true
  def run(input, _opts, %{actor: session_context}) when is_map(session_context) do
    {idempotency_key, command_input} = Map.pop!(input.arguments, :idempotency_key)

    with {:ok, operation} <-
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
           Verification.get_required_check_for_waive_command(
             session_context,
             required_check_id
           ),
         {:ok, result} <-
           Verification.waive_required_check(
             session_context,
             operation,
             run,
             required_check,
             attrs
           ) do
      WaiveVerificationCheck.from_result(operation, result)
    else
      {:error, error} -> {:error, CommandError.new(error)}
    end
  end

  def run(_input, _opts, _context), do: {:error, CommandError.new(:forbidden)}
end
