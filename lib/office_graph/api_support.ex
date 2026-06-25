defmodule OfficeGraph.ApiSupport do
  @moduledoc """
  Public boundary for shared API context loading and response support.
  """

  use Boundary,
    deps: [
      OfficeGraph.Foundation,
      OfficeGraph.Integrations,
      OfficeGraph.Operations,
      OfficeGraph.ProposedChanges,
      OfficeGraph.Runs,
      OfficeGraph.Verification,
      OfficeGraph.WorkGraph,
      OfficeGraph.WorkPackets
    ],
    exports: []

  alias OfficeGraph.Foundation
  alias OfficeGraph.Integrations
  alias OfficeGraph.Operations
  alias OfficeGraph.ProposedChanges
  alias OfficeGraph.Runs
  alias OfficeGraph.Verification
  alias OfficeGraph.WorkGraph
  alias OfficeGraph.WorkPackets

  @packet_run_flow_digest_key "packet_run_flow_digest"
  @packet_run_operation_prefix "packet-run-verification"
  @packet_run_input_keys [
    :flow_identity,
    :verification_check_id,
    :source_graph_item_id,
    :packet_title,
    :objective,
    :context_summary,
    :requirements,
    :success_criteria,
    :autonomy_posture,
    :source_surface,
    :reason,
    :authority_posture,
    :observation_source_kind,
    :observation_source_identity,
    :observation_idempotency_key,
    :observed_status,
    :normalized_status,
    :freshness_state,
    :trust_basis,
    :observation_rationale,
    :evidence_claim,
    :evidence_title,
    :evidence_body,
    :evidence_result,
    :acceptance_policy_basis
  ]

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
         {:ok, bootstrap} <- bootstrap_local_api_owner(),
         {:ok, verification_check} <-
           WorkGraph.get_verification_check(bootstrap.session, input.verification_check_id),
         :ok <- validate_packet_run_source(input, verification_check),
         :ok <- validate_packet_run_ready_input(input),
         :ok <- validate_packet_run_passed_evidence_input(input),
         :ok <-
           Runs.preflight_observation_idempotency(
             bootstrap.session,
             packet_run_step_key(input, :observation),
             packet_run_observation_attrs(input)
           ),
         {:ok, packet_operation} <-
           Operations.start_operation(bootstrap.session, :work_packet_create,
             idempotency_key: packet_run_step_key(input, :packet),
             metadata: packet_run_flow_metadata(input)
           ),
         :ok <- validate_packet_run_flow_replay(packet_operation, input),
         {:ok, packet_result} <-
           WorkPackets.create_packet(bootstrap.session, packet_operation, %{
             title: input.packet_title,
             objective: input.objective,
             context_summary: input.context_summary,
             requirements: input.requirements,
             success_criteria: input.success_criteria,
             autonomy_posture: input.autonomy_posture,
             source_graph_item_ids: [input.source_graph_item_id],
             verification_check_ids: [input.verification_check_id]
           }),
         {:ok, run_operation} <-
           Operations.start_operation(bootstrap.session, :work_run_start,
             idempotency_key: packet_run_step_key(input, :run),
             metadata: packet_run_flow_metadata(input)
           ),
         :ok <- validate_packet_run_flow_replay(run_operation, input),
         {:ok, run_result} <-
           Runs.start_run(bootstrap.session, run_operation, packet_result.version, %{
             source_surface: input.source_surface,
             reason: input.reason,
             authority_posture: input.authority_posture
           }),
         {:ok, observation_operation} <-
           Operations.start_operation(bootstrap.session, :execution_observation_record,
             idempotency_key: packet_run_step_key(input, :observation),
             metadata: packet_run_flow_metadata(input)
           ),
         :ok <- validate_packet_run_flow_replay(observation_operation, input),
         {:ok, observation_result} <-
           Runs.record_observation(
             bootstrap.session,
             observation_operation,
             run_result.run,
             packet_run_observation_attrs(input)
           ),
         {:ok, candidate_operation} <-
           Operations.start_operation(bootstrap.session, :evidence_candidate_create,
             idempotency_key: packet_run_step_key(input, :candidate),
             metadata: packet_run_flow_metadata(input)
           ),
         :ok <- validate_packet_run_flow_replay(candidate_operation, input),
         {:ok, candidate} <-
           Verification.create_evidence_candidate(bootstrap.session, candidate_operation, %{
             work_run_id: run_result.run.id,
             verification_check_id: input.verification_check_id,
             execution_observation_id: observation_result.observation.id,
             claim: input.evidence_claim,
             source_kind: input.observation_source_kind,
             source_identity: input.observation_source_identity,
             freshness_state: input.freshness_state,
             trust_basis: input.trust_basis,
             sensitivity: "internal"
           }),
         {:ok, acceptance_operation} <-
           Operations.start_operation(bootstrap.session, :evidence_accept,
             idempotency_key: packet_run_step_key(input, :accept),
             metadata: packet_run_flow_metadata(input)
           ),
         :ok <- validate_packet_run_flow_replay(acceptance_operation, input),
         {:ok, accepted} <-
           Verification.accept_evidence_candidate(
             bootstrap.session,
             acceptance_operation,
             candidate,
             %{
               title: input.evidence_title,
               body: input.evidence_body,
               result: input.evidence_result,
               acceptance_policy_basis: input.acceptance_policy_basis
             }
           ) do
      Runs.get_summary(bootstrap.session, accepted.work_run.id)
    end
  end

  defp bootstrap_local_api_owner do
    if Application.get_env(:office_graph, :allow_local_api_owner_bootstrap, false) do
      Foundation.bootstrap_local_owner([])
    else
      {:error, :forbidden}
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

  defp validate_packet_run_source(input, verification_check) do
    if input.source_graph_item_id == verification_check.graph_item_id do
      :ok
    else
      {:error,
       {:source_graph_item_check_mismatch, input.source_graph_item_id, verification_check.id,
        verification_check.graph_item_id}}
    end
  end

  defp validate_packet_run_ready_input(input) do
    ready_attrs = %{
      objective: input.objective,
      success_criteria: input.success_criteria,
      autonomy_posture: input.autonomy_posture,
      source_graph_item_ids: [input.source_graph_item_id],
      verification_check_ids: [input.verification_check_id]
    }

    if WorkPackets.ready_for_execution_attrs?(ready_attrs) do
      :ok
    else
      {:error, {:invalid_packet_run_input, :packet_readiness}}
    end
  end

  defp validate_packet_run_passed_evidence_input(%{evidence_result: "passed"} = input) do
    if Verification.passed_evidence_input_acceptable?(input) do
      :ok
    else
      {:error, {:invalid_packet_run_evidence_input, :evidence_result}}
    end
  end

  defp validate_packet_run_passed_evidence_input(_input), do: :ok

  defp packet_run_flow_metadata(input) do
    %{
      "flow_identity" => input.flow_identity,
      @packet_run_flow_digest_key => packet_run_flow_digest(input)
    }
  end

  defp packet_run_step_key(input, step) do
    @packet_run_operation_prefix <> ":" <> input.flow_identity <> ":" <> Atom.to_string(step)
  end

  defp packet_run_observation_attrs(input) do
    %{
      source_kind: input.observation_source_kind,
      source_identity: input.observation_source_identity,
      idempotency_key: input.observation_idempotency_key,
      observed_status: input.observed_status,
      normalized_status: input.normalized_status,
      freshness_state: input.freshness_state,
      trust_basis: input.trust_basis,
      verification_check_id: input.verification_check_id,
      graph_item_id: input.source_graph_item_id,
      rationale: input.observation_rationale
    }
  end

  defp packet_run_flow_digest(input) do
    input
    |> Map.take(@packet_run_input_keys)
    |> Enum.map(fn {key, value} -> {Atom.to_string(key), value} end)
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp validate_packet_run_flow_replay(operation, input) do
    expected_digest = packet_run_flow_digest(input)

    case metadata_value(operation.metadata, @packet_run_flow_digest_key) do
      ^expected_digest -> :ok
      _other -> {:error, {:packet_run_flow_idempotency_conflict, input.flow_identity}}
    end
  end

  defp metadata_value(metadata, key) when is_map(metadata) do
    Map.get(metadata, key)
  end

  defp metadata_value(_metadata, _key), do: nil

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
