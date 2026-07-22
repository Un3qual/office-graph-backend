defmodule OfficeGraph.ProposedChanges.ProposedGraphChange.TraceReferenceScope do
  @moduledoc false

  use Ash.Resource.Change

  alias OfficeGraph.Integrations.NormalizedIntakeEvent
  alias OfficeGraph.Operations.OperationCorrelation

  require Ash.Query

  @manual_intake_action "manual_intake.submit"
  @agent_runtime_action "agent.runtime.execute"

  @trace_references [
    operation_id: OperationCorrelation,
    normalized_event_id: NormalizedIntakeEvent
  ]

  @impl true
  def change(changeset, _opts, context) do
    actor = Map.get(context, :actor)

    with {:ok, organization_id, workspace_id} <- target_scope(changeset) do
      @trace_references
      |> Enum.reduce(changeset, fn {field, resource}, changeset ->
        validate_reference(changeset, field, resource, organization_id, workspace_id, actor)
      end)
      |> validate_normalized_event_operation()
    else
      :error ->
        changeset
        |> Ash.Changeset.add_error(
          field: :organization_id,
          message: "proposed change scope is required for trace references"
        )
        |> Ash.Changeset.add_error(
          field: :workspace_id,
          message: "proposed change scope is required for trace references"
        )
    end
  end

  defp target_scope(changeset) do
    organization_id = Ash.Changeset.get_attribute(changeset, :organization_id)
    workspace_id = Ash.Changeset.get_attribute(changeset, :workspace_id)

    if is_nil(organization_id) or is_nil(workspace_id) do
      :error
    else
      {:ok, organization_id, workspace_id}
    end
  end

  defp validate_reference(
         changeset,
         :operation_id = field,
         OperationCorrelation = resource,
         organization_id,
         workspace_id,
         actor
       ) do
    case Ash.Changeset.get_attribute(changeset, field) do
      nil ->
        changeset

      id ->
        case fetch_reference(resource, id) do
          {:ok,
           %{
             organization_id: ^organization_id,
             workspace_id: ^workspace_id,
             principal_id: principal_id,
             session_id: session_id,
             action: @manual_intake_action
           }} ->
            if same_actor?(actor, principal_id, session_id) do
              changeset
            else
              add_operation_context_error(changeset)
            end

          {:ok,
           %{
             organization_id: ^organization_id,
             workspace_id: ^workspace_id,
             operation_kind: "system",
             action: @agent_runtime_action
           }} ->
            changeset

          {:ok, %{organization_id: ^organization_id, workspace_id: ^workspace_id}} ->
            add_operation_context_error(changeset)

          {:ok, _missing_or_cross_scope} ->
            add_scope_error(changeset, field)

          {:error, error} ->
            Ash.Changeset.add_error(
              changeset,
              field: field,
              message: "#{field} lookup failed: #{format_lookup_error(error)}"
            )
        end
    end
  end

  defp validate_reference(
         changeset,
         :normalized_event_id = field,
         NormalizedIntakeEvent = resource,
         organization_id,
         workspace_id,
         _actor
       ) do
    case Ash.Changeset.get_attribute(changeset, field) do
      nil ->
        changeset

      id ->
        case fetch_reference(resource, id) do
          {:ok,
           %{
             organization_id: ^organization_id,
             workspace_id: ^workspace_id,
             outcome: "accepted"
           }} ->
            changeset

          {:ok, %{organization_id: ^organization_id, workspace_id: ^workspace_id}} ->
            add_normalized_event_outcome_error(changeset)

          {:ok, _missing_or_cross_scope} ->
            add_scope_error(changeset, field)

          {:error, error} ->
            Ash.Changeset.add_error(
              changeset,
              field: field,
              message: "#{field} lookup failed: #{format_lookup_error(error)}"
            )
        end
    end
  end

  defp validate_reference(changeset, field, resource, organization_id, workspace_id, _actor) do
    case Ash.Changeset.get_attribute(changeset, field) do
      nil ->
        changeset

      id ->
        case fetch_reference(resource, id) do
          {:ok, %{organization_id: ^organization_id, workspace_id: ^workspace_id}} ->
            changeset

          {:ok, _missing_or_cross_scope} ->
            add_scope_error(changeset, field)

          {:error, error} ->
            Ash.Changeset.add_error(
              changeset,
              field: field,
              message: "#{field} lookup failed: #{format_lookup_error(error)}"
            )
        end
    end
  end

  defp validate_normalized_event_operation(%{valid?: false} = changeset), do: changeset

  defp validate_normalized_event_operation(changeset) do
    operation_id = Ash.Changeset.get_attribute(changeset, :operation_id)
    normalized_event_id = Ash.Changeset.get_attribute(changeset, :normalized_event_id)

    if is_nil(operation_id) or is_nil(normalized_event_id) do
      changeset
    else
      validate_normalized_event_operation(changeset, operation_id, normalized_event_id)
    end
  end

  defp validate_normalized_event_operation(changeset, operation_id, normalized_event_id) do
    case fetch_reference(NormalizedIntakeEvent, normalized_event_id) do
      {:ok, %{operation_id: ^operation_id}} ->
        changeset

      {:ok, _event} ->
        add_event_operation_error(changeset)

      {:error, error} ->
        Ash.Changeset.add_error(
          changeset,
          field: :normalized_event_id,
          message: "normalized_event_id lookup failed: #{format_lookup_error(error)}"
        )
    end
  end

  defp fetch_reference(resource, id) do
    resource
    |> Ash.Query.filter(id == ^id)
    |> Ash.read_one(authorize?: false)
  end

  defp add_scope_error(changeset, field) do
    Ash.Changeset.add_error(
      changeset,
      field: field,
      message: "#{field} must match proposed change scope"
    )
  end

  defp add_normalized_event_outcome_error(changeset) do
    Ash.Changeset.add_error(
      changeset,
      field: :normalized_event_id,
      message: "normalized_event_id must reference an accepted normalized intake event"
    )
  end

  defp add_operation_context_error(changeset) do
    Ash.Changeset.add_error(
      changeset,
      field: :operation_id,
      message: "operation_id must reference the current manual intake operation"
    )
  end

  defp add_event_operation_error(changeset) do
    Ash.Changeset.add_error(
      changeset,
      field: :normalized_event_id,
      message: "normalized_event_id must reference an event produced by operation_id"
    )
  end

  defp same_actor?(actor, principal_id, session_id) when is_map(actor) do
    actor.principal_id == principal_id and actor.session_id == session_id
  end

  defp same_actor?(_actor, _principal_id, _session_id), do: false

  defp format_lookup_error(%{__exception__: true} = error), do: Exception.message(error)
end
