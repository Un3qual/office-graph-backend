defmodule OfficeGraph.Runs.Actions.RecordExecutionObservation do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.CommandSupport.CommandError
  alias OfficeGraph.Operations
  alias OfficeGraph.Runs
  alias OfficeGraph.Runs.CommandResults.RecordExecutionObservation

  @impl true
  def run(input, _opts, %{actor: session_context}) when is_map(session_context) do
    {idempotency_key, command_input} = Map.pop!(input.arguments, :idempotency_key)

    with {:ok, operation} <-
           Operations.start_command(
             session_context,
             :execution_observation_record,
             idempotency_key,
             command_input
           ),
         {run_id, attrs} <- Map.pop!(command_input, :run_id),
         {:ok, run} <- Runs.get_run_for_observation_command(session_context, run_id),
         {:ok, result} <-
           Runs.record_observation(
             session_context,
             operation,
             run,
             normalize_observation_attrs(attrs)
           ) do
      RecordExecutionObservation.from_result(operation, result)
    else
      {:error, error} -> {:error, CommandError.new(error)}
    end
  end

  def run(_input, _opts, _context), do: {:error, CommandError.new(:forbidden)}

  defp normalize_observation_attrs(attrs) do
    attrs
    |> rename(:observation_source_kind, :source_kind)
    |> rename(:observation_source_identity, :source_identity)
    |> rename(:observation_idempotency_key, :idempotency_key)
    |> rename(:source_graph_item_id, :graph_item_id)
    |> rename(:observation_rationale, :rationale)
  end

  defp rename(attrs, source, target) do
    {value, attrs} = Map.pop!(attrs, source)
    Map.put(attrs, target, value)
  end
end
