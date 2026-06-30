defmodule OfficeGraphWeb.GraphQL.PacketRunVerification.Mutations do
  use Absinthe.Schema.Notation

  alias OfficeGraph.ApiSupport
  alias OfficeGraphWeb.GraphQL.Common.Errors

  object :packet_run_verification_mutations do
    field :execute_packet_run_verification, non_null(:packet_run_summary) do
      arg(:input, non_null(:execute_packet_run_verification_input))

      resolve(fn %{input: input}, _ ->
        case ApiSupport.execute_packet_run_verification(input) do
          {:ok, summary} -> {:ok, summary}
          error -> Errors.to_absinthe(error)
        end
      end)
    end
  end
end
