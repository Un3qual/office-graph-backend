defmodule OfficeGraphWeb.GraphQL.OperatorCommands.Mutations do
  use Absinthe.Schema.Notation

  alias OfficeGraphWeb.GraphQL.OperatorCommands.Resolvers.GitHub

  object :operator_command_mutations do
    field :bind_github_installation, non_null(:bind_github_installation_payload) do
      arg(:input, non_null(:bind_github_installation_input))
      resolve(&GitHub.bind_installation/2)
    end

    field :reply_to_github_review, non_null(:github_outbound_action_payload) do
      arg(:input, non_null(:reply_to_github_review_input))
      resolve(&GitHub.reply_to_review/2)
    end

    field :update_github_check, non_null(:github_outbound_action_payload) do
      arg(:input, non_null(:update_github_check_input))
      resolve(&GitHub.update_check/2)
    end
  end
end
