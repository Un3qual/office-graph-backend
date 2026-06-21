defmodule OfficeGraph.WorkGraph.AshAuthorizationTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.Content.Document
  alias OfficeGraph.Foundation
  alias OfficeGraph.Operations
  alias OfficeGraph.WorkGraph
  alias OfficeGraph.WorkGraph.GraphItem
  alias OfficeGraph.WorkGraph.Resources.Signal, as: SignalResource
  alias OfficeGraph.WorkGraph.Resources.Task, as: TaskResource

  test "Ash reads are filtered to the actor organization and workspace" do
    {:ok, actor_scope} = bootstrap_scope("read-actor")
    {:ok, other_scope} = bootstrap_scope("read-other")

    actor_signal = create_signal!(actor_scope, "Visible signal")
    other_signal = create_signal!(other_scope, "Hidden signal")

    assert [%SignalResource{id: visible_id}] =
             Ash.read!(SignalResource, actor: actor_scope.session)

    assert visible_id == actor_signal.id
    refute visible_id == other_signal.id
  end

  test "cross-scope linked creates are rejected" do
    {:ok, actor_scope} = bootstrap_scope("linked-actor")
    {:ok, other_scope} = bootstrap_scope("linked-other")

    other_signal = create_signal!(other_scope, "Foreign source signal")
    task_id = Ecto.UUID.generate()
    graph_item = insert_graph_item!(actor_scope, "task", task_id, "Local task graph item")
    document = insert_document!(actor_scope, "Local task body")

    assert {:error, error} =
             Ash.create(
               TaskResource,
               %{
                 id: task_id,
                 organization_id: actor_scope.organization.id,
                 workspace_id: actor_scope.workspace.id,
                 graph_item_id: graph_item.id,
                 source_signal_id: other_signal.id,
                 body_document_id: document.id,
                 title: "Reject cross-scope source",
                 lifecycle_state: "open"
               },
               actor: actor_scope.session,
               action: :create
             )

    assert Exception.message(error) =~ "source_signal_id"
  end

  test "public WorkGraph create_task returns an error for a cross-scope source signal" do
    {:ok, source_scope} = bootstrap_scope("public-linked-source")
    {:ok, target_scope} = bootstrap_scope("public-linked-target")

    source_signal = create_signal!(source_scope, "Foreign source signal")
    {:ok, operation} = Operations.start_operation(target_scope.session, :proposed_change_apply)

    assert {:error, error} =
             WorkGraph.create_task(target_scope.session, operation, source_signal, %{
               title: "Reject public cross-scope source",
               body: "This task should not link to a signal from another scope."
             })

    assert Exception.message(error) =~ "source_signal_id"
  end

  defp bootstrap_scope(slug) do
    Foundation.bootstrap_local_owner(
      organization_name: "Office Graph #{slug}",
      organization_slug: "office-graph-#{slug}",
      workspace_name: "Workspace #{slug}",
      workspace_slug: "workspace-#{slug}",
      initiative_name: "Initiative #{slug}",
      initiative_slug: "initiative-#{slug}",
      owner_email: "owner-#{slug}@office-graph.local",
      owner_name: "Owner #{slug}"
    )
  end

  defp create_signal!(bootstrap, title) do
    {:ok, operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)

    {:ok, %{signal: signal}} =
      WorkGraph.create_signal(bootstrap.session, operation, %{
        title: title,
        body: "#{title} body"
      })

    signal
  end

  defp insert_graph_item!(bootstrap, resource_type, resource_id, title) do
    %GraphItem{id: Ecto.UUID.generate()}
    |> GraphItem.changeset(%{
      organization_id: bootstrap.organization.id,
      workspace_id: bootstrap.workspace.id,
      resource_type: resource_type,
      resource_id: resource_id,
      title: title
    })
    |> Repo.insert!()
  end

  defp insert_document!(bootstrap, plain_text) do
    %Document{id: Ecto.UUID.generate()}
    |> Document.changeset(%{
      organization_id: bootstrap.organization.id,
      workspace_id: bootstrap.workspace.id,
      plain_text: plain_text
    })
    |> Repo.insert!()
  end
end
