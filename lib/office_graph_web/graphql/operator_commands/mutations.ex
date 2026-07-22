defmodule OfficeGraphWeb.GraphQL.OperatorCommands.Mutations do
  use Absinthe.Schema.Notation

  alias OfficeGraphWeb.GraphQL.OperatorCommands.Resolvers.{
    GitHub,
    Intake,
    Packets,
    Runs,
    Agents,
    Verification
  }

  object :operator_command_mutations do
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

    field :submit_manual_intake, non_null(:submit_manual_intake_payload) do
      arg(:input, non_null(:submit_manual_intake_input))
      resolve(&Intake.submit/2)
    end

    field :apply_proposed_changes, non_null(:apply_proposed_changes_payload) do
      arg(:input, non_null(:apply_proposed_changes_input))
      resolve(&Intake.apply_proposed_changes/2)
    end

    field :create_work_packet, non_null(:create_work_packet_payload) do
      arg(:input, non_null(:create_work_packet_input))
      resolve(&Packets.create/2)
    end

    field :create_work_packet_version, non_null(:create_work_packet_version_payload) do
      arg(:input, non_null(:create_work_packet_version_input))
      resolve(&Packets.create_version/2)
    end

    field :start_work_run, non_null(:start_work_run_payload) do
      arg(:input, non_null(:start_work_run_input))
      resolve(&Runs.start/2)
    end

    field :record_execution_observation, non_null(:record_execution_observation_payload) do
      arg(:input, non_null(:record_execution_observation_input))
      resolve(&Runs.record_observation/2)
    end

    field :create_evidence_candidate, non_null(:create_evidence_candidate_payload) do
      arg(:input, non_null(:create_evidence_candidate_input))
      resolve(&Verification.create_candidate/2)
    end

    field :accept_evidence, non_null(:accept_evidence_payload) do
      arg(:input, non_null(:accept_evidence_input))
      resolve(&Verification.accept_evidence/2)
    end

    field :waive_verification_check, non_null(:waive_verification_check_payload) do
      arg(:input, non_null(:waive_verification_check_input))
      resolve(&Verification.waive_check/2)
    end
  end
end
