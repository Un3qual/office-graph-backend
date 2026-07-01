defmodule OfficeGraph.ApiSupport do
  @moduledoc """
  Public boundary for shared API context loading and response support.
  """

  use Boundary,
    deps: [
      OfficeGraph.Foundation,
      OfficeGraph.Identity,
      OfficeGraph.Integrations,
      OfficeGraph.Operations,
      OfficeGraph.PacketRunVerification,
      OfficeGraph.Projections,
      OfficeGraph.ProposedChanges,
      OfficeGraph.Verification,
      OfficeGraph.WorkGraph
    ],
    exports: []

  alias OfficeGraph.Foundation
  alias OfficeGraph.Identity.SessionContext
  alias OfficeGraph.Integrations
  alias OfficeGraph.Operations
  alias OfficeGraph.PacketRunVerification
  alias OfficeGraph.Projections
  alias OfficeGraph.ProposedChanges
  alias OfficeGraph.Verification
  alias OfficeGraph.WorkGraph

  def submit_manual_intake(params) do
    with {:ok, source_identity} <- required_string(params, :source_identity),
         {:ok, replay_identity} <- required_string(params, :replay_identity),
         {:ok, body} <- required_string(params, :body),
         {:ok, bootstrap} <- bootstrap_local_api_owner(),
         {:ok, operation} <- Operations.start_operation(bootstrap.session, :manual_intake_submit) do
      Integrations.submit_manual_intake(bootstrap.session, operation, %{
        source_identity: source_identity,
        replay_identity: replay_identity,
        body: body
      })
    end
  end

  def apply_proposed_changes(params) do
    with {:ok, ids} <- optional_id_list(params, :ids),
         :ok <- validate_apply_id_set(ids),
         {:ok, bootstrap} <- bootstrap_local_api_owner(),
         {:ok, proposed_changes} <- ProposedChanges.get_many(bootstrap.session, ids),
         {:ok, operation} <- Operations.start_operation(bootstrap.session, :proposed_change_apply) do
      ProposedChanges.apply_all(bootstrap.session, operation, proposed_changes)
    end
  end

  def complete_verification(params) do
    with {:ok, verification_check_id} <- required_id(params, :verification_check_id),
         {:ok, title} <- required_string(params, :title),
         {:ok, body} <- required_string(params, :body),
         {:ok, artifact_uri} <- optional_string(params, :artifact_uri),
         {:ok, bootstrap} <- bootstrap_local_api_owner(),
         {:ok, verification_check} <-
           WorkGraph.get_verification_check(bootstrap.session, verification_check_id),
         {:ok, operation} <- Operations.start_operation(bootstrap.session, :verification_complete) do
      Verification.complete_with_evidence(bootstrap.session, operation, verification_check, %{
        title: title,
        body: body,
        artifact_uri: artifact_uri
      })
    end
  end

  def execute_packet_run_verification(params) do
    with {:ok, input} <- packet_run_input(params),
         {:ok, bootstrap} <- bootstrap_local_api_owner() do
      PacketRunVerification.execute(bootstrap.session, input)
    end
  end

  def read_operator_inbox(params \\ %{}) do
    with {:ok, session_context} <- read_session_context(params) do
      Projections.operator_inbox(session_context)
    end
  end

  def read_operator_workflow_item(params) do
    with {:ok, normalized_event_id} <- required_id(params, :normalized_event_id),
         {:ok, session_context} <- read_session_context(params) do
      Projections.operator_workflow_item(session_context, normalized_event_id)
    end
  end

  def read_operator_packet_readiness(params) do
    with {:ok, input} <- packet_readiness_input(params),
         {:ok, session_context} <- read_session_context(params) do
      Projections.packet_readiness(session_context, input)
    end
  end

  def read_operator_run_state(params) do
    with {:ok, run_id} <- required_id(params, :run_id),
         {:ok, session_context} <- read_session_context(params) do
      Projections.operator_run_state(session_context, run_id)
    end
  end

  def read_operator_verification_outcome(params) do
    with {:ok, run_id} <- required_id(params, :run_id),
         {:ok, session_context} <- read_session_context(params) do
      Projections.verification_outcome(session_context, run_id)
    end
  end

  def with_request_session_context(params, actor) when is_map(params) do
    cond do
      Map.has_key?(params, "session_context") or Map.has_key?(params, :session_context) ->
        params

      match?(%SessionContext{}, actor) ->
        Map.put(params, :session_context, actor)

      true ->
        params
    end
  end

  def bootstrap_local_api_owner do
    if Application.get_env(:office_graph, :allow_local_api_owner_bootstrap, false) do
      Foundation.bootstrap_local_owner([])
    else
      {:error, :forbidden}
    end
  end

  defp read_session_context(params) do
    case value(params, :session_context) do
      nil ->
        with {:ok, bootstrap} <- bootstrap_local_api_owner() do
          {:ok, bootstrap.session}
        end

      %SessionContext{} = session_context ->
        {:ok, session_context}

      _other ->
        {:error, {:invalid_field, :session_context}}
    end
  end

  defp required_id(params, key) do
    case value(params, key) do
      value when is_binary(value) ->
        if String.trim(value) == "" do
          {:error, {:missing_field, key}}
        else
          cast_id(value, key)
        end

      nil ->
        {:error, {:missing_field, key}}

      _other ->
        {:error, {:invalid_field, key}}
    end
  end

  defp required_string(params, key) do
    case value(params, key) do
      value when is_binary(value) ->
        if String.trim(value) == "" do
          {:error, {:missing_field, key}}
        else
          {:ok, value}
        end

      nil ->
        {:error, {:missing_field, key}}

      _other ->
        {:error, {:invalid_field, key}}
    end
  end

  defp optional_string(params, key) do
    case value(params, key) do
      value when is_binary(value) -> {:ok, value}
      nil -> {:ok, nil}
      _other -> {:error, {:invalid_field, key}}
    end
  end

  defp packet_readiness_input(params) do
    with {:ok, source_graph_item_ids} <- optional_id_list(params, :source_graph_item_ids),
         {:ok, verification_check_ids} <- optional_id_list(params, :verification_check_ids),
         {:ok, title} <- optional_string(params, :title),
         {:ok, objective} <- optional_string(params, :objective),
         {:ok, context_summary} <- optional_string(params, :context_summary),
         {:ok, requirements} <- optional_string(params, :requirements),
         {:ok, success_criteria} <- optional_string(params, :success_criteria),
         {:ok, autonomy_posture} <- optional_string(params, :autonomy_posture) do
      {:ok,
       %{
         title: title,
         objective: objective,
         context_summary: context_summary,
         requirements: requirements,
         success_criteria: success_criteria,
         autonomy_posture: autonomy_posture,
         source_graph_item_ids: source_graph_item_ids,
         verification_check_ids: verification_check_ids
       }}
    end
  end

  defp packet_run_input(params) do
    with {:ok, flow_identity} <- required_string(params, :flow_identity),
         {:ok, verification_check_id} <- required_id(params, :verification_check_id),
         {:ok, source_graph_item_id} <- required_id(params, :source_graph_item_id),
         {:ok, packet_title} <- required_string(params, :packet_title),
         {:ok, objective} <- required_string(params, :objective),
         {:ok, context_summary} <- required_string(params, :context_summary),
         {:ok, requirements} <- required_string(params, :requirements),
         {:ok, success_criteria} <- required_string(params, :success_criteria),
         {:ok, autonomy_posture} <- required_string(params, :autonomy_posture),
         {:ok, source_surface} <- required_string(params, :source_surface),
         {:ok, reason} <- required_string(params, :reason),
         {:ok, authority_posture} <- required_string(params, :authority_posture),
         {:ok, observation_source_kind} <- required_string(params, :observation_source_kind),
         {:ok, observation_source_identity} <-
           required_string(params, :observation_source_identity),
         {:ok, observation_idempotency_key} <-
           required_string(params, :observation_idempotency_key),
         {:ok, observed_status} <- required_string(params, :observed_status),
         {:ok, normalized_status} <- required_string(params, :normalized_status),
         {:ok, freshness_state} <- required_string(params, :freshness_state),
         {:ok, trust_basis} <- required_string(params, :trust_basis),
         {:ok, observation_rationale} <- required_string(params, :observation_rationale),
         {:ok, evidence_claim} <- required_string(params, :evidence_claim),
         {:ok, evidence_title} <- required_string(params, :evidence_title),
         {:ok, evidence_body} <- required_string(params, :evidence_body),
         {:ok, evidence_result} <- required_string(params, :evidence_result),
         {:ok, acceptance_policy_basis} <- required_string(params, :acceptance_policy_basis) do
      {:ok,
       %{
         flow_identity: flow_identity,
         verification_check_id: verification_check_id,
         source_graph_item_id: source_graph_item_id,
         packet_title: packet_title,
         objective: objective,
         context_summary: context_summary,
         requirements: requirements,
         success_criteria: success_criteria,
         autonomy_posture: autonomy_posture,
         source_surface: source_surface,
         reason: reason,
         authority_posture: authority_posture,
         observation_source_kind: observation_source_kind,
         observation_source_identity: observation_source_identity,
         observation_idempotency_key: observation_idempotency_key,
         observed_status: observed_status,
         normalized_status: normalized_status,
         freshness_state: freshness_state,
         trust_basis: trust_basis,
         observation_rationale: observation_rationale,
         evidence_claim: evidence_claim,
         evidence_title: evidence_title,
         evidence_body: evidence_body,
         evidence_result: evidence_result,
         acceptance_policy_basis: acceptance_policy_basis
       }}
    end
  end

  defp validate_apply_id_set([]) do
    {:error, {:invalid_proposed_change_set, {:missing_change_type, "create_signal"}}}
  end

  defp validate_apply_id_set(_ids), do: :ok

  defp optional_id_list(params, key) do
    case value(params, key) do
      nil ->
        {:ok, []}

      values when is_list(values) ->
        cast_id_list(values, key)

      _other ->
        {:error, {:invalid_field, key}}
    end
  end

  defp cast_id_list(values, key) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, ids} ->
      case cast_id(value, key) do
        {:ok, id} -> {:cont, {:ok, [id | ids]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, ids} -> {:ok, Enum.reverse(ids)}
      error -> error
    end
  end

  defp cast_id(value, key) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, {:invalid_field, key}}
    end
  end

  defp cast_id(_value, key), do: {:error, {:invalid_field, key}}

  defp value(params, key) do
    cond do
      Map.has_key?(params, key) -> params[key]
      Map.has_key?(params, to_string(key)) -> params[to_string(key)]
      true -> nil
    end
  end
end
