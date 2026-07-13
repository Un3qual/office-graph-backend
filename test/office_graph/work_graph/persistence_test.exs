defmodule OfficeGraph.WorkGraph.PersistenceTest do
  use OfficeGraph.DataCase, async: false

  require Ash.Query

  alias OfficeGraph.Content

  alias OfficeGraph.Content.{
    Document,
    DocumentBlock,
    DocumentMark,
    DocumentReference,
    DocumentRevision
  }

  alias OfficeGraph.Authorization.RoleAssignment
  alias OfficeGraph.Foundation
  alias OfficeGraph.ExternalRefs.ExternalReference
  alias OfficeGraph.Identity.{Principal, Session, SessionContext}
  alias OfficeGraph.Integrations
  alias OfficeGraph.Integrations.{ExternalSource, NormalizedIntakeEvent, RawArchive}
  alias OfficeGraph.Operations
  alias OfficeGraph.Operations.OperationCorrelation
  alias OfficeGraph.Audit.AuditRecord
  alias OfficeGraph.Tenancy.Initiative
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

  test "operation correlation ids are unique only within a workspace scope", %{
    bootstrap: bootstrap
  } do
    correlation_id = "correlation-#{System.unique_integer([:positive])}"

    assert {:ok, _operation} =
             Operations.start_operation(bootstrap.session, :manual_intake_submit,
               correlation_id: correlation_id
             )

    assert {:error, same_scope_error} =
             Operations.start_operation(bootstrap.session, :manual_intake_submit,
               correlation_id: correlation_id
             )

    assert Exception.message(same_scope_error) =~ "correlation_id"

    assert {:ok, other_scope} =
             Foundation.bootstrap_local_owner(
               workspace_name: "Correlation Other Workspace",
               workspace_slug: "correlation-other-workspace",
               initiative_name: "Correlation Other Initiative",
               initiative_slug: "correlation-other-initiative"
             )

    assert other_scope.organization.id == bootstrap.organization.id
    assert other_scope.workspace.id != bootstrap.workspace.id

    assert {:ok, %OperationCorrelation{correlation_id: ^correlation_id}} =
             Operations.start_operation(other_scope.session, :manual_intake_submit,
               correlation_id: correlation_id
             )
  end

  test "operation idempotency keys reuse the existing operation within an action scope", %{
    bootstrap: bootstrap
  } do
    idempotency_key = "manual-intake:#{System.unique_integer([:positive])}"

    assert {:ok, first} =
             Operations.start_operation(bootstrap.session, :manual_intake_submit,
               correlation_id: "first-#{idempotency_key}",
               idempotency_key: idempotency_key
             )

    assert {:ok, second} =
             Operations.start_operation(bootstrap.session, :manual_intake_submit,
               correlation_id: "retry-#{idempotency_key}",
               idempotency_key: idempotency_key
             )

    assert second.id == first.id
    assert second.correlation_id == first.correlation_id

    assert 1 ==
             OperationCorrelation
             |> Ash.Query.filter(
               organization_id == ^bootstrap.organization.id and
                 workspace_id == ^bootstrap.workspace.id and
                 action == "manual_intake.submit" and
                 idempotency_key == ^idempotency_key
             )
             |> Ash.count!(authorize?: false)
  end

  test "operation creation rejects session contexts with a different principal", %{
    bootstrap: bootstrap
  } do
    bare_principal =
      Ash.create!(
        Principal,
        %{
          id: Ecto.UUID.generate(),
          email:
            "operation-principal-mismatch-#{System.unique_integer([:positive])}@office-graph.local",
          kind: "human",
          status: "active"
        },
        action: :create,
        authorize?: false
      )

    correlation_id = "operation-principal-mismatch-#{System.unique_integer([:positive])}"
    %SessionContext{} = owner_session = bootstrap.session

    forged = %SessionContext{
      owner_session
      | principal_id: bare_principal.id,
        capabilities: MapSet.new(["manual_intake.submit"])
    }

    assert {:error, :forbidden} =
             Operations.start_operation(forged, :manual_intake_submit,
               correlation_id: correlation_id
             )

    refute operation_correlation_exists?(bootstrap.organization.id, correlation_id)
  end

  test "operation creation rejects session contexts with a different workspace", %{
    bootstrap: bootstrap
  } do
    assert {:ok, other_workspace_scope} =
             Foundation.bootstrap_local_owner(
               workspace_name: "Operation Forged Workspace",
               workspace_slug: "operation-forged-workspace",
               initiative_name: "Operation Forged Initiative",
               initiative_slug: "operation-forged-initiative"
             )

    assert other_workspace_scope.organization.id == bootstrap.organization.id
    assert other_workspace_scope.workspace.id != bootstrap.workspace.id

    correlation_id = "operation-workspace-mismatch-#{System.unique_integer([:positive])}"
    %SessionContext{} = owner_session = bootstrap.session

    forged = %SessionContext{
      owner_session
      | workspace_id: other_workspace_scope.workspace.id,
        capabilities: MapSet.new(["manual_intake.submit"])
    }

    assert {:error, :forbidden} =
             Operations.start_operation(forged, :manual_intake_submit,
               correlation_id: correlation_id
             )

    refute operation_correlation_exists?(bootstrap.organization.id, correlation_id)
  end

  test "operation creation rejects revoked sessions", %{bootstrap: bootstrap} do
    revoked_session =
      Ash.create!(
        Session,
        %{
          id: Ecto.UUID.generate(),
          principal_id: bootstrap.principal.id,
          organization_id: bootstrap.organization.id,
          workspace_id: bootstrap.workspace.id,
          purpose: "revoked_operation_test",
          revoked_at: DateTime.utc_now()
        },
        action: :create,
        authorize?: false
      )

    correlation_id = "operation-revoked-session-#{System.unique_integer([:positive])}"
    %SessionContext{} = owner_session = bootstrap.session

    revoked_context = %SessionContext{
      owner_session
      | session_id: revoked_session.id,
        capabilities: MapSet.new(["manual_intake.submit"])
    }

    assert {:error, :forbidden} =
             Operations.start_operation(revoked_context, :manual_intake_submit,
               correlation_id: correlation_id
             )

    refute operation_correlation_exists?(bootstrap.organization.id, correlation_id)
  end

  test "role assignment identity treats nil workspace scope as comparable", %{
    bootstrap: bootstrap
  } do
    org_wide_assignment =
      Ash.create!(
        RoleAssignment,
        %{
          id: Ecto.UUID.generate(),
          principal_id: bootstrap.principal.id,
          role_id: bootstrap.role_assignment.role_id,
          organization_id: bootstrap.organization.id,
          workspace_id: nil
        },
        action: :create,
        authorize?: false
      )

    assert {:ok, %{id: org_wide_assignment_id}} =
             Ash.get(
               RoleAssignment,
               %{
                 principal_id: org_wide_assignment.principal_id,
                 role_id: org_wide_assignment.role_id,
                 organization_id: org_wide_assignment.organization_id,
                 workspace_id: nil
               },
               authorize?: false,
               not_found_error?: false
             )

    assert org_wide_assignment_id == org_wide_assignment.id
  end

  test "tenant hierarchy constraints reject mismatched workspace organization", %{
    bootstrap: bootstrap
  } do
    assert {:ok, other_scope} =
             Foundation.bootstrap_local_owner(
               organization_name: "Hierarchy Other Tenant",
               organization_slug: "hierarchy-other-tenant",
               workspace_name: "Hierarchy Other Workspace",
               workspace_slug: "hierarchy-other-workspace",
               initiative_name: "Hierarchy Other Initiative",
               initiative_slug: "hierarchy-other-initiative",
               owner_email: "hierarchy-other-owner@office-graph.local"
             )

    assert {:error, error} =
             Ash.create(
               Initiative,
               %{
                 id: Ecto.UUID.generate(),
                 organization_id: other_scope.organization.id,
                 workspace_id: bootstrap.workspace.id,
                 name: "Mismatched Initiative",
                 slug: "mismatched-initiative"
               },
               action: :create,
               authorize?: false
             )

    assert Exception.message(error) =~ "workspace"
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
    bootstrap: bootstrap
  } do
    {:ok, operation} = Operations.start_operation(bootstrap.session, :proposed_change_apply)

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

  test "plain document creation requires the capability matching the operation action", %{
    bootstrap: bootstrap
  } do
    for action <- [:manual_intake_submit, :proposed_change_apply, :verification_complete] do
      unauthorized = create_ungranted_session_context!(bootstrap, "content-#{action}")
      {:ok, operation} = Operations.start_operation(unauthorized, action)

      plain_text = "Unauthorized #{action} document #{System.unique_integer([:positive])}"

      assert {:error, :forbidden} =
               Content.create_plain_document(unauthorized, operation, plain_text)

      assert [] =
               Document
               |> Ash.Query.filter(plain_text == ^plain_text)
               |> Ash.read!(authorize?: false)

      assert [] =
               DocumentBlock
               |> Ash.Query.filter(text == ^plain_text)
               |> Ash.read!(authorize?: false)

      assert [] =
               DocumentRevision
               |> Ash.Query.filter(operation_id == ^operation.id)
               |> Ash.read!(authorize?: false)
    end
  end

  test "plain document creation rejects operation correlations from another context", %{
    bootstrap: bootstrap
  } do
    {:ok, other_scope} =
      Foundation.bootstrap_local_owner(
        organization_name: "Office Graph foreign document operation",
        organization_slug: "office-graph-foreign-document-operation",
        workspace_name: "Workspace foreign document operation",
        workspace_slug: "workspace-foreign-document-operation",
        initiative_name: "Initiative foreign document operation",
        initiative_slug: "initiative-foreign-document-operation",
        owner_email: "foreign-document-operation@office-graph.local",
        owner_name: "Foreign Document Operation"
      )

    {:ok, foreign_operation} =
      Operations.start_operation(other_scope.session, :manual_intake_submit)

    plain_text = "Foreign operation document #{System.unique_integer([:positive])}"

    assert {:error, :forbidden} =
             Content.create_plain_document(bootstrap.session, foreign_operation, plain_text)

    assert [] =
             Document
             |> Ash.Query.filter(plain_text == ^plain_text)
             |> Ash.read!(authorize?: false)
  end

  test "plain document creation rejects non-document-producing operations", %{
    bootstrap: bootstrap
  } do
    for action <- [:skeleton_read, :evidence_link] do
      {:ok, operation} = Operations.start_operation(bootstrap.session, action)
      plain_text = "Rejected #{action} document #{System.unique_integer([:positive])}"

      assert {:error, {:invalid_content_operation, operation_id}} =
               Content.create_plain_document(bootstrap.session, operation, plain_text)

      assert operation_id == operation.id

      assert [] =
               Document
               |> Ash.Query.filter(plain_text == ^plain_text)
               |> Ash.read!(authorize?: false)

      assert [] =
               DocumentBlock
               |> Ash.Query.filter(text == ^plain_text)
               |> Ash.read!(authorize?: false)

      assert [] =
               DocumentRevision
               |> Ash.Query.filter(operation_id == ^operation.id)
               |> Ash.read!(authorize?: false)
    end
  end

  test "content resources autogenerate ids for direct Ash creates", %{
    bootstrap: bootstrap,
    operation: operation
  } do
    document =
      Ash.create!(
        Document,
        %{
          organization_id: bootstrap.organization.id,
          workspace_id: bootstrap.workspace.id,
          plain_text: "Autogenerated document id"
        },
        action: :create,
        authorize?: false
      )

    block =
      Ash.create!(
        DocumentBlock,
        %{
          document_id: document.id,
          position: 0,
          block_type: "paragraph",
          text: "Autogenerated block id"
        },
        action: :create,
        authorize?: false
      )

    mark =
      Ash.create!(
        DocumentMark,
        %{
          block_id: block.id,
          mark_type: "strong"
        },
        action: :create,
        authorize?: false
      )

    reference =
      Ash.create!(
        DocumentReference,
        %{
          document_id: document.id,
          target_type: "operation",
          target_id: operation.id
        },
        action: :create,
        authorize?: false
      )

    revision =
      Ash.create!(
        DocumentRevision,
        %{
          document_id: document.id,
          operation_id: operation.id,
          revision_number: 1,
          semantic_summary: "initial"
        },
        action: :create,
        authorize?: false
      )

    for resource <- [document, block, mark, reference, revision] do
      assert {:ok, _binary_id} = Ecto.UUID.dump(resource.id)
    end

    explicit_id = Ecto.UUID.generate()

    explicit_document =
      Ash.create!(
        Document,
        %{
          id: explicit_id,
          organization_id: bootstrap.organization.id,
          workspace_id: bootstrap.workspace.id,
          plain_text: "Explicit document id"
        },
        action: :create,
        authorize?: false
      )

    assert explicit_document.id == explicit_id
  end

  test "content identity constraints surface duplicate block positions and revision numbers", %{
    bootstrap: bootstrap,
    operation: operation
  } do
    document =
      Ash.create!(
        Document,
        %{
          organization_id: bootstrap.organization.id,
          workspace_id: bootstrap.workspace.id,
          plain_text: "Document with duplicate identity attempts"
        },
        action: :create,
        authorize?: false
      )

    block_attrs = %{
      document_id: document.id,
      position: 0,
      block_type: "paragraph",
      text: "Duplicate position"
    }

    revision_attrs = %{
      document_id: document.id,
      operation_id: operation.id,
      revision_number: 1,
      semantic_summary: "initial"
    }

    assert {:ok, _block} =
             Ash.create(DocumentBlock, block_attrs, action: :create, authorize?: false)

    assert {:error, block_error} =
             Ash.create(DocumentBlock, block_attrs, action: :create, authorize?: false)

    block_message = ash_error_message(block_error)
    assert block_message =~ "document_id"
    assert block_message =~ "has already been taken"
    refute block_message =~ "constraint error when attempting to insert struct"

    assert {:ok, _revision} =
             Ash.create(DocumentRevision, revision_attrs, action: :create, authorize?: false)

    assert {:error, revision_error} =
             Ash.create(DocumentRevision, revision_attrs, action: :create, authorize?: false)

    revision_message = ash_error_message(revision_error)
    assert revision_message =~ "document_id"
    assert revision_message =~ "has already been taken"
    refute revision_message =~ "constraint error when attempting to insert struct"
  end

  test "content foreign key constraints surface invalid document and operation references", %{
    bootstrap: bootstrap
  } do
    assert {:error, document_error} =
             Ash.create(
               DocumentBlock,
               %{
                 document_id: Ecto.UUID.generate(),
                 position: 0,
                 block_type: "paragraph",
                 text: "Missing document"
               },
               action: :create,
               authorize?: false
             )

    document_message = ash_error_message(document_error)
    assert document_message =~ "document_id"
    refute document_message =~ "constraint error when attempting to insert struct"

    document =
      Ash.create!(
        Document,
        %{
          organization_id: bootstrap.organization.id,
          workspace_id: bootstrap.workspace.id,
          plain_text: "Document with missing operation revision"
        },
        action: :create,
        authorize?: false
      )

    assert {:error, operation_error} =
             Ash.create(
               DocumentRevision,
               %{
                 document_id: document.id,
                 operation_id: Ecto.UUID.generate(),
                 revision_number: 1,
                 semantic_summary: "missing operation"
               },
               action: :create,
               authorize?: false
             )

    operation_message = ash_error_message(operation_error)
    assert operation_message =~ "operation_id"
    refute operation_message =~ "constraint error when attempting to insert struct"
  end

  test "integration and external reference identities surface duplicate conflicts" do
    source_attrs = %{
      key: "manual:test-#{System.unique_integer([:positive])}",
      name: "Manual Intake",
      kind: "manual"
    }

    assert {:ok, source} =
             Ash.create(ExternalSource, source_attrs, action: :create, authorize?: false)

    assert {:error, source_error} =
             Ash.create(ExternalSource, source_attrs, action: :create, authorize?: false)

    source_message = ash_error_message(source_error)
    assert source_message =~ "key"
    assert source_message =~ "has already been taken"
    refute source_message =~ "constraint error when attempting to insert struct"

    reference_attrs = %{
      source_id: source.id,
      external_id: "ticket:#{System.unique_integer([:positive])}",
      resource_type: "signal",
      resource_id: Ecto.UUID.generate()
    }

    assert {:ok, _reference} =
             Ash.create(ExternalReference, reference_attrs, action: :create, authorize?: false)

    assert {:error, reference_error} =
             Ash.create(ExternalReference, reference_attrs, action: :create, authorize?: false)

    reference_message = ash_error_message(reference_error)
    assert reference_message =~ "source_id"
    assert reference_message =~ "has already been taken"
    refute reference_message =~ "constraint error when attempting to insert struct"
  end

  test "integration foreign key constraints surface invalid references", %{
    bootstrap: bootstrap,
    operation: operation
  } do
    source =
      Ash.create!(
        ExternalSource,
        %{
          key: "manual:fk-#{System.unique_integer([:positive])}",
          name: "Manual Intake",
          kind: "manual"
        },
        action: :create,
        authorize?: false
      )

    assert {:error, raw_error} =
             Ash.create(
               RawArchive,
               %{
                 organization_id: bootstrap.organization.id,
                 workspace_id: bootstrap.workspace.id,
                 source_id: Ecto.UUID.generate(),
                 operation_id: operation.id,
                 content_hash: "missing-source",
                 body: "Missing source"
               },
               action: :create,
               authorize?: false
             )

    raw_message = ash_error_message(raw_error)
    assert raw_message =~ "source_id"
    refute raw_message =~ "constraint error when attempting to insert struct"

    assert {:error, event_error} =
             Ash.create(
               NormalizedIntakeEvent,
               %{
                 organization_id: bootstrap.organization.id,
                 workspace_id: bootstrap.workspace.id,
                 raw_archive_id: Ecto.UUID.generate(),
                 operation_id: operation.id,
                 source_identity: source.key,
                 replay_identity: "missing-raw",
                 outcome: "accepted"
               },
               action: :create,
               authorize?: false
             )

    event_message = ash_error_message(event_error)
    assert event_message =~ "raw_archive_id"
    refute event_message =~ "constraint error when attempting to insert struct"
  end

  test "plain document creation rolls back document and block when revision creation fails", %{
    bootstrap: bootstrap,
    operation: operation
  } do
    plain_text = "Rollback document #{System.unique_integer([:positive])}"

    Repo.query!("""
    CREATE OR REPLACE FUNCTION office_graph_test_fail_document_revision()
    RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION 'injected document revision failure';
    END;
    $$ LANGUAGE plpgsql
    """)

    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_fail_document_revision ON document_revisions"
    )

    Repo.query!("""
    CREATE TRIGGER office_graph_test_fail_document_revision
    BEFORE INSERT ON document_revisions
    FOR EACH ROW
    EXECUTE FUNCTION office_graph_test_fail_document_revision()
    """)

    on_exit(fn ->
      Repo.query!(
        "DROP TRIGGER IF EXISTS office_graph_test_fail_document_revision ON document_revisions"
      )

      Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_fail_document_revision()")
    end)

    assert {:error, error} =
             Content.create_plain_document(bootstrap.session, operation, plain_text)

    assert ash_error_message(error) =~ "injected document revision failure"

    assert [] =
             Document
             |> Ash.Query.filter(plain_text == ^plain_text)
             |> Ash.read!(authorize?: false)

    assert [] =
             DocumentBlock
             |> Ash.Query.filter(text == ^plain_text)
             |> Ash.read!(authorize?: false)
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

    assert {:ok, first} = Integrations.submit_manual_intake(bootstrap.session, operation, attrs)
    assert first.duplicate? == false
    assert first.normalized_event.outcome == "accepted"
    assert first.raw_archive.content_hash
    assert length(first.proposed_changes) == 4

    assert {:ok, second} = Integrations.submit_manual_intake(bootstrap.session, operation, attrs)
    assert second.duplicate? == true
    assert second.normalized_event.outcome == "duplicate"
    assert second.normalized_event.duplicate_of_id == first.normalized_event.id
    assert second.proposed_changes == []

    assert {:error, duplicate_error} =
             Ash.create(
               NormalizedIntakeEvent,
               %{
                 organization_id: bootstrap.organization.id,
                 workspace_id: bootstrap.workspace.id,
                 raw_archive_id: first.raw_archive.id,
                 operation_id: operation.id,
                 source_identity: attrs.source_identity,
                 replay_identity: attrs.replay_identity,
                 outcome: "accepted"
               },
               action: :create,
               authorize?: false
             )

    assert Exception.message(duplicate_error) =~
             "normalized_intake_events_accepted_replay_identity_index"
  end

  test "manual intake rejects same replay identity with changed content", %{
    bootstrap: bootstrap,
    operation: operation
  } do
    attrs = %{
      source_identity: "manual:changed-content",
      replay_identity: "paste:changed-content",
      body: "Task: Investigate stable replay content"
    }

    assert {:ok, first} = Integrations.submit_manual_intake(bootstrap.session, operation, attrs)
    assert first.normalized_event.outcome == "accepted"

    conflicting_attrs = %{attrs | body: "Task: Investigate conflicting replay content"}
    accepted_event_id = first.normalized_event.id

    assert {:error, {:manual_intake_replay_conflict, ^accepted_event_id}} =
             Integrations.submit_manual_intake(bootstrap.session, operation, conflicting_attrs)

    assert 1 ==
             NormalizedIntakeEvent
             |> Ash.Query.filter(
               organization_id == ^bootstrap.organization.id and
                 workspace_id == ^bootstrap.workspace.id and
                 source_identity == ^attrs.source_identity and
                 replay_identity == ^attrs.replay_identity
             )
             |> Ash.count!(authorize?: false)
  end

  test "manual intake replay duplicates are scoped to workspace within an organization", %{
    bootstrap: bootstrap,
    operation: operation
  } do
    attrs = %{
      source_identity: "manual:tenant-scope",
      replay_identity: "paste:tenant-scope-1",
      body: "Task: Verify tenant-scoped intake replay"
    }

    assert {:ok, first} = Integrations.submit_manual_intake(bootstrap.session, operation, attrs)
    assert first.normalized_event.outcome == "accepted"
    assert length(first.proposed_changes) == 4

    assert {:ok, same_org_other_workspace} =
             Foundation.bootstrap_local_owner(
               workspace_name: "Second Workspace",
               workspace_slug: "second-workspace",
               initiative_name: "Second Walking Skeleton",
               initiative_slug: "second-walking-skeleton"
             )

    {:ok, same_org_other_workspace_operation} =
      Operations.start_operation(same_org_other_workspace.session, :manual_intake_submit)

    assert {:ok, cross_workspace} =
             Integrations.submit_manual_intake(
               same_org_other_workspace.session,
               same_org_other_workspace_operation,
               attrs
             )

    assert cross_workspace.normalized_event.outcome == "accepted"
    refute cross_workspace.normalized_event.duplicate_of_id
    assert length(cross_workspace.proposed_changes) == 4

    assert {:ok, second_tenant} =
             Foundation.bootstrap_local_owner(
               organization_name: "Second Tenant",
               organization_slug: "second-tenant",
               workspace_name: "Second Workspace",
               workspace_slug: "second-workspace",
               initiative_name: "Second Walking Skeleton",
               initiative_slug: "second-walking-skeleton",
               owner_email: "second-owner@office-graph.local",
               owner_name: "Second Owner"
             )

    {:ok, second_tenant_operation} =
      Operations.start_operation(second_tenant.session, :manual_intake_submit)

    assert {:ok, cross_scope} =
             Integrations.submit_manual_intake(
               second_tenant.session,
               second_tenant_operation,
               attrs
             )

    assert cross_scope.normalized_event.outcome == "accepted"
    refute cross_scope.normalized_event.duplicate_of_id
    assert length(cross_scope.proposed_changes) == 4

    assert {:ok, same_scope_duplicate} =
             Integrations.submit_manual_intake(bootstrap.session, operation, attrs)

    assert same_scope_duplicate.normalized_event.outcome == "duplicate"
    assert same_scope_duplicate.normalized_event.duplicate_of_id == first.normalized_event.id
    assert same_scope_duplicate.proposed_changes == []
  end

  defp ash_error_message(%Ash.Changeset{} = changeset) do
    changeset.errors
    |> Ash.Error.to_error_class()
    |> Exception.message()
  end

  defp ash_error_message(error), do: Exception.message(error)

  defp operation_correlation_exists?(organization_id, correlation_id) do
    OperationCorrelation
    |> Ash.Query.filter(organization_id == ^organization_id and correlation_id == ^correlation_id)
    |> Ash.exists?(authorize?: false)
  end

  defp create_ungranted_session_context!(bootstrap, purpose) do
    principal =
      Ash.create!(
        Principal,
        %{
          id: Ecto.UUID.generate(),
          email: "#{purpose}-#{System.unique_integer([:positive])}@office-graph.local",
          kind: "human",
          status: "active"
        },
        action: :create,
        authorize?: false
      )

    session =
      Ash.create!(
        Session,
        %{
          id: Ecto.UUID.generate(),
          principal_id: principal.id,
          organization_id: bootstrap.organization.id,
          workspace_id: bootstrap.workspace.id,
          purpose: purpose
        },
        action: :create,
        authorize?: false
      )

    %SessionContext{
      principal_id: principal.id,
      session_id: session.id,
      organization_id: bootstrap.organization.id,
      workspace_id: bootstrap.workspace.id,
      capabilities: MapSet.new()
    }
  end
end
