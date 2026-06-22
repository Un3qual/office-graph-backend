defmodule OfficeGraph.WorkGraph.AshAuthorizationTest do
  use OfficeGraph.DataCase, async: false

  require Ash.Query

  alias OfficeGraph.Content.Document
  alias OfficeGraph.Foundation
  alias OfficeGraph.Operations
  alias OfficeGraph.Verification
  alias OfficeGraph.WorkGraph
  alias OfficeGraph.WorkGraph.Changes.ValidateSameScopeReferences
  alias OfficeGraph.WorkGraph.EvidenceItem
  alias OfficeGraph.WorkGraph.GraphItem
  alias OfficeGraph.WorkGraph.GraphRelationship
  alias OfficeGraph.WorkGraph.ReviewFinding, as: ReviewFindingResource
  alias OfficeGraph.WorkGraph.Signal, as: SignalResource
  alias OfficeGraph.WorkGraph.Task, as: TaskResource
  alias OfficeGraph.WorkGraph.VerificationCheck, as: VerificationCheckResource
  alias OfficeGraph.WorkGraph.VerificationResult, as: VerificationResultResource

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
                 title: "Reject wrong graph item type",
                 state: "open"
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
                 title: "Reject wrong graph item resource id",
                 lifecycle_state: "open"
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
                   title: title,
                   state: "open"
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
                   title: title,
                   lifecycle_state: "required"
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
                 actor: actor_scope.session,
                 action: :create
               )

      assert Exception.message(error) =~ "operation_id"
    end
  end

  test "same-scope validation preserves Ash read errors separately from missing references" do
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

    assert message =~ "body_document_id lookup failed"
    assert message =~ "not-a-uuid"
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

  test "graph relationships expose no public Ash actions" do
    public_action_names =
      GraphRelationship
      |> Ash.Resource.Info.public_actions()
      |> Enum.map(& &1.name)

    refute :create in public_action_names
    refute :read in public_action_names
  end

  test "direct graph relationship creates reject cross-scope endpoints" do
    {:ok, actor_scope} = bootstrap_scope("relationship-actor")
    {:ok, other_scope} = bootstrap_scope("relationship-other")

    source = insert_graph_item!(actor_scope, "signal", Ecto.UUID.generate(), "Source")
    target = insert_graph_item!(other_scope, "task", Ecto.UUID.generate(), "Target")

    assert {:error, error} =
             Ash.create(
               GraphRelationship,
               %{
                 id: Ecto.UUID.generate(),
                 source_item_id: source.id,
                 target_item_id: target.id,
                 relationship_type: "cross_scope"
               },
               action: :create,
               authorize?: false
             )

    message = Exception.message(error)
    assert message =~ "source_item_id"
    assert message =~ "target_item_id"
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

  test "public WorkGraph create_signal returns an error for graph item validation failure" do
    {:ok, bootstrap} = bootstrap_scope("public-signal-validation")
    {:ok, operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)
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
      Operations.start_operation(other_principal_same_scope.session, :manual_intake_submit)

    body = "A reused operation from another session must not create graph truth."

    refute document_with_plain_text?(body)

    assert {:error, :forbidden} =
             WorkGraph.create_signal(actor_scope.session, foreign_operation, %{
               title: "Reject reused operation",
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

  test "public WorkGraph complete_verification returns an error for a stale verification check" do
    {:ok, bootstrap} = bootstrap_scope("public-stale-verification")
    verification_check = create_verification_check!(bootstrap)
    stale_verification_check = %{verification_check | id: Ecto.UUID.generate()}
    {:ok, operation} = Operations.start_operation(bootstrap.session, :verification_complete)
    body = "The verification check id no longer exists."

    refute document_with_plain_text?(body)

    assert {:error, error} =
             WorkGraph.complete_verification(
               bootstrap.session,
               operation,
               stale_verification_check,
               %{
                 title: "Stale verification evidence",
                 body: body,
                 artifact_uri: "https://example.test/stale-verification"
               }
             )

    assert error == {:not_found, VerificationCheckResource, stale_verification_check.id}
    refute document_with_plain_text?(body)
  end

  test "verification completion requires a verification-complete operation" do
    {:ok, bootstrap} = bootstrap_scope("completion-operation-action")
    verification_check = create_verification_check!(bootstrap)
    {:ok, operation} = Operations.start_operation(bootstrap.session, :evidence_link)
    operation_id = operation.id
    body = "Completion must reject evidence-link operation context."

    assert {:error, {:invalid_operation_action, ^operation_id, "verification.complete"}} =
             Verification.complete_with_evidence(
               bootstrap.session,
               operation,
               verification_check,
               %{
                 title: "Reject evidence-link operation",
                 body: body,
                 artifact_uri: "https://example.test/reject-evidence-link-operation"
               }
             )

    refute document_with_plain_text?(body)
  end

  test "verification completion reloads the check before deriving parent state" do
    {:ok, bootstrap} = bootstrap_scope("completion-parent-reload")
    chain = create_verification_chain!(bootstrap)
    other_chain = create_verification_chain!(bootstrap)

    tampered_check = %{
      chain.verification_check
      | review_finding_id: other_chain.review_finding.id
    }

    {:ok, operation} = Operations.start_operation(bootstrap.session, :verification_complete)

    assert {:ok, completed} =
             Verification.complete_with_evidence(bootstrap.session, operation, tampered_check, %{
               title: "Parent reload evidence",
               body: "Completion must use the persisted check parent.",
               artifact_uri: "https://example.test/parent-reload"
             })

    assert completed.review_finding.id == chain.review_finding.id
    assert completed.task.id == chain.task.id

    assert "open" ==
             ReviewFindingResource
             |> Ash.get!(other_chain.review_finding.id, authorize?: false)
             |> Map.fetch!(:lifecycle_state)

    assert "open" ==
             TaskResource
             |> Ash.get!(other_chain.task.id, authorize?: false)
             |> Map.fetch!(:lifecycle_state)
  end

  test "verification completion keeps parents open until all checks pass" do
    {:ok, bootstrap} = bootstrap_scope("completion-all-checks")
    chain = create_verification_chain!(bootstrap)
    second_check = create_verification_check!(bootstrap, chain.review_finding)

    {:ok, first_operation} = Operations.start_operation(bootstrap.session, :verification_complete)

    assert {:ok, first_completion} =
             Verification.complete_with_evidence(
               bootstrap.session,
               first_operation,
               chain.verification_check,
               %{
                 title: "First check evidence",
                 body: "One required check remains open.",
                 artifact_uri: "https://example.test/first-check"
               }
             )

    assert first_completion.verification_check.lifecycle_state == "satisfied"
    assert first_completion.review_finding.lifecycle_state == "open"
    assert first_completion.task.lifecycle_state == "open"

    assert "open" ==
             ReviewFindingResource
             |> Ash.get!(chain.review_finding.id, authorize?: false)
             |> Map.fetch!(:lifecycle_state)

    {:ok, second_operation} =
      Operations.start_operation(bootstrap.session, :verification_complete)

    assert {:ok, second_completion} =
             Verification.complete_with_evidence(
               bootstrap.session,
               second_operation,
               second_check,
               %{
                 title: "Second check evidence",
                 body: "All required checks are now satisfied.",
                 artifact_uri: "https://example.test/second-check"
               }
             )

    assert second_completion.verification_check.lifecycle_state == "satisfied"
    assert second_completion.review_finding.lifecycle_state == "verified_complete"
    assert second_completion.task.lifecycle_state == "verified_complete"
  end

  test "verification completion links evidence and artifact graph items" do
    {:ok, bootstrap} = bootstrap_scope("completion-evidence-relationships")

    completed = complete_verification!(bootstrap)

    assert relationship_exists?(
             completed.verification_check.graph_item_id,
             completed.evidence_item.graph_item_id,
             "has_evidence"
           )

    assert relationship_exists?(
             completed.evidence_item.graph_item_id,
             completed.artifact.graph_item_id,
             "references_artifact"
           )
  end

  test "verification completion rejects repeated completion without duplicate evidence" do
    {:ok, bootstrap} = bootstrap_scope("repeat-completion")
    completed = complete_verification!(bootstrap)
    {:ok, operation} = Operations.start_operation(bootstrap.session, :verification_complete)

    assert {:error, {:invalid_verification_check_status, check_id}} =
             Verification.complete_with_evidence(
               bootstrap.session,
               operation,
               completed.verification_check,
               %{
                 title: "Repeated completion",
                 body: "This should not create duplicate evidence.",
                 artifact_uri: "https://example.test/repeated-completion"
               }
             )

    assert check_id == completed.verification_check.id

    evidence_count =
      EvidenceItem
      |> Ash.Query.filter(verification_check_id == ^completed.verification_check.id)
      |> Ash.count!(authorize?: false)

    result_count =
      VerificationResultResource
      |> Ash.Query.filter(verification_check_id == ^completed.verification_check.id)
      |> Ash.count!(authorize?: false)

    assert evidence_count == 1
    assert result_count == 1
  end

  test "state transition actions reject caller supplied attributes" do
    {:ok, bootstrap} = bootstrap_scope("state-transition-input")
    verification_check = create_verification_check!(bootstrap)

    assert {:error, error} =
             verification_check
             |> Ash.Changeset.for_update(:mark_satisfied, %{title: "Mutated title"},
               actor: bootstrap.session
             )
             |> Ash.update()

    assert Exception.message(error) =~ "No such input `title`"
  end

  test "verification completion does not require skeleton read capability for internal reloads" do
    {:ok, bootstrap} = bootstrap_scope("verification-without-read")
    verification_check = create_verification_check!(bootstrap)

    verification_actor = %{
      bootstrap.session
      | capabilities: MapSet.new(["evidence.link", "verification.complete"])
    }

    {:ok, operation} = Operations.start_operation(verification_actor, :verification_complete)

    assert {:ok, completed} =
             Verification.complete_with_evidence(
               verification_actor,
               operation,
               verification_check,
               %{
                 title: "Completion without read",
                 body: "Evidence linked by a writer without skeleton read.",
                 artifact_uri: "https://example.test/no-read"
               }
             )

    assert completed.evidence_item.state == "accepted"
    assert completed.verification_result.result == "passed"
    assert completed.verification_check.lifecycle_state == "satisfied"
    assert completed.review_finding.lifecycle_state == "verified_complete"
    assert completed.task.lifecycle_state == "verified_complete"
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

  defp create_verification_check!(bootstrap) do
    review_finding = create_review_finding!(bootstrap)
    create_verification_check!(bootstrap, review_finding)
  end

  defp create_verification_check!(bootstrap, review_finding) do
    {:ok, graph_operation} = Operations.start_operation(bootstrap.session, :proposed_change_apply)

    {:ok, %{verification_check: verification_check}} =
      WorkGraph.create_verification_check(bootstrap.session, graph_operation, review_finding, %{
        title: "Verification check",
        body: "Check body"
      })

    verification_check
  end

  defp create_review_finding!(bootstrap) do
    {:ok, signal_operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)

    {:ok, %{signal: signal}} =
      WorkGraph.create_signal(bootstrap.session, signal_operation, %{
        title: "Verification source",
        body: "Source body"
      })

    task = create_task!(bootstrap, signal)
    create_review_finding!(bootstrap, task)
  end

  defp create_task!(bootstrap, signal, title \\ "Verification task") do
    {:ok, graph_operation} = Operations.start_operation(bootstrap.session, :proposed_change_apply)

    {:ok, %{task: task}} =
      WorkGraph.create_task(bootstrap.session, graph_operation, signal, %{
        title: title,
        body: "Task body"
      })

    task
  end

  defp create_review_finding!(bootstrap, task) do
    {:ok, graph_operation} = Operations.start_operation(bootstrap.session, :proposed_change_apply)

    {:ok, %{review_finding: review_finding}} =
      WorkGraph.create_review_finding(bootstrap.session, graph_operation, task, %{
        title: "Verification finding",
        body: "Finding body"
      })

    review_finding
  end

  defp create_verification_chain!(bootstrap) do
    signal = create_signal!(bootstrap, "Verification source")
    task = create_task!(bootstrap, signal)
    review_finding = create_review_finding!(bootstrap, task)
    verification_check = create_verification_check!(bootstrap, review_finding)

    %{
      signal: signal,
      task: task,
      review_finding: review_finding,
      verification_check: verification_check
    }
  end

  defp complete_verification!(bootstrap) do
    verification_check = create_verification_check!(bootstrap)
    {:ok, operation} = Operations.start_operation(bootstrap.session, :verification_complete)

    {:ok, completed} =
      Verification.complete_with_evidence(bootstrap.session, operation, verification_check, %{
        title: "Completed evidence",
        body: "Completed evidence body",
        artifact_uri: "https://example.test/completed-evidence"
      })

    completed
  end

  defp relationship_exists?(source_item_id, target_item_id, relationship_type) do
    GraphRelationship
    |> Ash.Query.filter(
      source_item_id == ^source_item_id and target_item_id == ^target_item_id and
        relationship_type == ^relationship_type
    )
    |> Ash.exists?(authorize?: false)
  end

  defp insert_graph_item!(bootstrap, resource_type, resource_id, title) do
    {:ok, graph_item} =
      Ash.create(
        GraphItem,
        %{
          id: Ecto.UUID.generate(),
          organization_id: bootstrap.organization.id,
          workspace_id: bootstrap.workspace.id,
          resource_type: resource_type,
          resource_id: resource_id,
          title: title
        },
        actor: bootstrap.session,
        action: :create
      )

    graph_item
  end

  defp insert_document!(bootstrap, plain_text) do
    Ash.create!(
      Document,
      %{
        id: Ecto.UUID.generate(),
        organization_id: bootstrap.organization.id,
        workspace_id: bootstrap.workspace.id,
        plain_text: plain_text
      },
      action: :create,
      authorize?: false
    )
  end

  defp document_with_plain_text?(plain_text) do
    Document
    |> Ash.Query.filter(plain_text == ^plain_text)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> false
      {:ok, _document} -> true
      {:error, _error} -> false
    end
  end
end
