defmodule OfficeGraph.ContentSystemAccessTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.Content

  test "system document creation preserves classified operation-validation outages" do
    assert {:error, :integration_storage_unavailable} =
             Content.create_system_plain_document(unavailable_operation(), "Provider content")
  end

  test "system document reads preserve classified operation-validation outages" do
    assert {:error, :integration_storage_unavailable} =
             Content.system_plain_text_for_document(
               unavailable_operation(),
               Ecto.UUID.generate()
             )
  end

  defp unavailable_operation do
    %{
      id: Ecto.UUID.generate(),
      operation_kind: "system",
      action: "integration.reconcile",
      organization_id: Ecto.UUID.generate(),
      workspace_id: Ecto.UUID.generate(),
      principal_id: "invalid-principal-id",
      authority_basis: "github_installation:test",
      causation_key: "test-content-storage-boundary",
      idempotency_scope: "test-content-storage-boundary"
    }
  end
end
