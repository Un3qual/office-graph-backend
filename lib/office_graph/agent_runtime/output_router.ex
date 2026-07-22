defmodule OfficeGraph.AgentRuntime.OutputRouter do
  @moduledoc false

  alias OfficeGraph.{Audit, NodeConversations, ProposedChanges, Revisions, Runs, Verification}
  alias OfficeGraph.AgentRuntime.{AgentDefinition, ModelOutput, ToolOutput}

  def route!(operation, execution, context_package, step_key, output)
      when is_struct(output, ModelOutput) or is_struct(output, ToolOutput) do
    with :ok <- validate_output_kind(execution, output.classification) do
      routed = route_classification(output, operation, execution, context_package, step_key)

      case routed do
        {:error, reason} ->
          OfficeGraph.Repo.rollback(reason)

        resource ->
          record_traces!(operation, output.classification, resource)
          resource
      end
    else
      {:error, reason} -> OfficeGraph.Repo.rollback(reason)
    end
  end

  defp validate_output_kind(execution, classification) do
    output_kind = Atom.to_string(classification)

    case Ash.get(AgentDefinition, execution.definition_id,
           authorize?: false,
           not_found_error?: false
         ) do
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
