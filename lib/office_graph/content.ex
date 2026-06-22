defmodule OfficeGraph.Content do
  @moduledoc """
  Public boundary for portable content and rich text persistence.
  """

  use Boundary, deps: [OfficeGraph.Repo], exports: []

  alias OfficeGraph.Content.{Document, DocumentBlock, DocumentRevision}
  alias OfficeGraph.Repo

  def create_plain_document(session_context, operation, plain_text) do
    with :ok <- validate_operation_context(session_context, operation) do
      document_id = Ecto.UUID.generate()

      Repo.transaction(fn ->
        with {:ok, document} <-
               ash_create(Document, %{
                 id: document_id,
                 organization_id: session_context.organization_id,
                 workspace_id: session_context.workspace_id,
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
  end

  defp validate_operation_context(session_context, operation)
       when is_map(session_context) and is_map(operation) do
    if operation.principal_id == session_context.principal_id and
         operation.session_id == session_context.session_id and
         operation.organization_id == session_context.organization_id and
         operation.workspace_id == session_context.workspace_id do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp validate_operation_context(_session_context, _operation), do: {:error, :forbidden}

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
