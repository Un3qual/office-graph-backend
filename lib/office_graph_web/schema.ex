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
        case ApiSupport.submit_manual_intake(input) do
          {:ok, intake} ->
            {:ok,
             %{
               normalized_event: intake.normalized_event,
               proposed_changes: intake.proposed_changes
             }}

          error ->
            graphql_error(error)
        end
      end)
    end

    field :apply_proposed_changes, non_null(:applied_payload) do
      arg(:input, non_null(:apply_proposed_changes_input))

      resolve(fn %{input: input}, _ ->
        case ApiSupport.apply_proposed_changes(input) do
          {:ok, applied} -> {:ok, applied}
          error -> graphql_error(error)
        end
      end)
    end

    field :complete_verification, non_null(:completed_payload) do
      arg(:input, non_null(:complete_verification_input))

      resolve(fn %{input: input}, _ ->
        case ApiSupport.complete_verification(input) do
          {:ok, completed} -> {:ok, completed}
          error -> graphql_error(error)
        end
      end)
    end
  end

  defp graphql_error({:error, :forbidden}) do
    {:error, message: "The action is not authorized.", extensions: %{code: "forbidden"}}
  end

  defp graphql_error({:error, {:missing_proposed_change, id}}) do
    {:error,
     message: "A proposed change could not be found.",
     extensions: %{code: "missing_proposed_change", proposed_change_id: id}}
  end

  defp graphql_error({:error, {:invalid_proposed_change_status, id}}) do
    {:error,
     message: "A proposed change is no longer pending.",
     extensions: %{code: "invalid_proposed_change_status", proposed_change_id: id}}
  end

  defp graphql_error({:error, {:invalid_proposed_change_set, reason}}) do
    {:error,
     message: "The proposed change set is invalid.",
     extensions: %{code: "invalid_proposed_change_set", reason: format_reason(reason)}}
  end

  defp graphql_error({:error, {:missing_verification_check, id}}) do
    {:error,
     message: "A verification check could not be found.",
     extensions: %{code: "missing_verification_check", verification_check_id: id}}
  end

  defp graphql_error({:error, {:invalid_verification_check_status, id}}) do
    {:error,
     message: "A verification check is no longer required.",
     extensions: %{code: "invalid_verification_check_status", verification_check_id: id}}
  end

  defp graphql_error({:error, {:missing_field, field}}) do
    {:error,
     message: "A required field is missing.",
     extensions: %{code: "validation_failed", field: field}}
  end

  defp graphql_error({:error, {:invalid_field, field}}) do
    {:error,
     message: "A field has an invalid value.",
     extensions: %{code: "validation_failed", field: field}}
  end

  defp graphql_error({:error, _error}) do
    {:error, message: "Validation failed.", extensions: %{code: "validation_failed"}}
  end

  defp format_reason({kind, value}), do: %{kind: kind, value: value}
  defp format_reason(reason), do: reason
end
