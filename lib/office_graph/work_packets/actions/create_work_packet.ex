defmodule OfficeGraph.WorkPackets.Actions.CreateWorkPacket do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.CommandSupport.CommandError
  alias OfficeGraph.Operations
  alias OfficeGraph.WorkPackets
  alias OfficeGraph.WorkPackets.CommandResults.PacketMutation

  @impl true
  def run(input, _opts, %{actor: session_context}) when is_map(session_context) do
    {idempotency_key, attrs} = Map.pop!(input.arguments, :idempotency_key)

    with {:ok, operation} <-
           Operations.start_command(
             session_context,
             :work_packet_create,
             idempotency_key,
             attrs
           ),
         {:ok, result} <- WorkPackets.create_packet(session_context, operation, attrs) do
      PacketMutation.from_result("create_work_packet", operation, result)
    else
      {:error, error} -> {:error, CommandError.new(error)}
    end
  end

  def run(_input, _opts, _context), do: {:error, CommandError.new(:forbidden)}
end
