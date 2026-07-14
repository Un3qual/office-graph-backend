defmodule OfficeGraph.WorkGraph.RelationshipCycleConcurrencyTest do
  use OfficeGraph.TestSupport.ConcurrencySupport

  alias OfficeGraph.WorkGraph.{GraphItem, RelationshipRequest}

  test "concurrent depends_on writes cannot commit a cycle" do
    suffix = System.unique_integer([:positive])
    organization_slug = "relationship-cycle-#{suffix}"
    owner_email = "relationship-cycle-#{suffix}@office-graph.local"

    try do
      {bootstrap, operation, first_request, second_request} =
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

          {:ok, operation} =
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

          {bootstrap, operation, first_request, second_request}
        end)

      results =
        [first_request, second_request]
        |> Enum.map(fn request ->
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
