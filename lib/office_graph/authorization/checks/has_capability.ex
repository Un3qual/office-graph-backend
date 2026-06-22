defmodule OfficeGraph.Authorization.Checks.HasCapability do
  @moduledoc false

  use Ash.Policy.SimpleCheck

  @impl true
  def describe(opts) do
    "actor has Office Graph capability #{inspect(opts[:capability])} for the target scope"
  end

  @impl true
  def match?(actor, context, opts) do
    capability = opts[:capability]

    with true <- not is_nil(actor),
         true <- not is_nil(capability),
         {:ok, organization_id, workspace_id} <- target_scope(context, actor),
         true <- scope_matches?(actor, organization_id, workspace_id),
         :ok <-
           OfficeGraph.Authorization.authorize(actor, capability,
             organization_id: organization_id
           ) do
      true
    else
      _ -> false
    end
  end

  defp target_scope(context, actor) do
    subject = subject(context)

    case subject do
      %Ash.Changeset{} = changeset ->
        changeset_scope(changeset)

      %Ash.Query{} ->
        actor_scope(actor)

      _subject ->
        if read_action?(context), do: actor_scope(actor), else: {:error, :missing_target_scope}
    end
  end

  defp subject(context) when is_map(context) do
    Map.get(context, :subject) || Map.get(context, :changeset) || Map.get(context, :query)
  end

  defp subject(_context), do: nil

  defp read_scope(%Ash.Changeset{action_type: :update} = changeset, field) do
    scope_value(changeset.data, field) || Map.get(changeset.attributes, field)
  end

  defp read_scope(%Ash.Changeset{} = changeset, field) do
    Map.get(changeset.attributes, field) || scope_value(changeset.data, field)
  end

  defp read_scope(_subject, _field), do: nil

  defp changeset_scope(changeset) do
    organization_id = read_scope(changeset, :organization_id)
    workspace_id = read_scope(changeset, :workspace_id)

    if is_nil(organization_id) or is_nil(workspace_id) do
      {:error, :missing_target_scope}
    else
      {:ok, organization_id, workspace_id}
    end
  end

  defp actor_scope(actor) do
    {:ok, scope_value(actor, :organization_id), scope_value(actor, :workspace_id)}
  end

  defp read_action?(context) when is_map(context) do
    case Map.get(context, :action) do
      %{type: :read} -> true
      _action -> false
    end
  end

  defp read_action?(_context), do: false

  defp scope_matches?(actor, organization_id, workspace_id) do
    scope_value(actor, :organization_id) == organization_id and
      (is_nil(workspace_id) or scope_value(actor, :workspace_id) == workspace_id)
  end

  defp scope_value(nil, _field), do: nil
  defp scope_value(data, field) when is_map(data), do: Map.get(data, field)
  defp scope_value(_data, _field), do: nil
end
