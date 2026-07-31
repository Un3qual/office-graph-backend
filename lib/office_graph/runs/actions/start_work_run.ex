defmodule OfficeGraph.Runs.Actions.StartWorkRun do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.CommandSupport.CommandError
  alias OfficeGraph.Operations
  alias OfficeGraph.Runs
  alias OfficeGraph.Runs.CommandResults.StartWorkRun

  @impl true
  def run(input, _opts, %{actor: session_context}) when is_map(session_context) do
    {idempotency_key, command_input} = Map.pop!(input.arguments, :idempotency_key)

    with {:ok, operation} <-
           Operations.start_command(
             session_context,
             :work_run_start,
             idempotency_key,
             command_input
           ),
         {packet_version_id, attrs} <- Map.pop!(command_input, :packet_version_id),
         {:ok, packet_version} <-
           Runs.get_packet_version_for_start_command(session_context, packet_version_id),
         {:ok, result} <- Runs.start_run(session_context, operation, packet_version, attrs) do
      StartWorkRun.from_result(operation, result)
    else
      {:error, error} -> {:error, CommandError.new(error)}
    end
  end

  def run(_input, _opts, _context), do: {:error, CommandError.new(:forbidden)}
end
