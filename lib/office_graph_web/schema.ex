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
    field :work_run_id, :id
    field :work_packet_version_id, :id
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

  object :operator_typed_id do
    field :type, non_null(:string)
    field :id, non_null(:id)
  end

  object :operator_source do
    field :identity, non_null(:string)
    field :replay_identity, non_null(:string)
    field :outcome, non_null(:string)
  end

  object :operator_proposed_change_status do
    field :pending, non_null(:integer)
    field :applied, non_null(:integer)
    field :rejected, non_null(:integer)
    field :total, non_null(:integer)
  end

  object :operator_graph_link do
    field :type, non_null(:string)
    field :id, non_null(:id)
    field :graph_item_id, :id
    field :title, :string
    field :state, :string
  end

  object :operator_graph_relationship do
    field :id, non_null(:id)
    field :source_graph_item_id, non_null(:id)
    field :target_graph_item_id, non_null(:id)
    field :relationship_type, non_null(:string)
  end

  object :operator_trace do
    field :operation_id, :id
    field :resource_count, non_null(:integer)
    field :resources, non_null(list_of(non_null(:operator_typed_id)))
  end

  object :operator_workflow_item do
    field :type, non_null(:string)
    field :typed_id, non_null(:operator_typed_id)
    field :normalized_event_id, non_null(:id)
    field :duplicate_of_id, :id
    field :status, non_null(:string)
    field :reason_codes, non_null(list_of(non_null(:string)))
    field :source, non_null(:operator_source)
    field :proposed_change_status, non_null(:operator_proposed_change_status)
    field :blocker_reasons, non_null(list_of(non_null(:string)))
    field :allowed_next_actions, non_null(list_of(non_null(:string)))
    field :operation_watermark, :id
    field :source_watermark, :id
    field :graph_links, non_null(list_of(non_null(:operator_graph_link)))
    field :graph_relationships, non_null(list_of(non_null(:operator_graph_relationship)))
    field :audit_trace, non_null(:operator_trace)
    field :revision_trace, non_null(:operator_trace)
  end

  object :operator_inbox do
    field :type, non_null(:string)

    field :empty, non_null(:boolean) do
      resolve(fn inbox, _, _ -> {:ok, Map.fetch!(inbox, :empty?)} end)
    end

    field :source_watermark, :id
    field :rows, non_null(list_of(non_null(:operator_workflow_item)))
  end

  object :operator_required_check do
    field :id, non_null(:id)
    field :graph_item_id, :id
    field :verification_check_id, :id
    field :state, non_null(:string)
  end

  object :operator_source_link do
    field :type, non_null(:string)
    field :id, non_null(:id)
    field :graph_item_id, non_null(:id)
    field :title, non_null(:string)
  end

  object :operator_packet_readiness do
    field :type, non_null(:string)

    field :ready, non_null(:boolean) do
      resolve(fn readiness, _, _ -> {:ok, Map.fetch!(readiness, :ready?)} end)
    end

    field :status, non_null(:string)
    field :allowed_next_actions, non_null(list_of(non_null(:string)))
    field :blocker_reasons, non_null(list_of(non_null(:string)))
    field :source_links, non_null(list_of(non_null(:operator_source_link)))
    field :required_checks, non_null(list_of(non_null(:operator_required_check)))
    field :source_watermark, :id
  end

  object :operator_run_ref do
    field :id, non_null(:id)
    field :aggregate_state, non_null(:string)
    field :execution_state, non_null(:string)
    field :verification_state, non_null(:string)
  end

  object :operator_packet_ref do
    field :id, non_null(:id)
    field :title, non_null(:string)
    field :state, non_null(:string)
  end

  object :operator_packet_version_ref do
    field :id, non_null(:id)
    field :version_number, non_null(:integer)
    field :lifecycle_state, non_null(:string)
    field :objective, :string
  end

  object :operator_observation do
    field :id, non_null(:id)
    field :verification_check_id, :id
    field :graph_item_id, :id
    field :normalized_status, non_null(:string)
    field :freshness_state, non_null(:string)
    field :trust_basis, non_null(:string)
    field :source_kind, non_null(:string)
    field :source_identity, non_null(:string)
  end

  object :operator_evidence_candidate do
    field :id, non_null(:id)
    field :verification_check_id, non_null(:id)
    field :execution_observation_id, non_null(:id)
    field :claim, non_null(:string)
    field :state, non_null(:string)
    field :freshness_state, non_null(:string)
    field :trust_basis, non_null(:string)
    field :source_kind, non_null(:string)
    field :source_identity, non_null(:string)
  end

  object :operator_evidence_item do
    field :id, non_null(:id)
    field :state, non_null(:string)
    field :candidate_id, :id
    field :work_run_id, :id
  end

  object :operator_verification_result do
    field :id, non_null(:id)
    field :result, non_null(:string)
    field :verification_check_id, non_null(:id)
    field :work_run_id, :id
    field :work_packet_version_id, :id
  end

  object :operator_missing_evidence do
    field :verification_check_id, non_null(:id)
    field :reason, non_null(:string)
  end

  object :operator_run_state do
    field :type, non_null(:string)
    field :status, non_null(:string)
    field :allowed_next_actions, non_null(list_of(non_null(:string)))
    field :source_watermark, :id
    field :packet, non_null(:operator_packet_ref)
    field :packet_version, non_null(:operator_packet_version_ref)
    field :run, non_null(:operator_run_ref)
    field :required_checks, non_null(list_of(non_null(:operator_required_check)))
    field :observations, non_null(list_of(non_null(:operator_observation)))
    field :evidence_candidates, non_null(list_of(non_null(:operator_evidence_candidate)))
    field :evidence_items, non_null(list_of(non_null(:operator_evidence_item)))
    field :verification_results, non_null(list_of(non_null(:operator_verification_result)))
    field :missing_evidence, non_null(list_of(non_null(:operator_missing_evidence)))
  end

  object :operator_verification_outcome do
    field :type, non_null(:string)
    field :status, non_null(:string)
    field :source_watermark, :id
    field :run, non_null(:operator_run_ref)
    field :verification_results, non_null(list_of(non_null(:operator_verification_result)))
    field :missing_evidence, non_null(list_of(non_null(:operator_missing_evidence)))
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

  input_object :operator_packet_readiness_input do
    field :title, :string
    field :objective, :string
    field :context_summary, :string
    field :requirements, :string
    field :success_criteria, :string
    field :autonomy_posture, :string
    field :source_graph_item_ids, list_of(non_null(:id))
    field :verification_check_ids, list_of(non_null(:id))
  end

  query do
    field :health, non_null(:string) do
      resolve(fn _, _ -> {:ok, "ok"} end)
    end

    field :operator_inbox, non_null(:operator_inbox) do
      resolve(fn _, _ ->
        case ApiSupport.read_operator_inbox() do
          {:ok, inbox} -> {:ok, inbox}
          error -> graphql_error(error)
        end
      end)
    end

    field :operator_workflow_item, non_null(:operator_workflow_item) do
      arg(:id, non_null(:id))

      resolve(fn %{id: id}, _ ->
        case ApiSupport.read_operator_workflow_item(%{normalized_event_id: id}) do
          {:ok, item} -> {:ok, item}
          error -> graphql_error(error)
        end
      end)
    end

    field :operator_packet_readiness, non_null(:operator_packet_readiness) do
      arg(:input, non_null(:operator_packet_readiness_input))

      resolve(fn %{input: input}, _ ->
        case ApiSupport.read_operator_packet_readiness(input) do
          {:ok, readiness} -> {:ok, readiness}
          error -> graphql_error(error)
        end
      end)
    end

    field :operator_run_state, non_null(:operator_run_state) do
      arg(:id, non_null(:id))

      resolve(fn %{id: id}, _ ->
        case ApiSupport.read_operator_run_state(%{run_id: id}) do
          {:ok, run_state} -> {:ok, run_state}
          error -> graphql_error(error)
        end
      end)
    end

    field :operator_verification_outcome, non_null(:operator_verification_outcome) do
      arg(:id, non_null(:id))

      resolve(fn %{id: id}, _ ->
        case ApiSupport.read_operator_verification_outcome(%{run_id: id}) do
          {:ok, outcome} -> {:ok, outcome}
          error -> graphql_error(error)
        end
      end)
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

    field :execute_packet_run_verification, non_null(:packet_run_summary) do
      arg(:input, non_null(:execute_packet_run_verification_input))

      resolve(fn %{input: input}, _ ->
        case ApiSupport.execute_packet_run_verification(input) do
          {:ok, summary} -> {:ok, summary}
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

  defp graphql_error({:error, {:invalid_proposed_change, id}}) do
    {:error,
     message: "A proposed change failed validation.",
     extensions: %{code: "invalid_proposed_change", proposed_change_id: id}}
  end

  defp graphql_error({:error, {:invalid_proposed_change_set, reason}}) do
    {:error,
     message: "The proposed change set is invalid.",
     extensions: %{code: "invalid_proposed_change_set", reason: format_reason(reason)}}
  end

  defp graphql_error({:error, {:manual_intake_replay_conflict, accepted_id}}) do
    {:error,
     message: "Manual intake replay identity conflicts with an accepted event.",
     extensions: %{code: "manual_intake_replay_conflict", accepted_id: accepted_id}}
  end

  defp graphql_error({:error, {:missing_verification_check, id}}) do
    {:error,
     message: "A verification check could not be found.",
     extensions: %{code: "missing_verification_check", verification_check_id: id}}
  end

  defp graphql_error({:error, {:packet_run_flow_idempotency_conflict, flow_identity}}) do
    {:error,
     message: "The packet-run-verification flow identity conflicts with different input.",
     extensions: %{code: "idempotency_conflict", flow_identity: flow_identity}}
  end

  defp graphql_error({:error, {:observation_idempotency_conflict, observation_id}}) do
    {:error,
     message: "The observation source idempotency key conflicts with different input.",
     extensions: %{code: "idempotency_conflict", observation_id: observation_id}}
  end

  defp graphql_error({:error, {:invalid_verification_check_status, id}}) do
    {:error,
     message: "A verification check is no longer required.",
     extensions: %{code: "invalid_verification_check_status", verification_check_id: id}}
  end

  defp graphql_error({:error, {:packet_version_not_ready, id}}) do
    {:error,
     message: "The packet version is not ready for execution.",
     extensions: %{code: "packet_version_not_ready", packet_version_id: id}}
  end

  defp graphql_error({:error, {:not_found, _resource, id}}) do
    {:error,
     message: "A referenced record could not be found.", extensions: %{code: "not_found", id: id}}
  end

  defp graphql_error({:error, {:missing_normalized_intake_event, id}}) do
    {:error,
     message: "The operator workflow item could not be found.",
     extensions: %{code: "not_found", normalized_event_id: id}}
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
