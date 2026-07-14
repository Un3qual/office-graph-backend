defmodule OfficeGraph.WorkGraph.RelationshipOperationPolicy do
  @moduledoc false

  @direct_actions %{
    create: "graph_relationship.create",
    supersede: "graph_relationship.supersede",
    archive: "graph_relationship.archive",
    restore: "graph_relationship.restore"
  }

  @direct_authorization_actions %{
    create: :graph_relationship_create,
    supersede: :graph_relationship_supersede,
    archive: :graph_relationship_archive,
    restore: :graph_relationship_restore
  }

  @embedded_create_actions %{
    "proposed_change.apply" =>
      MapSet.new(["generated_from", "review_finding_for", "requires_check"]),
    "verification.complete" => MapSet.new(["evidenced_by", "generated_from"]),
    "evidence.accept" => MapSet.new(["evidenced_by", "generated_from"]),
    "integration.reconcile" => :registered_definition
  }

  @embedded_authorization_actions %{
    "proposed_change.apply" => :proposed_change_apply,
    "verification.complete" => :verification_complete,
    "evidence.accept" => :evidence_accept,
    "integration.reconcile" => :graph_relationship_create
  }

  def validate(operation, definition, :create) do
    case Map.get(@embedded_create_actions, operation.action) do
      :registered_definition -> :ok
      %MapSet{} = keys -> if MapSet.member?(keys, definition.key), do: :ok, else: forbidden()
      nil -> validate_direct(operation, :create)
    end
  end

  def validate(operation, _definition, lifecycle_action) do
    validate_direct(operation, lifecycle_action)
  end

  def authorization_action(operation, :create) do
    Map.get(
      @embedded_authorization_actions,
      operation.action,
      @direct_authorization_actions.create
    )
  end

  def authorization_action(_operation, lifecycle_action) do
    Map.fetch!(@direct_authorization_actions, lifecycle_action)
  end

  defp validate_direct(operation, action) do
    if Map.fetch!(@direct_actions, action) == operation.action, do: :ok, else: forbidden()
  end

  defp forbidden, do: {:error, :forbidden}
end
