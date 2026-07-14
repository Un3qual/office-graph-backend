defmodule OfficeGraph.WorkGraph.CommandSupport do
  @moduledoc false

  alias OfficeGraph.Audit
  alias OfficeGraph.Content
  alias OfficeGraph.Operations
  alias OfficeGraph.Repo
  alias OfficeGraph.Revisions

  alias OfficeGraph.WorkGraph.{
    GraphItem,
    GraphRelationship,
    RelationshipDefinitions
  }

  require Ash.Query

  def transaction(fun) do
    Repo.transaction(fun)
  end

  def create_document!(session_context, operation, plain_text) do
    session_context
    |> Content.create_plain_document(operation, plain_text)
    |> unwrap_content()
  end

  # WorkGraph wraps Ash calls in graph transactions; request notifications so Ash
  # does not warn about missed dispatch, then ignore them until real notifiers exist.
  def ash_create(resource, attrs, session_context) do
    resource
    |> Ash.Changeset.for_create(:create, attrs, actor: session_context)
    |> Ash.create(authorize?: true, return_notifications?: true)
    |> unwrap_ash_result()
  end

  def ash_create_internal(resource, attrs) do
    resource
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create(authorize?: false, return_notifications?: true)
    |> unwrap_ash_result()
  end

  def ash_update_internal(record, action) do
    record
    |> Ash.Changeset.for_update(action, %{})
    |> Ash.update(authorize?: false, return_notifications?: true)
    |> unwrap_ash_result()
  end

  def ash_get(resource, id) do
    resource
    |> Ash.Query.filter(id == ^id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, {:not_found, resource, id}}
      result -> result
    end
  end

  def ash_get_for_update(resource, id) do
    resource
    |> Ash.Query.filter(id == ^id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, {:not_found, resource, id}}
      result -> result
    end
  end

  def unwrap_ash_result({:ok, record}) do
    {:ok, record}
  end

  def unwrap_ash_result({:ok, record, _notifications}) do
    {:ok, record}
  end

  def unwrap_ash_result({:error, error}) do
    {:error, error}
  end

  def unwrap_ash({:ok, record}) do
    record
  end

  def unwrap_ash({:error, error}) do
    Repo.rollback(error)
  end

  def unwrap_content({:ok, document}) do
    document
  end

  def unwrap_content({:error, error}) do
    Repo.rollback(error)
  end

  def validate_scope(session_context, record) do
    if record.organization_id == session_context.organization_id and
         record.workspace_id == session_context.workspace_id do
      :ok
    else
      {:error, :forbidden}
    end
  end

  def validate_scope!(session_context, record) do
    case validate_scope(session_context, record) do
      :ok -> :ok
      {:error, error} -> Repo.rollback(error)
    end
  end

  defdelegate validate_operation_context(session_context, operation), to: Operations

  defdelegate validate_operation_action(operation, expected_action), to: Operations

  def validate_open_review_finding!(%{lifecycle_state: "open"}), do: :ok

  def validate_open_review_finding!(review_finding) do
    Repo.rollback({:invalid_review_finding_status, review_finding.id})
  end

  def create_graph_item!(id, session_context, resource_type, resource_id, title) do
    ash_create_internal(
      GraphItem,
      %{
        id: id,
        organization_id: session_context.organization_id,
        workspace_id: session_context.workspace_id,
        resource_type: resource_type,
        resource_id: resource_id,
        title: title
      }
    )
    |> unwrap_ash()
  end

  def create_relationship!(
        session_context,
        operation,
        source_item_id,
        target_item_id,
        definition_key
      ) do
    definition =
      definition_key
      |> RelationshipDefinitions.fetch_by_key()
      |> unwrap_ash()

    ash_create_internal(
      GraphRelationship,
      %{
        id: Ecto.UUID.generate(),
        definition_id: definition.id,
        organization_id: session_context.organization_id,
        workspace_id: session_context.workspace_id,
        source_item_id: source_item_id,
        target_item_id: target_item_id,
        lifecycle: "active",
        asserting_principal_id: session_context.principal_id,
        operation_id: operation.id,
        valid_from: DateTime.utc_now()
      }
    )
    |> unwrap_ash()
  end

  def persisted_graph_item_id!(resource, id) do
    resource
    |> ash_get_for_update(id)
    |> unwrap_ash()
    |> Map.fetch!(:graph_item_id)
  end

  def trace!(operation, action, resource_type, resource_id) do
    Audit.record!(operation, action, resource_type, resource_id)
    Revisions.record!(operation, resource_type, resource_id, action, action)
  end
end
