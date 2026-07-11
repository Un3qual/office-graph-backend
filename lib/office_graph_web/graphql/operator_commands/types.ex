defmodule OfficeGraphWeb.GraphQL.OperatorCommands.Types do
  use Absinthe.Schema.Notation

  input_object :submit_manual_intake_input do
    field :idempotency_key, non_null(:string)
    field :source_identity, non_null(:string)
    field :replay_identity, non_null(:string)
    field :body, non_null(:string)
  end

  object :submit_manual_intake_payload do
    field :command, non_null(:string)
    field :operation_id, non_null(:id)
    field :affected_ids, non_null(list_of(non_null(:operator_typed_id)))
    field :normalized_event_id, non_null(:id)
    field :proposed_change_ids, non_null(list_of(non_null(:id)))
  end
end
