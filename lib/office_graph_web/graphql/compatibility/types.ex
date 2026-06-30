defmodule OfficeGraphWeb.GraphQL.Compatibility.Types do
  use Absinthe.Schema.Notation

  object :normalized_event do
    field :id, non_null(:id)
    field :outcome, non_null(:string)
  end

  object :proposed_change do
    field :id, non_null(:id)
    field :change_type, non_null(:string)
    field :status, non_null(:string)
  end

  object :manual_intake_payload do
    field :normalized_event, non_null(:normalized_event)
    field :proposed_changes, non_null(list_of(non_null(:proposed_change)))
  end

  object :loop_resource do
    field :id, non_null(:id)
    field :state, :string
    field :lifecycle_state, :string
  end

  object :applied_payload do
    field :signal, :loop_resource
    field :task, :loop_resource
    field :review_finding, :loop_resource
    field :verification_check, :loop_resource
  end

  object :verification_result do
    field :id, non_null(:id)
    field :result, non_null(:string)
  end

  object :completed_payload do
    field :evidence_item, :loop_resource
    field :verification_result, :verification_result
    field :task, :loop_resource
    field :review_finding, :loop_resource
    field :verification_check, :loop_resource
  end

  input_object :manual_intake_input do
    field :source_identity, non_null(:string)
    field :replay_identity, non_null(:string)
    field :body, non_null(:string)
  end

  input_object :apply_proposed_changes_input do
    field :ids, non_null(list_of(non_null(:id)))
  end

  input_object :complete_verification_input do
    field :verification_check_id, non_null(:id)
    field :title, non_null(:string)
    field :body, non_null(:string)
    field :artifact_uri, :string
  end
end
