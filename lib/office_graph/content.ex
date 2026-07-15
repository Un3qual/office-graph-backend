defmodule OfficeGraph.Content do
  @moduledoc """
  Public boundary for portable content and rich text persistence.
  """

  use Boundary,
    deps: [OfficeGraph.Authorization, OfficeGraph.Operations, OfficeGraph.Repo],
    exports: []

  alias OfficeGraph.{Authorization, Operations}
  alias OfficeGraph.Content.{Document, DocumentBlock, DocumentRevision}
  alias OfficeGraph.Repo

  require Ash.Query

  @document_operation_capabilities %{
    "manual_intake.submit" => :manual_intake_submit,
    "proposed_change.apply" => :proposed_change_apply,
    "verification.complete" => :verification_complete,
    "work_packet.create" => :work_packet_create,
    "evidence.accept" => :evidence_accept
  }
  @document_operation_actions Map.keys(@document_operation_capabilities)

  def create_plain_document(session_context, operation, plain_text) do
    with :ok <- validate_operation_context(session_context, operation),
         :ok <- authorize_operation_capability(session_context, operation) do
      persist_plain_document(session_context, operation, plain_text)
    end
  end

  def create_system_plain_document(operation, plain_text)
      when is_map(operation) and is_binary(plain_text) do
    with :ok <- Operations.validate_system_operation(operation, :integration_reconcile),
         true <- is_binary(operation.workspace_id) do
      persist_plain_document(operation, operation, plain_text)
    else
      _invalid -> {:error, :forbidden}
    end
  end

  def create_system_plain_document(_operation, _plain_text), do: {:error, :forbidden}

  def plain_text_for_document(session_context, document_id) do
    plain_text_for_scope(session_context, document_id)
  end

  def system_plain_text_for_document(operation, document_id)
      when is_map(operation) and is_binary(document_id) do
    with :ok <- Operations.validate_system_operation(operation, :integration_reconcile),
         true <- is_binary(operation.workspace_id) do
      plain_text_for_scope(operation, document_id)
    else
      _invalid -> {:error, :forbidden}
    end
  end

  def system_plain_text_for_document(_operation, _document_id), do: {:error, :forbidden}

  defp plain_text_for_scope(scope, document_id) do
    Document
    |> Ash.Query.filter(id == ^document_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok,
       %{
         organization_id: organization_id,
         workspace_id: workspace_id,
         plain_text: plain_text
       }}
      when organization_id == scope.organization_id and workspace_id == scope.workspace_id ->
        {:ok, plain_text}

      {:ok, _missing_or_cross_scope} ->
        {:error, {:not_found, Document, document_id}}

      {:error, error} ->
        {:error, error}
    end
  end

  defp validate_operation_context(session_context, operation)
       when is_map(session_context) and is_map(operation) do
    cond do
      operation.principal_id != session_context.principal_id or
        operation.session_id != session_context.session_id or
        operation.organization_id != session_context.organization_id or
          operation.workspace_id != session_context.workspace_id ->
        {:error, :forbidden}

      operation.action not in @document_operation_actions ->
        {:error, {:invalid_content_operation, operation.id}}

      true ->
        :ok
    end
  end

  defp validate_operation_context(_session_context, _operation), do: {:error, :forbidden}

  defp authorize_operation_capability(session_context, operation) do
    case Map.fetch(@document_operation_capabilities, operation.action) do
      {:ok, capability} ->
        Authorization.authorize_operation(session_context, operation, capability,
          organization_id: session_context.organization_id
        )

      :error ->
        {:error, {:invalid_content_operation, operation.id}}
    end
  end

  defp persist_plain_document(scope, operation, plain_text) do
    document_id = Ecto.UUID.generate()

    Repo.transaction(fn ->
      with {:ok, document} <-
             ash_create(Document, %{
               id: document_id,
               organization_id: scope.organization_id,
               workspace_id: scope.workspace_id,
               plain_text: plain_text
             }),
           {:ok, _block} <-
             ash_create(DocumentBlock, %{
               id: Ecto.UUID.generate(),
               document_id: document_id,
               position: 0,
               block_type: "paragraph",
               text: plain_text
             }),
           {:ok, _revision} <-
             ash_create(DocumentRevision, %{
               id: Ecto.UUID.generate(),
               document_id: document_id,
               operation_id: operation.id,
               revision_number: 1,
               semantic_summary: "initial"
             }) do
        document
      else
        {:error, error} -> Repo.rollback(error)
      end
    end)
    |> case do
      {:ok, document} -> {:ok, document}
      {:error, error} -> {:error, error}
    end
  end

  defp ash_create(resource, attrs) do
    # Ash returns notifications for create actions when requested; Content has no
    # subscribers yet, so this boundary deliberately ignores them.
    resource
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create(authorize?: false, return_notifications?: true)
    |> case do
      {:ok, record, _notifications} -> {:ok, record}
      {:ok, record} -> {:ok, record}
      {:error, error} -> {:error, error}
    end
  end
end
