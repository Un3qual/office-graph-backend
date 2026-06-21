defmodule OfficeGraph.Content do
  @moduledoc """
  Public boundary for portable content and rich text persistence.
  """

  use Boundary, deps: [OfficeGraph.Repo], exports: []

  alias Ecto.Multi
  alias OfficeGraph.Content.{Document, DocumentBlock, DocumentRevision}
  alias OfficeGraph.Repo

  def create_plain_document(session_context, operation, plain_text) do
    document_id = Ecto.UUID.generate()

    Multi.new()
    |> Multi.insert(
      :document,
      Document.changeset(%Document{id: document_id}, %{
        organization_id: session_context.organization_id,
        workspace_id: session_context.workspace_id,
        plain_text: plain_text
      })
    )
    |> Multi.insert(
      :block,
      DocumentBlock.changeset(%DocumentBlock{}, %{
        document_id: document_id,
        position: 0,
        block_type: "paragraph",
        text: plain_text
      })
    )
    |> Multi.insert(
      :revision,
      DocumentRevision.changeset(%DocumentRevision{}, %{
        document_id: document_id,
        operation_id: operation.id,
        revision_number: 1,
        semantic_summary: "initial"
      })
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{document: document}} -> {:ok, document}
      {:error, _step, changeset, _changes} -> {:error, changeset}
    end
  end
end
