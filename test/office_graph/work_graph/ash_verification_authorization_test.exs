defmodule OfficeGraph.WorkGraph.AshVerificationAuthorizationTest do
  use OfficeGraph.TestSupport.AshAuthorizationSupport

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

  test "public WorkGraph verification completion requires verification complete capability" do
    {:ok, bootstrap} = bootstrap_scope("completion-capability")
    verification_check = create_verification_check!(bootstrap)

    evidence_only =
      create_limited_session_context!(bootstrap, "completion-capability", ["evidence.link"])

    {:ok, operation} = Operations.start_operation(evidence_only, :verification_complete)
    body = "Direct completion must require verification completion capability."

    assert {:error, :forbidden} =
             WorkGraph.complete_verification(evidence_only, operation, verification_check, %{
               title: "Reject unauthorized completion",
               body: body,
               artifact_uri: "https://example.test/reject-completion-capability"
             })

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

  test "verification completion keeps task open until all findings complete" do
    {:ok, bootstrap} = bootstrap_scope("completion-all-findings")
    signal = create_signal!(bootstrap, "Multi-finding source")
    task = create_task!(bootstrap, signal)
    first_finding = create_review_finding!(bootstrap, task)
    second_finding = create_review_finding!(bootstrap, task)
    first_check = create_verification_check!(bootstrap, first_finding)
    second_check = create_verification_check!(bootstrap, second_finding)

    {:ok, first_operation} = Operations.start_operation(bootstrap.session, :verification_complete)

    assert {:ok, first_completion} =
             Verification.complete_with_evidence(
               bootstrap.session,
               first_operation,
               first_check,
               %{
                 title: "First finding evidence",
                 body: "Another finding remains open on the same task.",
                 artifact_uri: "https://example.test/first-finding"
               }
             )

    assert first_completion.review_finding.lifecycle_state == "verified_complete"
    assert first_completion.task.lifecycle_state == "open"

    assert "open" ==
             TaskResource
             |> Ash.get!(task.id, authorize?: false)
             |> Map.fetch!(:lifecycle_state)

    {:ok, second_operation} =
      Operations.start_operation(bootstrap.session, :verification_complete)

    assert {:ok, second_completion} =
             Verification.complete_with_evidence(
               bootstrap.session,
               second_operation,
               second_check,
               %{
                 title: "Second finding evidence",
                 body: "All findings are now complete.",
                 artifact_uri: "https://example.test/second-finding"
               }
             )

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

  test "verification check satisfaction is internal to completion flow" do
    {:ok, bootstrap} = bootstrap_scope("state-transition-internal")
    verification_check = create_verification_check!(bootstrap)

    assert {:error, error} =
             verification_check
             |> Ash.Changeset.for_update(:mark_satisfied, %{}, actor: bootstrap.session)
             |> Ash.update()

    assert Exception.message(error) =~ ~r/forbidden/i

    assert "required" ==
             VerificationCheckResource
             |> Ash.get!(verification_check.id, authorize?: false)
             |> Map.fetch!(:lifecycle_state)
  end

  test "verification result creation is internal to completion flow" do
    {:ok, bootstrap} = bootstrap_scope("result-create-internal")
    chain = create_verification_chain!(bootstrap)
    artifact = insert_artifact!(bootstrap, "Direct result artifact")
    evidence = insert_evidence_item!(bootstrap, chain.verification_check, artifact)
    {:ok, operation} = Operations.start_operation(bootstrap.session, :verification_complete)

    assert {:error, error} =
             Ash.create(
               VerificationResultResource,
               %{
                 id: Ecto.UUID.generate(),
                 organization_id: bootstrap.organization.id,
                 workspace_id: bootstrap.workspace.id,
                 verification_check_id: chain.verification_check.id,
                 evidence_item_id: evidence.id,
                 operation_id: operation.id,
                 result: "passed"
               },
               actor: bootstrap.session,
               action: :create
             )

    assert Exception.message(error) =~ ~r/forbidden/i

    assert {:ok, completed} =
             Verification.complete_with_evidence(
               bootstrap.session,
               operation,
               chain.verification_check,
               %{
                 title: "Official completion evidence",
                 body: "The official flow remains the path that creates results.",
                 artifact_uri: "https://example.test/official-result-create"
               }
             )

    assert completed.verification_result.result == "passed"
    assert completed.verification_check.lifecycle_state == "satisfied"
    assert completed.review_finding.lifecycle_state == "verified_complete"
  end

  test "verification results require evidence from the same check" do
    {:ok, bootstrap} = bootstrap_scope("result-evidence-check-match")
    unmatched_chain = create_verification_chain!(bootstrap)
    completed = complete_verification!(bootstrap)
    {:ok, operation} = Operations.start_operation(bootstrap.session, :verification_complete)

    assert {:error, error} =
             Ash.create(
               VerificationResultResource,
               %{
                 id: Ecto.UUID.generate(),
                 organization_id: bootstrap.organization.id,
                 workspace_id: bootstrap.workspace.id,
                 verification_check_id: unmatched_chain.verification_check.id,
                 evidence_item_id: completed.evidence_item.id,
                 operation_id: operation.id,
                 result: "passed"
               },
               authorize?: false,
               action: :create
             )

    assert Exception.message(error) =~ "evidence_item_id"
  end

  test "waived verification results require no evidence and separate authority" do
    {:ok, bootstrap} = bootstrap_scope("waived-result-contract")
    chain = create_verification_chain!(bootstrap)
    artifact = insert_artifact!(bootstrap, "Waiver contract artifact")
    evidence = insert_evidence_item!(bootstrap, chain.verification_check, artifact)

    limited_session =
      create_limited_session_context!(bootstrap, "waiver-authority", ["skeleton.read"])

    assert {:error, :forbidden} =
             Authorization.authorize(limited_session, :verification_waive,
               organization_id: bootstrap.organization.id
             )

    {:ok, denied_operation} = Operations.start_operation(limited_session, :verification_waive)

    assert {:error, :forbidden} =
             Authorization.authorize_operation(
               limited_session,
               denied_operation,
               :verification_waive,
               organization_id: bootstrap.organization.id
             )

    assert AuthorizationDecision
           |> Ash.Query.filter(operation_id == ^denied_operation.id and decision == "deny")
           |> Ash.exists?(authorize?: false)

    {:ok, operation} = Operations.start_operation(bootstrap.session, :verification_waive)

    assert {:error, evidence_error} =
             Ash.create(
               VerificationResultResource,
               %{
                 id: Ecto.UUID.generate(),
                 organization_id: bootstrap.organization.id,
                 workspace_id: bootstrap.workspace.id,
                 verification_check_id: chain.verification_check.id,
                 evidence_item_id: evidence.id,
                 operation_id: operation.id,
                 actor_principal_id: bootstrap.session.principal_id,
                 policy_basis: "owner_exception",
                 reason: "Waivers are governance decisions, not evidence.",
                 recorded_at: DateTime.utc_now(),
                 result: "waived"
               },
               authorize?: false,
               action: :create
             )

    assert Exception.message(evidence_error) =~ "evidence_item_id"

    assert {:ok, waived_result} =
             Ash.create(
               VerificationResultResource,
               %{
                 id: Ecto.UUID.generate(),
                 organization_id: bootstrap.organization.id,
                 workspace_id: bootstrap.workspace.id,
                 verification_check_id: chain.verification_check.id,
                 evidence_item_id: nil,
                 operation_id: operation.id,
                 actor_principal_id: bootstrap.session.principal_id,
                 policy_basis: "owner_exception",
                 reason: "Approved exception.",
                 recorded_at: DateTime.utc_now(),
                 result: "waived"
               },
               authorize?: false,
               action: :create
             )

    assert waived_result.result == "waived"
    assert waived_result.evidence_item_id == nil

    missing_evidence_chain = create_verification_chain!(bootstrap)

    {:ok, missing_evidence_operation} =
      Operations.start_operation(bootstrap.session, :verification_complete)

    assert {:error, missing_evidence_error} =
             Ash.create(
               VerificationResultResource,
               %{
                 id: Ecto.UUID.generate(),
                 organization_id: bootstrap.organization.id,
                 workspace_id: bootstrap.workspace.id,
                 verification_check_id: missing_evidence_chain.verification_check.id,
                 evidence_item_id: nil,
                 operation_id: missing_evidence_operation.id,
                 result: "passed"
               },
               authorize?: false,
               action: :create
             )

    assert Exception.message(missing_evidence_error) =~ "evidence_item_id"
  end

  test "verification evidence match lookup fails closed when evidence cannot be read" do
    assert false ==
             ValidateResultEvidence.evidence_matches_check?(
               Ecto.UUID.generate(),
               Ecto.UUID.generate(),
               fn _evidence_item_id -> {:error, :database_unavailable} end
             )
  end

  test "verification completion does not require skeleton read capability for internal reloads" do
    {:ok, bootstrap} = bootstrap_scope("verification-without-read")
    verification_check = create_verification_check!(bootstrap)

    verification_actor =
      create_limited_session_context!(bootstrap, "verification-without-read", [
        "evidence.link",
        "verification.complete"
      ])

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
end
