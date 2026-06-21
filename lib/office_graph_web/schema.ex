defmodule OfficeGraphWeb.Schema do
  use Absinthe.Schema

  alias OfficeGraph.ApiSupport

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

  query do
    field :health, non_null(:string) do
      resolve(fn _, _ -> {:ok, "ok"} end)
    end
  end

  mutation do
    field :submit_manual_intake, non_null(:manual_intake_payload) do
      arg(:input, non_null(:manual_intake_input))

      resolve(fn %{input: input}, _ ->
        with {:ok, intake} <- ApiSupport.submit_manual_intake(input) do
          {:ok,
           %{
             normalized_event: intake.normalized_event,
             proposed_changes: intake.proposed_changes
           }}
        end
      end)
    end

    field :apply_proposed_changes, non_null(:applied_payload) do
      arg(:input, non_null(:apply_proposed_changes_input))

      resolve(fn %{input: input}, _ ->
        case ApiSupport.apply_proposed_changes(input) do
          {:error, {:missing_proposed_change, id}} ->
            {:error,
             message: "A proposed change could not be found.",
             extensions: %{code: "missing_proposed_change", proposed_change_id: id}}

          {:error, {:invalid_proposed_change_status, id}} ->
            {:error,
             message: "A proposed change is no longer pending.",
             extensions: %{code: "invalid_proposed_change_status", proposed_change_id: id}}

          result ->
            result
        end
      end)
    end

    field :complete_verification, non_null(:completed_payload) do
      arg(:input, non_null(:complete_verification_input))

      resolve(fn %{input: input}, _ ->
        ApiSupport.complete_verification(input)
      end)
    end
  end
end
