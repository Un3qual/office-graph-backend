defmodule OfficeGraph.ProposedChanges.ProposedGraphChange.OriginatingOperationActor do
  @moduledoc false

  use Ash.Policy.SimpleCheck

  alias OfficeGraph.Operations.OperationCorrelation

  @impl true
  def describe(opts), do: "actor owns proposed change operation #{inspect(opts[:action])}"

  @impl true
  def match?(actor, context, opts) do
    expected_action = opts[:action]

    with true <- is_map(actor),
         {:ok, operation_id, organization_id, workspace_id} <- proposed_change_context(context),
         {:ok, operation} <- fetch_operation(operation_id),
         true <- operation.action == expected_action,
         true <- operation.principal_id == actor.principal_id,
         true <- operation.session_id == actor.session_id,
         true <- operation.organization_id == organization_id,
         true <- operation.workspace_id == workspace_id,
         true <- actor.organization_id == organization_id,
         true <- actor.workspace_id == workspace_id do
      true
    else
      _ -> false
    end
  end

  defp proposed_change_context(context) when is_map(context) do
    context
    |> subject()
    |> case do
      %Ash.Changeset{} = changeset ->
        operation_id = read_value(changeset, :operation_id)
        organization_id = read_value(changeset, :organization_id)
        workspace_id = read_value(changeset, :workspace_id)

        if operation_id && organization_id && workspace_id do
          {:ok, operation_id, organization_id, workspace_id}
        else
          :error
        end

      _subject ->
        :error
    end
  end

  defp proposed_change_context(_context), do: :error

  defp subject(context), do: Map.get(context, :subject) || Map.get(context, :changeset)

  defp read_value(%Ash.Changeset{} = changeset, field) do
    Map.get(changeset.attributes, field) || scope_value(changeset.data, field)
  end

  defp scope_value(data, field) when is_map(data), do: Map.get(data, field)
  defp scope_value(_data, _field), do: nil

  defp fetch_operation(operation_id) do
    OperationCorrelation
    |> Ash.get(operation_id, authorize?: false, not_found_error?: false)
    |> case do
      {:ok, nil} -> :error
      {:ok, operation} -> {:ok, operation}
      {:error, _error} -> :error
    end
  end
end
