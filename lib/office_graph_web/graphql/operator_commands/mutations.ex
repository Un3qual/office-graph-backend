defmodule OfficeGraphWeb.GraphQL.OperatorCommands.Mutations do
  use Absinthe.Schema.Notation

  alias OfficeGraphWeb.GraphQL.OperatorCommands.Resolvers.{Agents, GitHub}

  object :operator_command_mutations do
    field :invoke_agent, non_null(:invoke_agent_payload) do
      arg(:input, non_null(:invoke_agent_input))
      resolve(&Agents.invoke_agent/2)
    end

    field :cancel_agent_execution, non_null(:cancel_agent_execution_payload) do
      arg(:input, non_null(:cancel_agent_execution_input))
      resolve(&Agents.cancel_agent_execution/2)
    end

    field :start_run_conversation, non_null(:start_run_conversation_payload) do
      arg(:input, non_null(:start_run_conversation_input))
      resolve(&Agents.start_conversation/2)
    end

    field :append_conversation_message, non_null(:append_conversation_message_payload) do
      arg(:input, non_null(:append_conversation_message_input))
      resolve(&Agents.append_conversation_message/2)
    end

    field :resolve_agent_approval, non_null(:resolve_agent_approval_payload) do
      arg(:input, non_null(:resolve_agent_approval_input))
      resolve(&Agents.resolve_approval/2)
    end

    field :resolve_agent_context_expansion,
          non_null(:resolve_agent_context_expansion_payload) do
      arg(:input, non_null(:resolve_agent_context_expansion_input))
      resolve(&Agents.resolve_context_expansion/2)
    end

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
