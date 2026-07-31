defmodule OfficeGraph.NodeConversations.Actions.AppendConversationMessage do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.CommandSupport.CommandError
  alias OfficeGraph.NodeConversations
  alias OfficeGraph.NodeConversations.CommandResults.AppendConversationMessage
  alias OfficeGraph.Operations

  @impl true
  def run(input, _opts, %{actor: session_context}) when is_map(session_context) do
    {idempotency_key, command_input} = Map.pop!(input.arguments, :idempotency_key)

    with {:ok, operation} <-
           Operations.start_command(
             session_context,
             :conversation_message_create,
             idempotency_key,
             command_input
           ),
         {:ok, message} <-
           NodeConversations.append_human_message(
             session_context,
             operation,
             command_input
           ) do
      AppendConversationMessage.from_result(operation, message)
    else
      {:error, error} -> {:error, CommandError.new(error)}
    end
  end

  def run(_input, _opts, _context), do: {:error, CommandError.new(:forbidden)}
end
