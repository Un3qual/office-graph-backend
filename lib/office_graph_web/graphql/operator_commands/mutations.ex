defmodule OfficeGraphWeb.GraphQL.OperatorCommands.Mutations do
  use Absinthe.Schema.Notation

  alias OfficeGraphWeb.GraphQL.OperatorCommands.Resolvers.{
    GitHub,
    Intake,
    Packets,
    Runs,
    Verification
  }

  object :operator_command_mutations do
    field :bind_github_installation, non_null(:bind_github_installation_payload) do
      arg(:input, non_null(:bind_github_installation_input))
      resolve(&GitHub.bind_installation/2)
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
