defmodule OfficeGraph.PacketRunVerification do
  @moduledoc """
  Domain command boundary for the packet-run-verification workflow.
  """

  use Boundary,
    deps: [
      OfficeGraph.Operations,
      OfficeGraph.Repo,
      OfficeGraph.Runs,
      OfficeGraph.Verification,
      OfficeGraph.WorkGraph,
      OfficeGraph.WorkPackets
    ],
    exports: []

  alias OfficeGraph.Operations
  alias OfficeGraph.Repo
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

  def execute(session_context, input) when is_map(session_context) and is_map(input) do
    with {:ok, verification_check} <-
           WorkGraph.get_verification_check(session_context, input.verification_check_id),
         :ok <- validate_source(input, verification_check),
         :ok <- validate_ready_input(input),
         :ok <- validate_evidence_result(input),
         :ok <- validate_passed_evidence_input(input) do
      execute_transaction(session_context, input)
    end
  end

  def prepare_packet(session_context, input) do
    with {:ok, operation} <-
           Operations.start_operation(session_context, :work_packet_create,
             idempotency_key: step_key(input, :packet),
             metadata: flow_metadata(input)
           ),
         :ok <- validate_flow_replay(operation, input) do
      WorkPackets.create_packet(session_context, operation, %{
        title: input.packet_title,
        objective: input.objective,
        context_summary: input.context_summary,
        requirements: input.requirements,
        success_criteria: input.success_criteria,
        autonomy_posture: input.autonomy_posture,
        source_graph_item_ids: [input.source_graph_item_id],
        verification_check_ids: [input.verification_check_id]
      })
    end
  end

  def start_run(session_context, input, packet_result) do
    with {:ok, operation} <-
           Operations.start_operation(session_context, :work_run_start,
             idempotency_key: step_key(input, :run),
             metadata: flow_metadata(input)
           ),
         :ok <- validate_flow_replay(operation, input) do
      Runs.start_run(session_context, operation, packet_result.version, %{
        source_surface: input.source_surface,
        reason: input.reason,
        authority_posture: input.authority_posture
      })
    end
  end

  def record_execution_observation(session_context, input, run) do
    with {:ok, operation} <-
           Operations.start_operation(session_context, :execution_observation_record,
             idempotency_key: step_key(input, :observation),
             metadata: flow_metadata(input)
           ),
         :ok <- validate_flow_replay(operation, input) do
      Runs.record_observation(
        session_context,
        operation,
        run,
        observation_attrs(input)
      )
    end
  end

  def suggest_evidence(session_context, input, run, observation) do
    with {:ok, operation} <-
           Operations.start_operation(session_context, :evidence_candidate_create,
             idempotency_key: step_key(input, :candidate),
             metadata: flow_metadata(input)
           ),
         :ok <- validate_flow_replay(operation, input) do
      Verification.create_evidence_candidate(session_context, operation, %{
        work_run_id: run.id,
        verification_check_id: input.verification_check_id,
        execution_observation_id: observation.id,
        claim: input.evidence_claim,
        source_kind: input.observation_source_kind,
        source_identity: input.observation_source_identity,
        freshness_state: input.freshness_state,
        trust_basis: input.trust_basis,
        sensitivity: "internal"
      })
    end
  end

  def accept_evidence(session_context, input, candidate) do
    with {:ok, operation} <-
           Operations.start_operation(session_context, :evidence_accept,
             idempotency_key: step_key(input, :accept),
             metadata: flow_metadata(input)
           ),
         :ok <- validate_flow_replay(operation, input) do
      Verification.accept_evidence_candidate(session_context, operation, candidate, %{
        title: input.evidence_title,
        body: input.evidence_body,
        result: input.evidence_result,
        acceptance_policy_basis: input.acceptance_policy_basis
      })
    end
  end

  defp execute_transaction(session_context, input) do
    Repo.transaction(fn ->
      case execute_steps(session_context, input) do
        {:ok, summary} -> summary
        {:error, error} -> Repo.rollback(error)
      end
    end)
    |> case do
      {:ok, summary} -> {:ok, summary}
      {:error, error} -> {:error, error}
    end
  end

  defp execute_steps(session_context, input) do
    Runs.with_observation_idempotency_lock(
      session_context,
      observation_attrs(input),
      fn ->
        do_execute_steps(session_context, input)
      end
    )
  end

  defp do_execute_steps(session_context, input) do
    with :ok <-
           Runs.preflight_observation_idempotency(
             session_context,
             step_key(input, :observation),
             observation_attrs(input)
           ),
         {:ok, packet_result} <- prepare_packet(session_context, input),
         {:ok, run_result} <- start_run(session_context, input, packet_result),
         {:ok, observation_result} <-
           record_execution_observation(session_context, input, run_result.run),
         {:ok, candidate} <-
           suggest_evidence(
             session_context,
             input,
             run_result.run,
             observation_result.observation
           ),
         {:ok, accepted} <- accept_evidence(session_context, input, candidate) do
      Runs.get_summary(session_context, accepted.work_run.id)
    end
  end

  defp validate_source(input, verification_check) do
    if input.source_graph_item_id == verification_check.graph_item_id do
      :ok
    else
      {:error,
       {:source_graph_item_check_mismatch, input.source_graph_item_id, verification_check.id,
        verification_check.graph_item_id}}
    end
  end

  defp validate_ready_input(input) do
    ready_attrs = %{
      objective: input.objective,
      context_summary: input.context_summary,
      requirements: input.requirements,
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

  defp validate_evidence_result(%{evidence_result: result})
       when result in ["passed", "failed"] do
    :ok
  end

  defp validate_evidence_result(%{evidence_result: result}) do
    {:error, {:invalid_evidence_result, result}}
  end

  defp validate_passed_evidence_input(%{evidence_result: "passed"} = input) do
    if Verification.passed_evidence_input_acceptable?(input) do
      :ok
    else
      {:error, {:invalid_packet_run_evidence_input, :evidence_result}}
    end
  end

  defp validate_passed_evidence_input(_input), do: :ok

  defp flow_metadata(input) do
    %{
      "flow_identity" => input.flow_identity,
      @packet_run_flow_digest_key => flow_digest(input)
    }
  end

  defp step_key(input, step) do
    @packet_run_operation_prefix <> ":" <> input.flow_identity <> ":" <> Atom.to_string(step)
  end

  defp observation_attrs(input) do
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

  defp flow_digest(input) do
    input
    |> Map.take(@packet_run_input_keys)
    |> Enum.map(fn {key, value} -> {Atom.to_string(key), value} end)
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp validate_flow_replay(operation, input) do
    expected_digest = flow_digest(input)

    case metadata_value(operation.metadata, @packet_run_flow_digest_key) do
      ^expected_digest -> :ok
      _other -> {:error, {:packet_run_flow_idempotency_conflict, input.flow_identity}}
    end
  end

  defp metadata_value(metadata, key) when is_map(metadata) do
    Map.get(metadata, key)
  end

  defp metadata_value(_metadata, _key), do: nil
end
