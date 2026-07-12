defmodule OfficeGraphWeb.GraphQL.OperatorWorkflow.Types do
  use Absinthe.Schema.Notation
  use Absinthe.Relay.Schema.Notation, :modern

  alias Absinthe.Relay.Connection
  alias OfficeGraph.Projections
  alias OfficeGraphWeb.GraphQL.Common.Errors
  alias OfficeGraphWeb.RequestSession

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

  object :operator_proposed_action_preview do
    field :action, non_null(:string)
    field :title, non_null(:string)
    field :status, non_null(:string)
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

  object :operator_command_affordance do
    field :identity, non_null(:string)
    field :state, non_null(:string)
    field :reason_codes, non_null(list_of(non_null(:string)))
    field :blocker_reasons, non_null(list_of(non_null(:string)))
    field :safe_explanation, non_null(:string)
    field :required_fields, non_null(list_of(non_null(:string)))
    field :input_defaults, non_null(list_of(non_null(:operator_command_input_default)))
    field :target_ids, non_null(list_of(non_null(:operator_typed_id)))
    field :trace_links, non_null(list_of(non_null(:operator_typed_id)))
    field :decision_links, non_null(list_of(non_null(:operator_typed_id)))
  end

  object :operator_command_input_default do
    field :field, non_null(:string)
    field :value, :string
    field :values, non_null(list_of(non_null(:string)))
  end

  object :operator_relationship_summary do
    field :graph_links, non_null(:integer)
    field :graph_relationships, non_null(:integer)
    field :has_more, non_null(:boolean)
  end

  node object(:operator_workflow_item,
         id_fetcher: &OfficeGraphWeb.GraphQL.OperatorWorkflow.Types.operator_workflow_item_id/2
       ) do
    field :type, non_null(:string)
    field :typed_id, non_null(:operator_typed_id)
    field :normalized_event_id, non_null(:id)
    field :duplicate_of_id, :id
    field :title, non_null(:string)
    field :source_summary, non_null(:string)

    field :proposed_action_previews,
          non_null(list_of(non_null(:operator_proposed_action_preview)))

    field :status, non_null(:string)
    field :reason_codes, non_null(list_of(non_null(:string)))
    field :source, non_null(:operator_source)
    field :proposed_change_status, non_null(:operator_proposed_change_status)
    field :blocker_reasons, non_null(list_of(non_null(:string)))
    field :allowed_next_actions, non_null(list_of(non_null(:string)))
    field :command_affordances, non_null(list_of(non_null(:operator_command_affordance)))
    field :operation_watermark, :id
    field :source_watermark, :id
    field :graph_links, non_null(list_of(non_null(:operator_graph_link)))
    field :graph_relationships, non_null(list_of(non_null(:operator_graph_relationship)))
    field :relationship_summary, non_null(:operator_relationship_summary)
    field :audit_trace, non_null(:operator_trace)
    field :revision_trace, non_null(:operator_trace)
  end

  connection(node_type: :operator_workflow_item)

  object :operator_relationship_detail do
    field :kind, non_null(:string)
    field :stable_id, non_null(:id)
    field :title, non_null(:string)
    field :status, :string
    field :source_graph_item_id, :id
    field :target_graph_item_id, :id
    field :relationship_type, non_null(:string)
  end

  connection(node_type: :operator_relationship_detail)

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
    field :command_affordances, non_null(list_of(non_null(:operator_command_affordance)))
    field :blocker_reasons, non_null(list_of(non_null(:string)))
    field :source_links, non_null(list_of(non_null(:operator_source_link)))
    field :required_checks, non_null(list_of(non_null(:operator_required_check)))
    field :source_watermark, :id
  end

  object :operator_packet_workspace_packet do
    field :id, non_null(:id)
    field :title, non_null(:string)
    field :state, non_null(:string)
    field :current_version_id, non_null(:id)
    field :operation_id, :id
  end

  object :operator_packet_workspace_version do
    field :id, non_null(:id)
    field :version_number, non_null(:integer)
    field :lifecycle_state, non_null(:string)
    field :title, non_null(:string)
    field :objective, non_null(:string)
    field :context_summary, non_null(:string)
    field :requirements, non_null(:string)
    field :success_criteria, :string
    field :autonomy_posture, non_null(:string)
    field :source_graph_item_ids, non_null(list_of(non_null(:id)))
    field :verification_check_ids, non_null(list_of(non_null(:id)))
    field :operation_id, non_null(:id)
    field :inserted_at, non_null(:datetime)
  end

  connection(node_type: :operator_packet_workspace_version)

  object :operator_packet_workspace do
    field :type, non_null(:string)
    field :source_watermark, non_null(:id)

    field :ready, non_null(:boolean) do
      resolve(fn workspace, _, _ -> {:ok, Map.fetch!(workspace, :ready?)} end)
    end

    field :status, non_null(:string)
    field :blocker_reasons, non_null(list_of(non_null(:string)))
    field :allowed_next_actions, non_null(list_of(non_null(:string)))
    field :command_affordances, non_null(list_of(non_null(:operator_command_affordance)))
    field :packet, non_null(:operator_packet_workspace_packet)
    field :current_version, non_null(:operator_packet_workspace_version)

    connection field :version_history,
                 node_type: :operator_packet_workspace_version,
                 paginate: :forward do
      resolve(fn
        %{first: first}, _resolution when is_integer(first) and first < 0 ->
          {:error, "A field has an invalid value."}

        args, %{source: workspace} = resolution ->
          with {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
               {:ok, :forward, limit} <- Connection.limit(args, 100),
               {:ok, page} <-
                 Projections.packet_version_history_page(session_context, workspace.packet.id,
                   limit: limit,
                   after_cursor: Map.get(args, :after)
                 ) do
            {:ok,
             %{
               edges: page.edges,
               page_info: %{
                 has_next_page: page.has_next_page?,
                 has_previous_page: page.has_previous_page?,
                 start_cursor: page.edges |> List.first() |> then(&(&1 && &1.cursor)),
                 end_cursor: page.edges |> List.last() |> then(&(&1 && &1.cursor))
               }
             }}
          else
            error -> Errors.to_absinthe(error)
          end
      end)
    end
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
    field :execution_observation_id, :id
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
    field :evidence_item_id, :id
    field :operation_id, :id
    field :actor_principal_id, :id
    field :policy_basis, :string
    field :target_graph_item_id, :id
    field :work_run_id, :id
    field :work_packet_version_id, :id
  end

  object :operator_missing_evidence do
    field :verification_check_id, non_null(:id)
    field :reason, non_null(:string)
  end

  object :operator_run_activity do
    field :kind, non_null(:string)
    field :stable_id, non_null(:id)
    field :title, non_null(:string)
    field :status, non_null(:string)
  end

  connection(node_type: :operator_run_activity)

  object :operator_run_child_summary do
    field :required_checks, non_null(:integer)
    field :observations, non_null(:integer)
    field :evidence_candidates, non_null(:integer)
    field :evidence_items, non_null(:integer)
    field :verification_results, non_null(:integer)
    field :missing_evidence, non_null(:integer)

    field :has_more, non_null(:boolean) do
      resolve(fn summary, _, _ -> {:ok, Map.fetch!(summary, :has_more?)} end)
    end
  end

  object :operator_observation_command_option do
    field :key, non_null(:id)
    field :label, non_null(:string)
    field :run_id, non_null(:id)
    field :verification_check_id, non_null(:id)
    field :source_graph_item_id, non_null(:id)
    field :observation_source_kind, non_null(:string)
    field :observation_source_identity, non_null(:string)
    field :freshness_state, non_null(:string)
    field :trust_basis, non_null(:string)
    field :default_outcome_key, non_null(:string)
    field :outcomes, non_null(list_of(non_null(:operator_observation_outcome_option)))
  end

  object :operator_observation_outcome_option do
    field :key, non_null(:string)
    field :label, non_null(:string)
    field :observed_status, non_null(:string)
    field :normalized_status, non_null(:string)
  end

  object :operator_evidence_candidate_command_option do
    field :key, non_null(:id)
    field :label, non_null(:string)
    field :work_run_id, non_null(:id)
    field :verification_check_id, non_null(:id)
    field :execution_observation_id, non_null(:id)
    field :source_kind, non_null(:string)
    field :source_identity, non_null(:string)
    field :freshness_state, non_null(:string)
    field :trust_basis, non_null(:string)
    field :sensitivity, non_null(:string)
  end

  object :operator_evidence_acceptance_command_option do
    field :key, non_null(:id)
    field :label, non_null(:string)
    field :evidence_candidate_id, non_null(:id)
    field :result, non_null(:string)
    field :acceptance_policy_basis, non_null(:string)
  end

  object :operator_waiver_command_option do
    field :key, non_null(:id)
    field :label, non_null(:string)
    field :run_id, non_null(:id)
    field :run_required_check_id, non_null(:id)
    field :expected_execution_state, non_null(:string)
    field :expected_verification_state, non_null(:string)
    field :policy_basis, non_null(:string)
  end

  object :operator_run_command_options do
    field :observation, non_null(list_of(non_null(:operator_observation_command_option)))

    field :evidence_candidate,
          non_null(list_of(non_null(:operator_evidence_candidate_command_option)))

    field :evidence_acceptance,
          non_null(list_of(non_null(:operator_evidence_acceptance_command_option)))

    field :waiver, non_null(list_of(non_null(:operator_waiver_command_option)))
  end

  object :operator_run_command_option_choice do
    field :kind, non_null(:string)
    field :key, non_null(:id)
    field :label, non_null(:string)
    field :observation, :operator_observation_command_option
    field :evidence_candidate, :operator_evidence_candidate_command_option
    field :evidence_acceptance, :operator_evidence_acceptance_command_option
    field :waiver, :operator_waiver_command_option
  end

  connection(node_type: :operator_run_command_option_choice)

  object :operator_run_command_option_summary do
    field :observation, non_null(:integer)
    field :evidence_candidate, non_null(:integer)
    field :evidence_acceptance, non_null(:integer)
    field :waiver, non_null(:integer)
  end

  object :operator_run_state do
    field :type, non_null(:string)
    field :status, non_null(:string)
    field :allowed_next_actions, non_null(list_of(non_null(:string)))
    field :command_affordances, non_null(list_of(non_null(:operator_command_affordance)))
    field :command_options, non_null(:operator_run_command_options)
    field :command_options_overflow, non_null(:boolean)
    field :command_option_summary, non_null(:operator_run_command_option_summary)

    field :child_summary, non_null(:operator_run_child_summary)

    connection field :activity, node_type: :operator_run_activity, paginate: :forward do
      resolve(fn
        %{first: first}, _resolution when is_integer(first) and first < 0 ->
          {:error, "A field has an invalid value."}

        args, %{source: run_state} = resolution ->
          with {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
               {:ok, :forward, limit} <- Connection.limit(args, 100),
               {:ok, page} <-
                 Projections.operator_run_activity_page(session_context, run_state.run.id,
                   limit: limit,
                   after_cursor: Map.get(args, :after)
                 ) do
            {:ok,
             %{
               edges: page.edges,
               page_info: %{
                 has_next_page: page.has_next_page?,
                 has_previous_page: page.has_previous_page?,
                 start_cursor: page.edges |> List.first() |> then(&(&1 && &1.cursor)),
                 end_cursor: page.edges |> List.last() |> then(&(&1 && &1.cursor))
               }
             }}
          else
            error -> Errors.to_absinthe(error)
          end
      end)
    end

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

  def operator_workflow_item_id(%{normalized_event_id: normalized_event_id}, _resolution) do
    normalized_event_id
  end

  def operator_workflow_item_id(_item, _resolution), do: nil
end
