defmodule OfficeGraphWeb.JsonApi.OperatorCommands.PacketsController do
  use OfficeGraphWeb, :controller

  alias OfficeGraph.Operations
  alias OfficeGraph.WorkPackets
  alias OfficeGraphWeb.JsonApi.Common.Errors
  alias OfficeGraphWeb.JsonApi.OperatorCommands.Serializer
  alias OfficeGraphWeb.OperatorCommands.Input
  alias OfficeGraphWeb.RequestSession

  def create_work_packet(conn, params) do
    command = "create_work_packet"

    with {:ok, parsed} <- Input.parse(:create_work_packet, params),
         {:ok, session_context} <- request_session(conn),
         {idempotency_key, attrs} <- Map.pop!(parsed, :idempotency_key),
         {:ok, operation} <-
           Operations.start_command(
             session_context,
             :work_packet_create,
             idempotency_key,
             attrs
           ),
         {:ok, result} <- WorkPackets.create_packet(session_context, operation, attrs) do
      render_packet_result(conn, command, operation, result)
    else
      error -> Errors.render(conn, error, command: command)
    end
  end

  def create_work_packet_version(conn, params) do
    command = "create_work_packet_version"

    with {:ok, parsed} <- Input.parse(:create_work_packet_version, params),
         {:ok, session_context} <- request_session(conn),
         {idempotency_key, command_input} <- Map.pop!(parsed, :idempotency_key),
         {:ok, operation} <-
           Operations.start_command(
             session_context,
             :work_packet_version_create,
             idempotency_key,
             command_input
           ),
         {packet_id, attrs} <- Map.pop!(command_input, :packet_id),
         {:ok, packet} <- WorkPackets.get_packet_for_version_command(session_context, packet_id),
         {:ok, result} <- WorkPackets.create_version(session_context, operation, packet, attrs) do
      render_packet_result(conn, command, operation, result)
    else
      error -> Errors.render(conn, error, command: command)
    end
  end

  defp render_packet_result(conn, command, operation, result) do
    Serializer.render(
      conn,
      command,
      operation.id,
      [
        typed_id("work_packet", result.packet.id),
        typed_id("work_packet_version", result.version.id)
      ],
      %{
        packet: %{
          id: result.packet.id,
          current_version_id: result.packet.current_version_id,
          title: result.packet.title,
          state: result.packet.state
        },
        packet_version: %{
          id: result.version.id,
          version_number: result.version.version_number,
          lifecycle_state: result.version.lifecycle_state
        }
      }
    )
  end

  defp request_session(conn) do
    conn
    |> Ash.PlugHelpers.get_actor()
    |> RequestSession.resolve()
  end

  defp typed_id(type, id), do: %{type: type, id: id}
end
