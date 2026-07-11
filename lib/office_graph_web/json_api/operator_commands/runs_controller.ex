defmodule OfficeGraphWeb.JsonApi.OperatorCommands.RunsController do
  use OfficeGraphWeb, :controller

  alias OfficeGraph.Operations
  alias OfficeGraph.Runs
  alias OfficeGraphWeb.JsonApi.Common.Errors
  alias OfficeGraphWeb.JsonApi.OperatorCommands.{Input, Serializer}
  alias OfficeGraphWeb.RequestSession

  def start_work_run(conn, params) do
    command = "start_work_run"

    with {:ok, parsed} <- Input.parse(:start_work_run, params),
         {:ok, session_context} <- request_session(conn),
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

      Serializer.render(conn, command, operation.id, affected_ids, %{
        run: run_result(result.run),
        required_checks: Enum.map(result.required_checks, &required_check_result/1)
      })
    else
      error -> Errors.render(conn, error, command: command)
    end
  end

  defp run_result(run) do
    %{
      id: run.id,
      work_packet_version_id: run.work_packet_version_id,
      execution_state: run.execution_state,
      verification_state: run.verification_state,
      aggregate_state: run.aggregate_state
    }
  end

  defp required_check_result(required_check) do
    %{
      id: required_check.id,
      verification_check_id: required_check.verification_check_id,
      state: required_check.state
    }
  end

  defp request_session(conn) do
    conn
    |> Ash.PlugHelpers.get_actor()
    |> RequestSession.resolve()
  end

  defp typed_id(type, id), do: %{type: type, id: id}
end
