defmodule OfficeGraphWeb.GraphQL.OperatorCommands.Types do
  use Absinthe.Schema.Notation

  input_object :submit_manual_intake_input do
    field :idempotency_key, non_null(:string)
    field :source_identity, non_null(:string)
    field :replay_identity, non_null(:string)
    field :body, non_null(:string)
  end

  input_object :apply_proposed_changes_input do
    field :idempotency_key, non_null(:string)
    field :normalized_event_id, non_null(:id)
    field :proposed_change_ids, non_null(list_of(non_null(:id)))
  end

  input_object :create_work_packet_input do
    field :idempotency_key, non_null(:string)
    field :title, non_null(:string)
    field :objective, non_null(:string)
    field :context_summary, non_null(:string)
    field :requirements, non_null(:string)
    field :success_criteria, non_null(:string)
    field :autonomy_posture, non_null(:string)
    field :source_graph_item_ids, non_null(list_of(non_null(:id)))
    field :verification_check_ids, non_null(list_of(non_null(:id)))
  end

  input_object :create_work_packet_version_input do
    field :idempotency_key, non_null(:string)
    field :packet_id, non_null(:id)
    field :expected_current_version_id, non_null(:id)
    field :title, non_null(:string)
    field :objective, non_null(:string)
    field :context_summary, non_null(:string)
    field :requirements, non_null(:string)
    field :success_criteria, non_null(:string)
    field :autonomy_posture, non_null(:string)
    field :source_graph_item_ids, non_null(list_of(non_null(:id)))
    field :verification_check_ids, non_null(list_of(non_null(:id)))
  end

  input_object :start_work_run_input do
    field :idempotency_key, non_null(:string)
    field :packet_version_id, non_null(:id)
    field :source_surface, non_null(:string)
    field :reason, non_null(:string)
    field :authority_posture, non_null(:string)
  end

  input_object :record_execution_observation_input do
    field :idempotency_key, non_null(:string)
    field :run_id, non_null(:id)
    field :verification_check_id, non_null(:id)
    field :source_graph_item_id, non_null(:id)
    field :observation_source_kind, non_null(:string)
    field :observation_source_identity, non_null(:string)
    field :observation_idempotency_key, non_null(:string)
    field :observed_status, non_null(:string)
    field :normalized_status, non_null(:string)
    field :freshness_state, non_null(:string)
    field :trust_basis, non_null(:string)
    field :observation_rationale, non_null(:string)
  end

  input_object :create_evidence_candidate_input do
    field :idempotency_key, non_null(:string)
    field :work_run_id, non_null(:id)
    field :verification_check_id, non_null(:id)
    field :execution_observation_id, non_null(:id)
    field :claim, non_null(:string)
    field :source_kind, non_null(:string)
    field :source_identity, non_null(:string)
    field :freshness_state, non_null(:string)
    field :trust_basis, non_null(:string)
    field :sensitivity, non_null(:string)
  end

  input_object :accept_evidence_input do
    field :idempotency_key, non_null(:string)
    field :candidate_id, non_null(:id)
    field :title, non_null(:string)
    field :body, non_null(:string)
    field :result, non_null(:string)
    field :acceptance_policy_basis, non_null(:string)
  end

  input_object :waive_verification_check_input do
    field :idempotency_key, non_null(:string)
    field :run_id, non_null(:id)
    field :run_required_check_id, non_null(:id)
    field :expected_execution_state, non_null(:string)
    field :expected_verification_state, non_null(:string)
    field :reason, non_null(:string)
    field :policy_basis, non_null(:string)
  end

  object :operator_command_signal do
    field :id, non_null(:id)
  end

  object :operator_command_task do
    field :id, non_null(:id)
  end

  object :operator_command_review_finding do
    field :id, non_null(:id)
  end

  object :operator_command_verification_check do
    field :id, non_null(:id)
    field :graph_item_id, non_null(:id)
  end

  object :operator_command_work_packet do
    field :id, non_null(:id)
    field :current_version_id, non_null(:id)
    field :title, non_null(:string)
    field :state, non_null(:string)
  end

  object :operator_command_work_packet_version do
    field :id, non_null(:id)
    field :version_number, non_null(:integer)
    field :lifecycle_state, non_null(:string)
  end

  object :operator_command_work_run do
    field :id, non_null(:id)
    field :execution_state, non_null(:string)
    field :verification_state, non_null(:string)
  end

  object :operator_command_run_required_check do
    field :id, non_null(:id)
    field :verification_check_id, non_null(:id)
    field :state, non_null(:string)
  end

  object :operator_command_execution_observation do
    field :id, non_null(:id)
    field :normalized_status, non_null(:string)
  end

  object :operator_command_evidence_candidate do
    field :id, non_null(:id)
    field :candidate_state, non_null(:string)
  end

  object :operator_command_evidence_item do
    field :id, non_null(:id)
    field :state, non_null(:string)
  end

  object :operator_command_verification_result do
    field :id, non_null(:id)
    field :result, non_null(:string)
  end

  object :submit_manual_intake_payload do
    field :command, non_null(:string)
    field :operation_id, non_null(:id)
    field :affected_ids, non_null(list_of(non_null(:operator_typed_id)))
    field :normalized_event_id, non_null(:id)
    field :proposed_change_ids, non_null(list_of(non_null(:id)))
  end

  object :apply_proposed_changes_payload do
    field :command, non_null(:string)
    field :operation_id, non_null(:id)
    field :affected_ids, non_null(list_of(non_null(:operator_typed_id)))
    field :signal, non_null(:operator_command_signal)
    field :task, non_null(:operator_command_task)
    field :review_finding, non_null(:operator_command_review_finding)
    field :verification_check, non_null(:operator_command_verification_check)
  end

  object :create_work_packet_payload do
    field :command, non_null(:string)
    field :operation_id, non_null(:id)
    field :affected_ids, non_null(list_of(non_null(:operator_typed_id)))
    field :packet, non_null(:operator_command_work_packet)
    field :packet_version, non_null(:operator_command_work_packet_version)
  end

  object :create_work_packet_version_payload do
    field :command, non_null(:string)
    field :operation_id, non_null(:id)
    field :affected_ids, non_null(list_of(non_null(:operator_typed_id)))
    field :packet, non_null(:operator_command_work_packet)
    field :packet_version, non_null(:operator_command_work_packet_version)
  end

  object :start_work_run_payload do
    field :command, non_null(:string)
    field :operation_id, non_null(:id)
    field :affected_ids, non_null(list_of(non_null(:operator_typed_id)))
    field :run, non_null(:operator_command_work_run)

    field :required_checks,
          non_null(list_of(non_null(:operator_command_run_required_check)))
  end

  object :record_execution_observation_payload do
    field :command, non_null(:string)
    field :operation_id, non_null(:id)
    field :affected_ids, non_null(list_of(non_null(:operator_typed_id)))
    field :observation, non_null(:operator_command_execution_observation)
    field :run, non_null(:operator_command_work_run)
  end

  object :create_evidence_candidate_payload do
    field :command, non_null(:string)
    field :operation_id, non_null(:id)
    field :affected_ids, non_null(list_of(non_null(:operator_typed_id)))
    field :evidence_candidate, non_null(:operator_command_evidence_candidate)
  end

  object :accept_evidence_payload do
    field :command, non_null(:string)
    field :operation_id, non_null(:id)
    field :affected_ids, non_null(list_of(non_null(:operator_typed_id)))
    field :evidence_candidate, non_null(:operator_command_evidence_candidate)
    field :evidence_item, non_null(:operator_command_evidence_item)
    field :verification_result, non_null(:operator_command_verification_result)
    field :run, :operator_command_work_run
  end

  object :waive_verification_check_payload do
    field :command, non_null(:string)
    field :operation_id, non_null(:id)
    field :affected_ids, non_null(list_of(non_null(:operator_typed_id)))
    field :verification_result, non_null(:operator_command_verification_result)
    field :required_check, non_null(:operator_command_run_required_check)
    field :run, non_null(:operator_command_work_run)
  end
end
