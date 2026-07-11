defmodule OfficeGraphWeb.GraphQL.OperatorCommands.Mutations do
  use Absinthe.Schema.Notation

  alias OfficeGraphWeb.GraphQL.OperatorCommands.Resolvers.Intake

  object :operator_command_mutations do
    field :submit_manual_intake, non_null(:submit_manual_intake_payload) do
      arg(:input, non_null(:submit_manual_intake_input))
      resolve(&Intake.submit/2)
    end
  end
end
