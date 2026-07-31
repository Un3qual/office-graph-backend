defmodule OfficeGraph.AgentRuntime.OutputRouter do
  @moduledoc false

  alias OfficeGraph.{Audit, NodeConversations, ProposedChanges, Revisions, Runs, Verification}

  alias OfficeGraph.AgentRuntime.{
    ActionSupport,
    AgentDefinition,
    AgentExecution,
    AuthoritySnapshot,
    ModelOutput,
    ToolOutput
  }

  @output_capabilities %{
    proposal: "proposal.create",
    finding: "proposal.create",
    evidence_candidate: "evidence.suggest",
    message: nil,
    observation: nil
  }

  @behaviour Ash.Resource.Actions.Implementation

  def route(operation, execution, context_package, step_key, output)
      when is_struct(output, ModelOutput) or is_struct(output, ToolOutput) do
    AgentExecution
    |> Ash.ActionInput.for_action(:route_output_contract, %{
      operation: operation,
      execution: execution,
      context_package: context_package,
      step_key: step_key,
      output: output
    })
    |> Ash.run_action(authorize?: false)
    |> ActionSupport.normalize_action_result()
  end

  def route!(operation, execution, context_package, step_key, output)
      when is_struct(output, ModelOutput) or is_struct(output, ToolOutput) do
    case route_in_transaction(operation, execution, context_package, step_key, output) do
      {:ok, resource} -> resource
      {:error, reason} -> ActionSupport.rollback(AgentExecution, reason)
    end
  end

  @impl true
  def run(input, [mode: :route], _context) do
    attrs = input.arguments

    case route_in_transaction(
           attrs.operation,
           attrs.execution,
           attrs.context_package,
           attrs.step_key,
           attrs.output
         ) do
      {:ok, resource} -> {:ok, resource}
      {:error, reason} -> ActionSupport.rollback(AgentExecution, reason)
    end
  end

  defp route_in_transaction(operation, execution, context_package, step_key, output) do
    with :ok <- validate_output_kind(execution, context_package, output.classification),
         resource when not is_tuple(resource) <-
           route_classification(output, operation, execution, context_package, step_key) do
      record_traces!(operation, output.classification, resource)
      {:ok, resource}
    end
  end

  defp validate_output_kind(execution, context_package, classification) do
    output_kind = Atom.to_string(classification)

    with {:ok, required_capability} <- Map.fetch(@output_capabilities, classification),
         :ok <- validate_definition_output_kind(execution, output_kind),
         :ok <-
           validate_snapshot_capability(
             execution,
             context_package,
             output_kind,
             required_capability
           ) do
      :ok
    else
      :error -> {:error, {:agent_output_kind_not_allowed, output_kind}}
      {:error, _reason} = error -> error
    end
  end

  defp validate_definition_output_kind(execution, output_kind) do
    AgentDefinition
    |> Ash.get(execution.definition_id, authorize?: false, not_found_error?: false)
    |> case do
      {:ok, %AgentDefinition{allowed_output_kinds: allowed}} ->
        if output_kind in allowed,
          do: :ok,
          else: {:error, {:agent_output_kind_not_allowed, output_kind}}

      {:ok, _missing_or_disallowed} ->
        {:error, {:agent_output_kind_not_allowed, output_kind}}

      {:error, _storage_error} ->
        {:error, :integration_storage_unavailable}
    end
  end

  defp validate_snapshot_capability(_execution, _context_package, _output_kind, nil),
    do: :ok

  defp validate_snapshot_capability(execution, context_package, output_kind, required_capability) do
    AuthoritySnapshot
    |> Ash.get(context_package.authority_snapshot_id,
      authorize?: false,
      not_found_error?: false
    )
    |> case do
      {:ok, %AuthoritySnapshot{} = snapshot} ->
        cond do
          snapshot.execution_id != execution.id or
              context_package.execution_id != execution.id ->
            {:error, :authority_snapshot_invalid}

          required_capability in snapshot.capability_keys ->
            :ok

          true ->
            {:error, {:agent_output_capability_not_authorized, output_kind, required_capability}}
        end

      {:ok, nil} ->
        {:error, :authority_snapshot_invalid}

      {:error, _storage_error} ->
        {:error, :integration_storage_unavailable}
    end
  end

  defp route_classification(
         %{classification: classification, safe_summary: summary},
         operation,
         execution,
         context_package,
         step_key
       )
       when classification in [:proposal, :finding] do
    ProposedChanges.create_from_agent(
      operation,
      execution,
      context_package,
      step_key,
      classification,
      summary
    )
  end

  defp route_classification(
         %{classification: :evidence_candidate, safe_summary: summary},
         operation,
         execution,
         context_package,
         step_key
       ) do
    Verification.create_agent_evidence_candidate(
      operation,
      execution,
      context_package,
      step_key,
      summary
    )
  end

  defp route_classification(
         %{classification: :message, safe_summary: summary},
         operation,
         execution,
         context_package,
         step_key
       ) do
    NodeConversations.append_agent_message(
      operation,
      execution,
      context_package,
      step_key,
      summary
    )
  end

  defp route_classification(
         %{classification: :observation, safe_summary: summary},
         operation,
         execution,
         context_package,
         step_key
       ) do
    Runs.record_agent_observation(
      operation,
      execution,
      context_package,
      step_key,
      summary
    )
  end

  defp record_traces!(operation, classification, resource) do
    resource_type = resource_type(classification)
    action = "agent_output.#{classification}"

    Audit.record_once!(operation, action, resource_type, resource.id)
    Revisions.record_once!(operation, resource_type, resource.id, action, "Routed #{action}")
  end

  defp resource_type(classification) when classification in [:proposal, :finding],
    do: "proposed_graph_change"

  defp resource_type(:evidence_candidate), do: "evidence_candidate"
  defp resource_type(:message), do: "conversation_message"
  defp resource_type(:observation), do: "execution_observation"
end
