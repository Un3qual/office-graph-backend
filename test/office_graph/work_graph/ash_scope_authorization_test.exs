defmodule OfficeGraph.WorkGraph.AshScopeAuthorizationTest do
  use OfficeGraph.TestSupport.AshAuthorizationSupport

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
                 title: "Reject cross-scope source"
               },
               actor: actor_scope.session,
               action: :create
             )

    assert Exception.message(error) =~ "source_signal_id"
  end

  test "direct Ash creates reject graph item type and id mismatches" do
    {:ok, bootstrap} = bootstrap_scope("direct-graph-item-mismatch")

    signal_id = Ecto.UUID.generate()

    wrong_type_graph_item =
      insert_graph_item!(bootstrap, "task", signal_id, "Wrong type graph item")

    signal_document = insert_document!(bootstrap, "Direct mismatch signal body")

    assert {:error, signal_error} =
             Ash.create(
               SignalResource,
               %{
                 id: signal_id,
                 organization_id: bootstrap.organization.id,
                 workspace_id: bootstrap.workspace.id,
                 graph_item_id: wrong_type_graph_item.id,
                 body_document_id: signal_document.id,
                 title: "Reject wrong graph item type"
               },
               actor: bootstrap.session,
               action: :create
             )

    assert Exception.message(signal_error) =~ "graph_item_id"

    source_signal = create_signal!(bootstrap, "Mismatch source signal")
    task_id = Ecto.UUID.generate()

    wrong_id_graph_item =
      insert_graph_item!(bootstrap, "task", Ecto.UUID.generate(), "Wrong id graph item")

    task_document = insert_document!(bootstrap, "Direct mismatch task body")

    assert {:error, task_error} =
             Ash.create(
               TaskResource,
               %{
                 id: task_id,
                 organization_id: bootstrap.organization.id,
                 workspace_id: bootstrap.workspace.id,
                 graph_item_id: wrong_id_graph_item.id,
                 source_signal_id: source_signal.id,
                 body_document_id: task_document.id,
                 title: "Reject wrong graph item resource id"
               },
               actor: bootstrap.session,
               action: :create
             )

    assert Exception.message(task_error) =~ "graph_item_id"
  end

  test "direct Ash creates reject invalid Ash document references" do
    {:ok, actor_scope} = bootstrap_scope("ash-document-actor")
    {:ok, other_scope} = bootstrap_scope("ash-document-other")

    foreign_document = insert_document!(other_scope, "Foreign document")

    for {document_id, title} <- [
          {foreign_document.id, "Reject cross-scope document"},
          {Ecto.UUID.generate(), "Reject missing document"}
        ] do
      signal_id = Ecto.UUID.generate()
      graph_item = insert_graph_item!(actor_scope, "signal", signal_id, "#{title} graph item")

      assert {:error, error} =
               Ash.create(
                 SignalResource,
                 %{
                   id: signal_id,
                   organization_id: actor_scope.organization.id,
                   workspace_id: actor_scope.workspace.id,
                   graph_item_id: graph_item.id,
                   body_document_id: document_id,
                   title: title
                 },
                 actor: actor_scope.session,
                 action: :create
               )

      assert Exception.message(error) =~ "body_document_id"
    end
  end

  test "direct Ash creates reject invalid Ash description document references" do
    {:ok, actor_scope} = bootstrap_scope("ash-description-actor")
    {:ok, other_scope} = bootstrap_scope("ash-description-other")

    review_finding = create_review_finding!(actor_scope)
    foreign_document = insert_document!(other_scope, "Foreign check description")

    for {document_id, title} <- [
          {foreign_document.id, "Reject cross-scope check description"},
          {Ecto.UUID.generate(), "Reject missing check description"}
        ] do
      verification_check_id = Ecto.UUID.generate()

      graph_item =
        insert_graph_item!(
          actor_scope,
          "verification_check",
          verification_check_id,
          "#{title} graph item"
        )

      assert {:error, error} =
               Ash.create(
                 VerificationCheckResource,
                 %{
                   id: verification_check_id,
                   organization_id: actor_scope.organization.id,
                   workspace_id: actor_scope.workspace.id,
                   graph_item_id: graph_item.id,
                   review_finding_id: review_finding.id,
                   description_document_id: document_id,
                   title: title
                 },
                 actor: actor_scope.session,
                 action: :create
               )

      assert Exception.message(error) =~ "description_document_id"
    end
  end

  test "direct Ash creates reject invalid Ecto operation references" do
    {:ok, actor_scope} = bootstrap_scope("ecto-operation-actor")
    {:ok, other_scope} = bootstrap_scope("ecto-operation-other")

    completed = complete_verification!(actor_scope)

    {:ok, foreign_operation} =
      Operations.start_operation(other_scope.session, :verification_complete)

    for {operation_id, result} <- [
          {foreign_operation.id, "cross_scope_operation"},
          {Ecto.UUID.generate(), "missing_operation"}
        ] do
      assert {:error, error} =
               Ash.create(
                 VerificationResultResource,
                 %{
                   id: Ecto.UUID.generate(),
                   organization_id: actor_scope.organization.id,
                   workspace_id: actor_scope.workspace.id,
                   verification_check_id: completed.verification_check.id,
                   evidence_item_id: completed.evidence_item.id,
                   operation_id: operation_id,
                   result: result
                 },
                 authorize?: false,
                 action: :create
               )

      assert Exception.message(error) =~ "operation_id"
    end
  end

  test "same-scope validation sanitizes Ash read errors" do
    organization_id = Ecto.UUID.generate()
    workspace_id = Ecto.UUID.generate()

    changeset = %Ash.Changeset{
      attributes: %{
        organization_id: organization_id,
        workspace_id: workspace_id,
        body_document_id: "not-a-uuid"
      }
    }

    error =
      changeset
      |> ValidateSameScopeReferences.change(
        [references: [body_document_id: Document]],
        %{}
      )
      |> Map.fetch!(:errors)
      |> Ash.Error.to_error_class()

    message = Exception.message(error)

    assert message =~ "body_document_id could not be validated"
    refute message =~ "not-a-uuid"
    refute message =~ "must reference an existing record in the target scope"
  end

  test "same-scope validation attaches missing target scope to both fields" do
    changeset = %Ash.Changeset{
      arguments: %{},
      attributes: %{
        organization_id: Ecto.UUID.generate(),
        body_document_id: Ecto.UUID.generate()
      }
    }

    errors =
      changeset
      |> ValidateSameScopeReferences.change(
        [references: [body_document_id: Document]],
        %{}
      )
      |> Map.fetch!(:errors)

    assert Enum.any?(errors, &(&1.field == :organization_id))
    assert Enum.any?(errors, &(&1.field == :workspace_id))
  end

  test "same-scope validation batches reference reads for bulk creates" do
    {:ok, bootstrap} = bootstrap_scope("bulk-reference-validation")

    inputs =
      Enum.map(1..4, fn index ->
        signal_id = Ecto.UUID.generate()

        graph_item =
          insert_graph_item!(
            bootstrap,
            "signal",
            signal_id,
            "Bulk signal graph item #{index}"
          )

        document = insert_document!(bootstrap, "Bulk signal body #{index}")

        %{
          id: signal_id,
          organization_id: bootstrap.organization.id,
          workspace_id: bootstrap.workspace.id,
          graph_item_id: graph_item.id,
          body_document_id: document.id,
          title: "Bulk signal #{index}"
        }
      end)

    {%Ash.BulkResult{status: :success, records: records}, queries} =
      QueryCounter.count(fn ->
        Ash.bulk_create(inputs, SignalResource, :create,
          actor: bootstrap.session,
          authorize?: true,
          return_errors?: true,
          return_records?: true,
          sorted?: true,
          stop_on_error?: true
        )
      end)

    assert length(records) == 4

    # Accepted budget: one lookup per referenced resource in an Ash batch.
    assert QueryCounter.source_count(queries, "graph_items") <= 1
    assert QueryCounter.source_count(queries, "document") <= 1
  end

  test "same-scope validation preserves bulk reference errors" do
    {:ok, actor_scope} = bootstrap_scope("bulk-reference-errors-actor")
    {:ok, other_scope} = bootstrap_scope("bulk-reference-errors-other")

    missing_id = Ecto.UUID.generate()
    cross_scope_id = Ecto.UUID.generate()
    wrong_identity_id = Ecto.UUID.generate()

    foreign_graph_item =
      insert_graph_item!(
        other_scope,
        "signal",
        cross_scope_id,
        "Foreign bulk signal graph item"
      )

    wrong_identity_graph_item =
      insert_graph_item!(
        actor_scope,
        "task",
        wrong_identity_id,
        "Wrong bulk signal graph identity"
      )

    inputs = [
      bulk_signal_input(actor_scope, missing_id, Ecto.UUID.generate(), "Missing bulk reference"),
      bulk_signal_input(
        actor_scope,
        cross_scope_id,
        foreign_graph_item.id,
        "Cross-scope bulk reference"
      ),
      bulk_signal_input(
        actor_scope,
        wrong_identity_id,
        wrong_identity_graph_item.id,
        "Wrong bulk graph identity"
      )
    ]

    assert %Ash.BulkResult{status: :error, error_count: 3, errors: errors} =
             Ash.bulk_create(inputs, SignalResource, :create,
               actor: actor_scope.session,
               authorize?: true,
               return_errors?: true,
               return_records?: true,
               sorted?: true
             )

    messages = Enum.map(errors, &Exception.message/1)

    assert Enum.count(
             messages,
             &String.contains?(
               &1,
               "graph_item_id must reference an existing record in the target scope"
             )
           ) == 2

    assert Enum.count(
             messages,
             &String.contains?(
               &1,
               "graph_item_id must reference a graph item for the target resource"
             )
           ) == 1
  end

  test "same-scope validation isolates malformed IDs within bulk creates" do
    {:ok, bootstrap} = bootstrap_scope("bulk-reference-malformed-id")

    valid_signal_id = Ecto.UUID.generate()

    valid_graph_item =
      insert_graph_item!(
        bootstrap,
        "signal",
        valid_signal_id,
        "Valid bulk signal graph item"
      )

    valid_input =
      bulk_signal_input(
        bootstrap,
        valid_signal_id,
        valid_graph_item.id,
        "Valid bulk signal"
      )

    malformed_input =
      bulk_signal_input(
        bootstrap,
        Ecto.UUID.generate(),
        "not-a-uuid",
        "Malformed bulk signal"
      )

    assert %Ash.BulkResult{
             status: :partial_success,
             error_count: 1,
             records: [%SignalResource{id: ^valid_signal_id}],
             errors: [error]
           } =
             Ash.bulk_create([valid_input, malformed_input], SignalResource, :create,
               actor: bootstrap.session,
               authorize?: true,
               return_errors?: true,
               return_records?: true,
               sorted?: true,
               stop_on_error?: false
             )

    message = Exception.message(error)
    assert message =~ "Invalid value provided for graph_item_id"
    assert message =~ "not-a-uuid"
  end

  test "repo Ash bulk create returns ordered records and skips empty inserts" do
    {empty_records, empty_queries} =
      QueryCounter.count(fn -> Repo.ash_bulk_create!(SignalResource, []) end)

    assert empty_records == []
    assert empty_queries == []

    {:ok, bootstrap} = bootstrap_scope("repo-bulk-create-order")

    inputs =
      Enum.map(1..3, fn index ->
        signal_id = Ecto.UUID.generate()

        graph_item =
          insert_graph_item!(
            bootstrap,
            "signal",
            signal_id,
            "Ordered bulk graph item #{index}"
          )

        bulk_signal_input(
          bootstrap,
          signal_id,
          graph_item.id,
          "Ordered bulk signal #{index}"
        )
      end)

    assert {:ok, records} =
             Repo.transaction(fn -> Repo.ash_bulk_create!(SignalResource, inputs) end)

    assert Enum.map(records, & &1.id) == Enum.map(inputs, & &1.id)
  end

  test "repo Ash bulk create rolls back an invalid middle record" do
    {:ok, bootstrap} = bootstrap_scope("repo-bulk-create-rollback")

    valid_inputs =
      Enum.map(1..2, fn index ->
        signal_id = Ecto.UUID.generate()

        graph_item =
          insert_graph_item!(
            bootstrap,
            "signal",
            signal_id,
            "Rollback bulk graph item #{index}"
          )

        bulk_signal_input(
          bootstrap,
          signal_id,
          graph_item.id,
          "Rollback bulk signal #{index}"
        )
      end)

    invalid_input =
      bulk_signal_input(
        bootstrap,
        Ecto.UUID.generate(),
        Ecto.UUID.generate(),
        "Invalid middle bulk signal"
      )

    inputs = [List.first(valid_inputs), invalid_input, List.last(valid_inputs)]

    assert {:error, %Ash.Error.Invalid{}} =
             Repo.transaction(fn -> Repo.ash_bulk_create!(SignalResource, inputs) end)

    input_ids = Enum.map(inputs, & &1.id)

    assert [] ==
             SignalResource
             |> Ash.Query.filter(id in ^input_ids)
             |> Ash.read!(authorize?: false)
  end

  test "graph relationships expose no public Ash actions" do
    public_action_names =
      GraphRelationship
      |> Ash.Resource.Info.public_actions()
      |> Enum.map(& &1.name)

    refute :create in public_action_names
    refute :read in public_action_names
  end

  test "graph item create is internal to typed WorkGraph flows" do
    {:ok, bootstrap} = bootstrap_scope("graph-item-internal-create")

    assert {:error, error} =
             Ash.create(
               GraphItem,
               %{
                 id: Ecto.UUID.generate(),
                 organization_id: bootstrap.organization.id,
                 workspace_id: bootstrap.workspace.id,
                 resource_type: "task",
                 resource_id: Ecto.UUID.generate(),
                 title: "Dangling graph item"
               },
               actor: bootstrap.session,
               action: :create
             )

    assert Exception.message(error) =~ ~r/forbidden/i
  end

  test "direct graph relationship creates reject cross-scope endpoints" do
    {:ok, actor_scope} = bootstrap_scope("relationship-actor")
    {:ok, other_scope} = bootstrap_scope("relationship-other")

    source = insert_graph_item!(actor_scope, "task", Ecto.UUID.generate(), "Source")
    target = insert_graph_item!(other_scope, "task", Ecto.UUID.generate(), "Target")
    {:ok, definition} = OfficeGraph.WorkGraph.RelationshipDefinitions.fetch_by_key("depends_on")
    {:ok, operation} = Operations.start_operation(actor_scope.session, :graph_relationship_create)

    assert {:error, error} =
             Ash.create(
               GraphRelationship,
               %{
                 id: Ecto.UUID.generate(),
                 definition_id: definition.id,
                 organization_id: actor_scope.organization.id,
                 workspace_id: actor_scope.workspace.id,
                 source_item_id: source.id,
                 target_item_id: target.id,
                 asserting_principal_id: actor_scope.principal.id,
                 operation_id: operation.id,
                 valid_from: DateTime.utc_now()
               },
               action: :create,
               authorize?: false
             )

    message = Exception.message(error)
    assert message =~ "source_item_id"
    assert message =~ "target_item_id"
  end
end
