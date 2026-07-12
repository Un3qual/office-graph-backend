defmodule OfficeGraphWeb.GraphQL.OperatorCommands.Resolvers.Runs do
  @moduledoc false

  alias OfficeGraph.Operations
  alias OfficeGraph.Runs
  alias OfficeGraphWeb.GraphQL.Common.Errors
  alias OfficeGraphWeb.OperatorCommands.Input
  alias OfficeGraphWeb.RequestSession

  def start(%{input: input}, resolution) do
    with {:ok, parsed} <- Input.parse(:start_work_run, input),
         {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
         {idempotency_key, command_input} <- Map.pop!(parsed, :idempotency_key),
         {:ok, operation} <-
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
      affected_ids =
        [typed_id("work_run", result.run.id)] ++
          Enum.map(result.required_checks, &typed_id("run_required_check", &1.id))

      {:ok,
       %{
         command: "start_work_run",
         operation_id: operation.id,
         affected_ids: affected_ids,
         run: result.run,
         required_checks: result.required_checks
       }}
    else
      error -> Errors.to_absinthe(error)
    end
  end

  def record_observation(%{input: input}, resolution) do
    with {:ok, parsed} <- Input.parse(:record_execution_observation, input),
         {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
         {idempotency_key, command_input} <- Map.pop!(parsed, :idempotency_key),
         {:ok, operation} <-
           Operations.start_command(
             session_context,
             :execution_observation_record,
             idempotency_key,
             command_input
           ),
         {run_id, attrs} <- Map.pop!(command_input, :run_id),
         {:ok, run} <- Runs.get_run_for_observation_command(session_context, run_id),
         attrs <- normalize_observation_attrs(attrs),
         {:ok, result} <- Runs.record_observation(session_context, operation, run, attrs) do
      {:ok,
       %{
         command: "record_execution_observation",
         operation_id: operation.id,
         affected_ids: [
           typed_id("execution_observation", result.observation.id),
           typed_id("work_run", result.run.id)
         ],
         observation: result.observation,
         run: result.run
       }}
    else
      error -> Errors.to_absinthe(error)
    end
  end

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

  defp typed_id(type, id), do: %{type: type, id: id}
end
