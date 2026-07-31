defmodule OfficeGraph.WorkPackets.Actions.CreateWorkPacketVersion do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.CommandSupport.CommandError
  alias OfficeGraph.Operations
  alias OfficeGraph.WorkPackets
  alias OfficeGraph.WorkPackets.CommandResults.PacketMutation

  @impl true
  def run(input, _opts, %{actor: session_context}) when is_map(session_context) do
    {idempotency_key, command_input} = Map.pop!(input.arguments, :idempotency_key)

    with {:ok, operation} <-
           Operations.start_command(
             session_context,
             :work_packet_version_create,
             idempotency_key,
             command_input
           ),
         {packet_id, attrs} <- Map.pop!(command_input, :packet_id),
         {:ok, packet} <- WorkPackets.get_packet_for_version_command(session_context, packet_id),
         {:ok, result} <- WorkPackets.create_version(session_context, operation, packet, attrs) do
      PacketMutation.from_result("create_work_packet_version", operation, result)
    else
      {:error, error} -> {:error, CommandError.new(error)}
    end
  end

  def run(_input, _opts, _context), do: {:error, CommandError.new(:forbidden)}
end
