defmodule OfficeGraphWeb.GraphQL.PacketRunVerification.Types do
  use Absinthe.Schema.Notation

  object :packet_run_packet do
    field :id, non_null(:id)
    field :title, non_null(:string)
    field :state, non_null(:string)
  end

  object :packet_run_packet_version do
    field :id, non_null(:id)
    field :version_number, non_null(:integer)
    field :lifecycle_state, non_null(:string)
    field :objective, non_null(:string)
  end

  object :packet_run_run do
    field :id, non_null(:id)
    field :aggregate_state, non_null(:string)
    field :execution_state, non_null(:string)
    field :verification_state, non_null(:string)
  end

  object :packet_run_required_check do
    field :id, non_null(:id)
    field :verification_check_id, non_null(:id)
    field :state, non_null(:string)
  end

  object :packet_run_observation do
    field :id, non_null(:id)
    field :normalized_status, non_null(:string)
    field :source_kind, non_null(:string)
    field :source_identity, non_null(:string)
  end

  object :packet_run_evidence_item do
    field :id, non_null(:id)
    field :state, non_null(:string)
    field :candidate_id, :id
    field :work_run_id, :id
  end

  object :packet_run_verification_result do
    field :id, non_null(:id)
    field :result, non_null(:string)
    field :evidence_item_id, :id
    field :operation_id, :id
    field :work_run_id, :id
    field :work_packet_version_id, :id
    field :actor_principal_id, :id
    field :policy_basis, :string
    field :target_graph_item_id, :id
  end

  object :packet_run_missing_evidence do
    field :verification_check_id, non_null(:id)
    field :reason, non_null(:string)
  end

  object :packet_run_summary do
    field :packet, non_null(:packet_run_packet)
    field :packet_version, non_null(:packet_run_packet_version)
    field :run, non_null(:packet_run_run)
    field :required_checks, non_null(list_of(non_null(:packet_run_required_check)))
    field :observations, non_null(list_of(non_null(:packet_run_observation)))
    field :evidence_items, non_null(list_of(non_null(:packet_run_evidence_item)))
    field :verification_results, non_null(list_of(non_null(:packet_run_verification_result)))
    field :missing_evidence, non_null(list_of(non_null(:packet_run_missing_evidence)))
  end

  input_object :execute_packet_run_verification_input do
    field :flow_identity, non_null(:string)
    field :verification_check_id, non_null(:id)
    field :source_graph_item_id, non_null(:id)
    field :packet_title, non_null(:string)
    field :objective, non_null(:string)
    field :context_summary, non_null(:string)
    field :requirements, non_null(:string)
    field :success_criteria, non_null(:string)
    field :autonomy_posture, non_null(:string)
    field :source_surface, non_null(:string)
    field :reason, non_null(:string)
    field :authority_posture, non_null(:string)
    field :observation_source_kind, non_null(:string)
    field :observation_source_identity, non_null(:string)
    field :observation_idempotency_key, non_null(:string)
    field :observed_status, non_null(:string)
    field :normalized_status, non_null(:string)
    field :freshness_state, non_null(:string)
    field :trust_basis, non_null(:string)
    field :observation_rationale, non_null(:string)
    field :evidence_claim, non_null(:string)
    field :evidence_title, non_null(:string)
    field :evidence_body, non_null(:string)
    field :evidence_result, non_null(:string)
    field :acceptance_policy_basis, non_null(:string)
  end
end
