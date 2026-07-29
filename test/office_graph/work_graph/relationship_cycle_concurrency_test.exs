defmodule OfficeGraph.WorkGraph.RelationshipCycleConcurrencyTest do
  use OfficeGraph.TestSupport.ConcurrencySupport

  alias OfficeGraph.WorkGraph.{GraphItem, GraphRelationship, RelationshipRequest}

  require Ash.Query

  test "concurrent depends_on writes cannot commit a cycle" do
    suffix = System.unique_integer([:positive])
    organization_slug = "relationship-cycle-#{suffix}"
    owner_email = "relationship-cycle-#{suffix}@office-graph.local"

    try do
      {bootstrap, operations, first_request, second_request} =
        with_unboxed_connection(fn ->
          {:ok, bootstrap} =
            Foundation.bootstrap_local_owner(
              organization_name: "Relationship Cycle #{suffix}",
              organization_slug: organization_slug,
              workspace_name: "Relationship Cycle Workspace #{suffix}",
              workspace_slug: "relationship-cycle-workspace-#{suffix}",
              initiative_name: "Relationship Cycle Initiative #{suffix}",
              initiative_slug: "relationship-cycle-initiative-#{suffix}",
              owner_email: owner_email
            )

          {:ok, first_operation} =
            Operations.start_operation(bootstrap.session, :graph_relationship_create)

          {:ok, second_operation} =
            Operations.start_operation(bootstrap.session, :graph_relationship_create)

          first_item = insert_graph_item!(bootstrap, "First cycle task")
          second_item = insert_graph_item!(bootstrap, "Second cycle task")

          first_request =
            RelationshipRequest.new!(%{
              definition_key: "depends_on",
              source_item_id: first_item.id,
              target_item_id: second_item.id,
              workspace_id: bootstrap.workspace.id
            })

          second_request = %{
            first_request
            | source_item_id: second_item.id,
              target_item_id: first_item.id
          }

          {bootstrap, [first_operation, second_operation], first_request, second_request}
        end)

      results =
        operations
        |> Enum.zip([first_request, second_request])
        |> Enum.map(fn {operation, request} ->
          Task.async(fn ->
            with_unboxed_connection(fn ->
              receive do
                :go ->
                  WorkGraph.create_relationship(bootstrap.session, operation, request)
              end
            end)
          end)
        end)
        |> then(fn tasks ->
          Enum.each(tasks, &send(&1.pid, :go))
          Task.await_many(tasks, 10_000)
        end)

      assert Enum.count(results, &match?({:ok, _}, &1)) == 1

      assert Enum.count(
               results,
               &match?({:error, {:relationship_cycle, "depends_on"}}, &1)
             ) == 1
    after
      with_unboxed_connection(fn ->
        cleanup_work_run_verification_scope!(organization_slug)
        cleanup_bootstrap_scope!(organization_slug, owner_email)
      end)
    end
  end

  test "concurrent operations replay one active relationship identity" do
    suffix = System.unique_integer([:positive])
    organization_slug = "relationship-identity-#{suffix}"
    owner_email = "relationship-identity-#{suffix}@office-graph.local"

    try do
      {bootstrap, operations, request} =
        with_unboxed_connection(fn ->
          {:ok, bootstrap} =
            Foundation.bootstrap_local_owner(
              organization_name: "Relationship Identity #{suffix}",
              organization_slug: organization_slug,
              workspace_name: "Relationship Identity Workspace #{suffix}",
              workspace_slug: "relationship-identity-workspace-#{suffix}",
              initiative_name: "Relationship Identity Initiative #{suffix}",
              initiative_slug: "relationship-identity-initiative-#{suffix}",
              owner_email: owner_email
            )

          {:ok, first_operation} =
            Operations.start_operation(bootstrap.session, :graph_relationship_create)

          {:ok, second_operation} =
            Operations.start_operation(bootstrap.session, :graph_relationship_create)

          source_item = insert_graph_item!(bootstrap, "Relationship identity source")
          target_item = insert_graph_item!(bootstrap, "Relationship identity target")

          request =
            RelationshipRequest.new!(%{
              definition_key: "depends_on",
              source_item_id: source_item.id,
              target_item_id: target_item.id,
              workspace_id: bootstrap.workspace.id
            })

          {bootstrap, [first_operation, second_operation], request}
        end)

      results =
        operations
        |> Enum.map(fn operation ->
          fn -> WorkGraph.create_relationship(bootstrap.session, operation, request) end
        end)
        |> run_concurrently()

      assert [{:ok, first}, {:ok, second}] = results
      assert first.id == second.id
      assert first.operation_id in Enum.map(operations, & &1.id)
      assert second.operation_id == first.operation_id

      with_unboxed_connection(fn ->
        relationships =
          GraphRelationship
          |> Ash.Query.filter(
            source_item_id == ^request.source_item_id and
              target_item_id == ^request.target_item_id and lifecycle == "active"
          )
          |> Ash.read!(authorize?: false)

        assert Enum.map(relationships, & &1.id) == [first.id]
      end)
    after
      with_unboxed_connection(fn ->
        cleanup_work_run_verification_scope!(organization_slug)
        cleanup_bootstrap_scope!(organization_slug, owner_email)
      end)
    end
  end

  defp insert_graph_item!(bootstrap, title) do
    Repo.ash_create!(
      GraphItem,
      %{
        id: Ecto.UUID.generate(),
        organization_id: bootstrap.organization.id,
        workspace_id: bootstrap.workspace.id,
        resource_type: "task",
        resource_id: Ecto.UUID.generate(),
        title: title
      }
    )
  end
end
