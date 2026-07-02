defmodule OfficeGraphWeb.GraphQL.PacketRunVerification.Mutations do
  use Absinthe.Schema.Notation

  alias OfficeGraph.PacketRunVerification
  alias OfficeGraphWeb.GraphQL.Common.Errors
  alias OfficeGraphWeb.GraphQL.PacketRunVerification.Input
  alias OfficeGraphWeb.RequestSession

  object :packet_run_verification_mutations do
    field :execute_packet_run_verification, non_null(:packet_run_summary) do
      arg(:input, non_null(:execute_packet_run_verification_input))

      resolve(fn %{input: input}, resolution ->
        with {:ok, parsed_input} <- Input.parse(input),
             {:ok, session_context} <- request_session(resolution),
             {:ok, summary} <- PacketRunVerification.execute(session_context, parsed_input) do
          {:ok, summary}
        else
          error -> Errors.to_absinthe(error)
        end
      end)
    end
  end

  defp request_session(resolution) do
    resolution.context
    |> Map.get(:actor)
    |> RequestSession.resolve()
  end
end
