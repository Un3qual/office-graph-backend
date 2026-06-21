defmodule OfficeGraph.WorkGraph.PersistenceTest do
  use OfficeGraph.DataCase, async: false

  require Ash.Query

  alias OfficeGraph.Content
  alias OfficeGraph.Content.{DocumentBlock, DocumentRevision}
  alias OfficeGraph.Foundation
  alias OfficeGraph.Integrations
  alias OfficeGraph.Operations
  alias OfficeGraph.Audit.AuditRecord
  alias OfficeGraph.WorkGraph

  setup do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)

    %{bootstrap: bootstrap, operation: operation}
  end

  test "operation correlation records preserve principal and scope", %{
    bootstrap: bootstrap,
    operation: operation
  } do
    assert operation.action == "manual_intake.submit"
    assert operation.principal_id == bootstrap.principal.id
    assert operation.organization_id == bootstrap.organization.id
    assert operation.workspace_id == bootstrap.workspace.id
    assert operation.correlation_id
  end

  test "internal audit creates default to sensitive records", %{operation: operation} do
    record =
      Ash.create!(
        AuditRecord,
        %{
          id: Ecto.UUID.generate(),
          operation_id: operation.id,
          actor_principal_id: operation.principal_id,
          action: "audit.default",
          resource_type: "signal",
          resource_id: Ecto.UUID.generate()
        },
        action: :create,
        authorize?: false
      )

    assert record.sensitive == true
  end

  test "graph identity and typed signal are created atomically", %{
    bootstrap: bootstrap,
    operation: operation
  } do
    assert {:ok, created} =
             WorkGraph.create_signal(bootstrap.session, operation, %{
               title: "Investigate flaky deploy",
               body: "Deploy check failed twice."
             })

    assert created.signal.graph_item_id == created.graph_item.id
    assert created.graph_item.resource_type == "signal"
    assert created.graph_item.resource_id == created.signal.id
    assert created.document.plain_text == "Deploy check failed twice."
  end

  test "plain document creation stores first block and initial revision through Ash", %{
    bootstrap: bootstrap,
    operation: operation
  } do
    assert {:ok, document} =
             Content.create_plain_document(
               bootstrap.session,
               operation,
               "Deploy check failed twice."
             )

    assert document.organization_id == bootstrap.organization.id
    assert document.workspace_id == bootstrap.workspace.id
    assert document.plain_text == "Deploy check failed twice."

    assert [
             %DocumentBlock{
               document_id: document_id,
               position: 0,
               block_type: "paragraph",
               text: "Deploy check failed twice."
             }
           ] =
             DocumentBlock
             |> Ash.Query.filter(document_id == ^document.id)
             |> Ash.read!(authorize?: false)

    assert document_id == document.id

    assert [
             %DocumentRevision{
               document_id: ^document_id,
               operation_id: operation_id,
               revision_number: 1,
               semantic_summary: "initial"
             }
           ] =
             DocumentRevision
             |> Ash.Query.filter(document_id == ^document.id)
             |> Ash.read!(authorize?: false)

    assert operation_id == operation.id
  end

  test "manual intake stores raw archive and identifies replay duplicates", %{
    bootstrap: bootstrap,
    operation: operation
  } do
    attrs = %{
      source_identity: "manual:web",
      replay_identity: "paste:deploy-123",
      body: "Task: Investigate flaky deploy"
    }

    assert {:ok, first} = Integrations.record_manual_intake(bootstrap.session, operation, attrs)
    assert first.duplicate? == false
    assert first.normalized_event.outcome == "accepted"
    assert first.raw_archive.content_hash

    assert {:ok, second} = Integrations.record_manual_intake(bootstrap.session, operation, attrs)
    assert second.duplicate? == true
    assert second.normalized_event.outcome == "duplicate"
    assert second.normalized_event.duplicate_of_id == first.normalized_event.id
  end
end
