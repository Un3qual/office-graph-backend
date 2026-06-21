defmodule OfficeGraph.WorkGraph.PersistenceTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.Foundation
  alias OfficeGraph.Integrations
  alias OfficeGraph.Operations
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
