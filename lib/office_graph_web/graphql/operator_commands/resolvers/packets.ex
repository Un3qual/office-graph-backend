defmodule OfficeGraphWeb.GraphQL.OperatorCommands.Resolvers.Packets do
  @moduledoc false

  alias OfficeGraph.Operations
  alias OfficeGraph.WorkPackets
  alias OfficeGraphWeb.GraphQL.Common.Errors
  alias OfficeGraphWeb.OperatorCommands.Input
  alias OfficeGraphWeb.RequestSession

  def create(%{input: input}, resolution) do
    with {:ok, parsed} <- Input.parse(:create_work_packet, input),
         {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
         {idempotency_key, attrs} <- Map.pop!(parsed, :idempotency_key),
         {:ok, operation} <-
           Operations.start_command(session_context, :work_packet_create, idempotency_key, attrs),
         {:ok, result} <- WorkPackets.create_packet(session_context, operation, attrs) do
      {:ok, packet_payload("create_work_packet", operation, result)}
    else
      error -> Errors.to_absinthe(error)
    end
  end

  def create_version(%{input: input}, resolution) do
    with {:ok, input} <-
           normalize_relay_id(input, :packet_id, :work_packet, resolution.schema),
         {:ok, input} <-
           normalize_relay_id(
             input,
             :expected_current_version_id,
             :work_packet_version,
             resolution.schema
           ),
         {:ok, parsed} <- Input.parse(:create_work_packet_version, input),
         {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
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
      {:ok, packet_payload("create_work_packet_version", operation, result)}
    else
      error -> Errors.to_absinthe(error)
    end
  end

  defp packet_payload(command, operation, result) do
    %{
      command: command,
      operation_id: operation.id,
      affected_ids: [
        typed_id("work_packet", result.packet.id),
        typed_id("work_packet_version", result.version.id)
      ],
      packet: result.packet,
      packet_version: result.version
    }
  end

  defp typed_id(type, id), do: %{type: type, id: id}

  defp normalize_relay_id(input, field, expected_type, schema) do
    value = Map.get(input, field)

    case Ecto.UUID.cast(value) do
      {:ok, id} ->
        {:ok, Map.put(input, field, id)}

      :error ->
        case Absinthe.Relay.Node.from_global_id(value, schema) do
          {:ok, %{type: ^expected_type, id: id}} -> {:ok, Map.put(input, field, id)}
          _other -> {:error, {:invalid_field, field}}
        end
    end
  end
end
