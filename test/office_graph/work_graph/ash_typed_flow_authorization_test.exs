defmodule OfficeGraph.WorkGraph.AshTypedFlowAuthorizationTest do
  use OfficeGraph.TestSupport.AshAuthorizationSupport

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

  test "direct typed creates reject caller supplied lifecycle states" do
    {:ok, bootstrap} = bootstrap_scope("direct-create-lifecycle")
    source_signal = create_signal!(bootstrap, "Lifecycle source signal")
    task = create_task!(bootstrap, source_signal)
    review_finding = create_review_finding!(bootstrap, task)
    verification_check = create_verification_check!(bootstrap, review_finding)
    artifact = insert_artifact!(bootstrap, "Lifecycle evidence artifact")

    signal_id = Ecto.UUID.generate()

    signal_graph_item =
      insert_graph_item!(bootstrap, "signal", signal_id, "Spoofed signal graph item")

    signal_document = insert_document!(bootstrap, "Spoofed signal body")

    assert {:error, signal_error} =
             Ash.create(
               SignalResource,
               %{
                 id: signal_id,
                 organization_id: bootstrap.organization.id,
                 workspace_id: bootstrap.workspace.id,
                 graph_item_id: signal_graph_item.id,
                 body_document_id: signal_document.id,
                 title: "Spoofed signal",
                 state: "closed"
               },
               actor: bootstrap.session,
               action: :create
             )

    assert Exception.message(signal_error) =~ "No such input `state`"

    defaulted_signal_id = Ecto.UUID.generate()

    defaulted_signal_graph_item =
      insert_graph_item!(bootstrap, "signal", defaulted_signal_id, "Defaulted signal graph item")

    defaulted_signal_document = insert_document!(bootstrap, "Defaulted signal body")

    assert {:ok, defaulted_signal} =
             Ash.create(
               SignalResource,
               %{
                 id: defaulted_signal_id,
                 organization_id: bootstrap.organization.id,
                 workspace_id: bootstrap.workspace.id,
                 graph_item_id: defaulted_signal_graph_item.id,
                 body_document_id: defaulted_signal_document.id,
                 title: "Defaulted signal"
               },
               actor: bootstrap.session,
               action: :create
             )

    assert defaulted_signal.state == "open"

    task_id = Ecto.UUID.generate()
    task_graph_item = insert_graph_item!(bootstrap, "task", task_id, "Spoofed task graph item")
    task_document = insert_document!(bootstrap, "Spoofed task body")

    assert {:error, task_error} =
             Ash.create(
               TaskResource,
               %{
                 id: task_id,
                 organization_id: bootstrap.organization.id,
                 workspace_id: bootstrap.workspace.id,
                 graph_item_id: task_graph_item.id,
                 source_signal_id: source_signal.id,
                 body_document_id: task_document.id,
                 title: "Spoofed task",
                 lifecycle_state: "verified_complete"
               },
               actor: bootstrap.session,
               action: :create
             )

    assert Exception.message(task_error) =~ "No such input `lifecycle_state`"

    finding_id = Ecto.UUID.generate()

    finding_graph_item =
      insert_graph_item!(bootstrap, "review_finding", finding_id, "Spoofed finding graph item")

    finding_document = insert_document!(bootstrap, "Spoofed finding body")

    assert {:error, finding_error} =
             Ash.create(
               ReviewFindingResource,
               %{
                 id: finding_id,
                 organization_id: bootstrap.organization.id,
                 workspace_id: bootstrap.workspace.id,
                 graph_item_id: finding_graph_item.id,
                 task_id: task.id,
                 body_document_id: finding_document.id,
                 title: "Spoofed finding",
                 lifecycle_state: "verified_complete"
               },
               actor: bootstrap.session,
               action: :create
             )

    assert Exception.message(finding_error) =~ "No such input `lifecycle_state`"

    check_id = Ecto.UUID.generate()

    check_graph_item =
      insert_graph_item!(bootstrap, "verification_check", check_id, "Spoofed check graph item")

    check_document = insert_document!(bootstrap, "Spoofed check body")

    assert {:error, check_error} =
             Ash.create(
               VerificationCheckResource,
               %{
                 id: check_id,
                 organization_id: bootstrap.organization.id,
                 workspace_id: bootstrap.workspace.id,
                 graph_item_id: check_graph_item.id,
                 review_finding_id: review_finding.id,
                 description_document_id: check_document.id,
                 title: "Spoofed check",
                 lifecycle_state: "satisfied"
               },
               actor: bootstrap.session,
               action: :create
             )

    assert Exception.message(check_error) =~ "No such input `lifecycle_state`"

    evidence_id = Ecto.UUID.generate()

    evidence_graph_item =
      insert_graph_item!(bootstrap, "evidence_item", evidence_id, "Spoofed evidence graph item")

    evidence_document = insert_document!(bootstrap, "Spoofed evidence body")

    assert {:error, evidence_error} =
             Ash.create(
               EvidenceItem,
               %{
                 id: evidence_id,
                 organization_id: bootstrap.organization.id,
                 workspace_id: bootstrap.workspace.id,
                 graph_item_id: evidence_graph_item.id,
                 verification_check_id: verification_check.id,
                 artifact_id: artifact.id,
                 body_document_id: evidence_document.id,
                 title: "Spoofed evidence",
                 state: "accepted"
               },
               actor: bootstrap.session,
               action: :create
             )

    assert Exception.message(evidence_error) =~ "No such input `state`"
  end

  test "public WorkGraph create_signal returns an error for graph item validation failure" do
    {:ok, bootstrap} = bootstrap_scope("public-signal-validation")
    {:ok, operation} = Operations.start_operation(bootstrap.session, :proposed_change_apply)
    body = "A missing title should be returned as a validation error."

    refute document_with_plain_text?(body)

    assert {:error, error} =
             WorkGraph.create_signal(bootstrap.session, operation, %{
               title: nil,
               body: body
             })

    assert Exception.message(error) =~ "title"
    refute document_with_plain_text?(body)
  end

  test "public WorkGraph create_signal rejects operations from another session in the same workspace" do
    {:ok, actor_scope} = bootstrap_scope("public-signal-operation-actor")

    {:ok, other_principal_same_scope} =
      Foundation.bootstrap_local_owner(
        organization_name: "Office Graph public-signal-operation-actor",
        organization_slug: "office-graph-public-signal-operation-actor",
        workspace_name: "Workspace public-signal-operation-actor",
        workspace_slug: "workspace-public-signal-operation-actor",
        initiative_name: "Initiative public-signal-operation-actor",
        initiative_slug: "initiative-public-signal-operation-actor",
        owner_email: "other-public-signal-operation-actor@office-graph.local",
        owner_name: "Other Owner public-signal-operation-actor"
      )

    {:ok, foreign_operation} =
      Operations.start_operation(other_principal_same_scope.session, :proposed_change_apply)

    body = "A reused operation from another session must not create graph truth."

    refute document_with_plain_text?(body)

    assert {:error, :forbidden} =
             WorkGraph.create_signal(actor_scope.session, foreign_operation, %{
               title: "Reject reused operation",
               body: body
             })

    refute document_with_plain_text?(body)
  end

  test "public WorkGraph create_signal rejects manual intake operations" do
    {:ok, bootstrap} = bootstrap_scope("public-signal-manual-intake-operation")
    {:ok, manual_operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)
    manual_operation_id = manual_operation.id
    body = "Manual intake must create proposals, not graph truth."

    refute document_with_plain_text?(body)

    assert {:error, {:invalid_operation_action, ^manual_operation_id, "proposed_change.apply"}} =
             WorkGraph.create_signal(bootstrap.session, manual_operation, %{
               title: "Reject manual signal",
               body: body
             })

    refute document_with_plain_text?(body)
  end

  test "public WorkGraph linked creates require proposed-change apply operations" do
    {:ok, bootstrap} = bootstrap_scope("linked-create-operation-action")
    signal = create_signal!(bootstrap, "Operation action source")
    {:ok, manual_operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)
    manual_operation_id = manual_operation.id

    assert {:error, {:invalid_operation_action, ^manual_operation_id, "proposed_change.apply"}} =
             WorkGraph.create_task(bootstrap.session, manual_operation, signal, %{
               title: "Reject non-apply task",
               body: "Task graph writes must be tied to an apply operation."
             })

    {:ok, apply_operation} = Operations.start_operation(bootstrap.session, :proposed_change_apply)

    {:ok, %{task: task}} =
      WorkGraph.create_task(bootstrap.session, apply_operation, signal, %{
        title: "Apply task",
        body: "Task body"
      })

    assert {:error, {:invalid_operation_action, ^manual_operation_id, "proposed_change.apply"}} =
             WorkGraph.create_review_finding(bootstrap.session, manual_operation, task, %{
               title: "Reject non-apply finding",
               body: "Finding graph writes must be tied to an apply operation."
             })

    {:ok, %{review_finding: review_finding}} =
      WorkGraph.create_review_finding(bootstrap.session, apply_operation, task, %{
        title: "Apply finding",
        body: "Finding body"
      })

    assert {:error, {:invalid_operation_action, ^manual_operation_id, "proposed_change.apply"}} =
             WorkGraph.create_verification_check(
               bootstrap.session,
               manual_operation,
               review_finding,
               %{
                 title: "Reject non-apply check",
                 body: "Check graph writes must be tied to an apply operation."
               }
             )
  end

  test "public WorkGraph linked creates build edges from persisted parents" do
    {:ok, bootstrap} = bootstrap_scope("persisted-parent-edges")
    signal = create_signal!(bootstrap, "Persisted parent signal")
    other_signal = create_signal!(bootstrap, "Other parent signal")
    tampered_signal = %{signal | graph_item_id: other_signal.graph_item_id}

    {:ok, operation} = Operations.start_operation(bootstrap.session, :proposed_change_apply)

    assert {:ok, %{task: task, relationship: task_relationship}} =
             WorkGraph.create_task(bootstrap.session, operation, tampered_signal, %{
               title: "Persisted parent task",
               body: "Task should point at the persisted signal graph item."
             })

    assert task_relationship.source_item_id == signal.graph_item_id
    refute task_relationship.source_item_id == other_signal.graph_item_id

    other_task = create_task!(bootstrap, other_signal, "Other parent task")
    tampered_task = %{task | graph_item_id: other_task.graph_item_id}

    assert {:ok, %{review_finding: review_finding, relationship: finding_relationship}} =
             WorkGraph.create_review_finding(bootstrap.session, operation, tampered_task, %{
               title: "Persisted parent finding",
               body: "Finding should point at the persisted task graph item."
             })

    assert finding_relationship.source_item_id == task.graph_item_id
    refute finding_relationship.source_item_id == other_task.graph_item_id

    other_finding = create_review_finding!(bootstrap, other_task)
    tampered_finding = %{review_finding | graph_item_id: other_finding.graph_item_id}

    assert {:ok, %{relationship: check_relationship}} =
             WorkGraph.create_verification_check(
               bootstrap.session,
               operation,
               tampered_finding,
               %{
                 title: "Persisted parent check",
                 body: "Check should point at the persisted finding graph item."
               }
             )

    assert check_relationship.source_item_id == review_finding.graph_item_id
    refute check_relationship.source_item_id == other_finding.graph_item_id
  end

  test "public WorkGraph create_verification_check rejects completed review findings" do
    {:ok, bootstrap} = bootstrap_scope("completed-finding-check")
    completed = complete_verification!(bootstrap)
    {:ok, operation} = Operations.start_operation(bootstrap.session, :proposed_change_apply)

    assert {:error, error} =
             WorkGraph.create_verification_check(
               bootstrap.session,
               operation,
               completed.review_finding,
               %{
                 title: "Late verification check",
                 body: "Completed findings must not receive new required checks."
               }
             )

    assert %Ash.Changeset{errors: errors} = error
    assert invalid_attribute_error?(errors, :review_finding_id, "open review finding")

    check_count =
      VerificationCheckResource
      |> Ash.Query.filter(review_finding_id == ^completed.review_finding.id)
      |> Ash.count!(authorize?: false)

    assert check_count == 1
  end

  test "public WorkGraph create_review_finding rejects completed tasks" do
    {:ok, bootstrap} = bootstrap_scope("completed-task-finding")
    completed = complete_verification!(bootstrap)
    {:ok, operation} = Operations.start_operation(bootstrap.session, :proposed_change_apply)

    assert {:error, error} =
             WorkGraph.create_review_finding(bootstrap.session, operation, completed.task, %{
               title: "Late review finding",
               body: "Completed tasks must not receive new review findings."
             })

    assert %Ash.Changeset{errors: errors} = error
    assert invalid_attribute_error?(errors, :task_id, "open task")

    finding_count =
      ReviewFindingResource
      |> Ash.Query.filter(task_id == ^completed.task.id)
      |> Ash.count!(authorize?: false)

    assert finding_count == 1
  end

  test "direct Ash verification check create rejects completed review findings" do
    {:ok, bootstrap} = bootstrap_scope("direct-completed-finding-check")
    completed = complete_verification!(bootstrap)
    check_id = Ecto.UUID.generate()

    graph_item =
      insert_graph_item!(
        bootstrap,
        "verification_check",
        check_id,
        "Late verification check graph item"
      )

    document = insert_document!(bootstrap, "Late verification check description")

    assert {:error, error} =
             Ash.create(
               VerificationCheckResource,
               %{
                 id: check_id,
                 organization_id: bootstrap.organization.id,
                 workspace_id: bootstrap.workspace.id,
                 graph_item_id: graph_item.id,
                 review_finding_id: completed.review_finding.id,
                 description_document_id: document.id,
                 title: "Late verification check"
               },
               actor: bootstrap.session,
               action: :create
             )

    assert Exception.message(error) =~ "review_finding_id"
    assert Exception.message(error) =~ "open review finding"
  end

  test "direct Ash review finding create rejects completed tasks" do
    {:ok, bootstrap} = bootstrap_scope("direct-completed-task-finding")
    completed = complete_verification!(bootstrap)
    finding_id = Ecto.UUID.generate()

    graph_item =
      insert_graph_item!(
        bootstrap,
        "review_finding",
        finding_id,
        "Late review finding graph item"
      )

    document = insert_document!(bootstrap, "Late review finding body")

    assert {:error, error} =
             Ash.create(
               ReviewFindingResource,
               %{
                 id: finding_id,
                 organization_id: bootstrap.organization.id,
                 workspace_id: bootstrap.workspace.id,
                 graph_item_id: graph_item.id,
                 task_id: completed.task.id,
                 body_document_id: document.id,
                 title: "Late review finding"
               },
               actor: bootstrap.session,
               action: :create
             )

    assert Exception.message(error) =~ "task_id"
    assert Exception.message(error) =~ "open task"
  end
end
