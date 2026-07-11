defmodule OfficeGraph.ProposedChangesTest do
  use OfficeGraph.DataCase, async: false

  require Ash.Query

  alias OfficeGraph.Foundation
  alias OfficeGraph.Authorization.{Capability, Role, RoleAssignment, RoleCapability}
  alias OfficeGraph.Authorization.AuthorizationDecision
  alias OfficeGraph.Identity.{Principal, Session, SessionContext}
  alias OfficeGraph.Integrations
  alias OfficeGraph.Integrations.{ExternalSource, NormalizedIntakeEvent, RawArchive}
  alias OfficeGraph.Operations
  alias OfficeGraph.ProposedChanges
  alias OfficeGraph.ProposedChanges.ProposedGraphChange
  alias OfficeGraph.Repo
  alias OfficeGraph.WorkGraph

  setup do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, intake_operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)

    {:ok, intake} =
      Integrations.submit_manual_intake(bootstrap.session, intake_operation, %{
        source_identity: "manual:web",
        replay_identity: "paste:proposed-change-test",
        body: "Investigate flaky deploy and prove it."
      })

    %{bootstrap: bootstrap, intake: intake, intake_operation: intake_operation}
  end

  test "invalid proposed changes are rejected without applying graph truth", %{
    bootstrap: bootstrap,
    intake: intake
  } do
    invalid =
      intake.proposed_changes
      |> hd()
      |> update_payload!(bootstrap.session, %{"body" => "missing title"})

    proposed_changes = [invalid | tl(intake.proposed_changes)]
    {:ok, apply_operation} = Operations.start_operation(bootstrap.session, :proposed_change_apply)
    invalid_id = invalid.id

    assert {:error, {:invalid_proposed_change, ^invalid_id}} =
             ProposedChanges.apply_all(bootstrap.session, apply_operation, proposed_changes)

    assert get_change!(invalid).status == "rejected"
  end

  test "non-string proposed change payload fields are invalid instead of crashing", %{
    bootstrap: bootstrap,
    intake: intake
  } do
    invalid =
      intake.proposed_changes
      |> hd()
      |> update_payload!(bootstrap.session, %{
        "title" => %{"bad" => "shape"},
        "body" => "A valid body should not rescue a malformed title."
      })

    proposed_changes = [invalid | tl(intake.proposed_changes)]
    {:ok, apply_operation} = Operations.start_operation(bootstrap.session, :proposed_change_apply)
    invalid_id = invalid.id

    assert {:error, {:invalid_proposed_change, ^invalid_id}} =
             ProposedChanges.apply_all(bootstrap.session, apply_operation, proposed_changes)

    assert get_change!(invalid).status == "rejected"
  end

  test "get_many! preserves caller order and raises for missing ids", %{
    bootstrap: bootstrap,
    intake: intake
  } do
    ids =
      intake.proposed_changes
      |> Enum.map(& &1.id)
      |> Enum.reverse()

    assert ids ==
             ids
             |> then(&ProposedChanges.get_many!(bootstrap.session, &1))
             |> Enum.map(& &1.id)

    assert_raise KeyError, fn ->
      ProposedChanges.get_many!(bootstrap.session, [Ecto.UUID.generate()])
    end
  end

  test "get_many! does not load proposed changes outside the caller scope", %{
    bootstrap: bootstrap
  } do
    foreign = submit_scoped_intake!("foreign-proposed-load")
    foreign_id = foreign.intake.proposed_changes |> hd() |> Map.fetch!(:id)

    assert_raise KeyError, fn ->
      ProposedChanges.get_many!(bootstrap.session, [foreign_id])
    end
  end

  test "direct Ash create cannot spoof proposed change lifecycle fields", %{bootstrap: bootstrap} do
    {:ok, intake_operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)

    assert_raise Ash.Error.Invalid, ~r/No such input `status`/, fn ->
      ProposedGraphChange
      |> Ash.Changeset.for_create(
        :create,
        %{
          organization_id: bootstrap.session.organization_id,
          workspace_id: bootstrap.session.workspace_id,
          operation_id: intake_operation.id,
          status: "applied",
          change_type: "create_signal",
          payload: %{"title" => "Spoofed lifecycle", "body" => "This must stay pending."},
          validation_errors: ["spoofed"],
          applied_at: DateTime.utc_now()
        },
        actor: bootstrap.session
      )
      |> Ash.create!()
    end
  end

  test "direct Ash create rejects operation trace outside the proposed change scope", %{
    bootstrap: bootstrap
  } do
    foreign = submit_scoped_intake!("foreign-operation-trace")

    assert {:error, error} =
             ProposedGraphChange
             |> Ash.Changeset.for_create(
               :create,
               %{
                 organization_id: bootstrap.session.organization_id,
                 workspace_id: bootstrap.session.workspace_id,
                 operation_id: foreign.intake.normalized_event.operation_id,
                 change_type: "create_signal",
                 payload: %{"title" => "Spoofed operation", "body" => "Wrong operation scope."}
               },
               actor: bootstrap.session
             )
             |> Ash.create()

    assert Exception.message(error) =~ "operation_id must match proposed change scope"
  end

  test "direct Ash create rejects operation traces from another same-scope actor", %{
    bootstrap: bootstrap
  } do
    {:ok, other_same_scope} =
      Foundation.bootstrap_local_owner(
        organization_name: bootstrap.organization.name,
        organization_slug: bootstrap.organization.slug,
        workspace_name: bootstrap.workspace.name,
        workspace_slug: bootstrap.workspace.slug,
        initiative_name: "Operation trace same scope",
        initiative_slug: "operation-trace-same-scope",
        owner_email: "other-operation-trace@office-graph.local",
        owner_name: "Other Operation Trace"
      )

    {:ok, foreign_operation} =
      Operations.start_operation(other_same_scope.session, :manual_intake_submit)

    assert {:error, error} =
             ProposedGraphChange
             |> Ash.Changeset.for_create(
               :create,
               %{
                 organization_id: bootstrap.session.organization_id,
                 workspace_id: bootstrap.session.workspace_id,
                 operation_id: foreign_operation.id,
                 change_type: "create_signal",
                 payload: %{"title" => "Spoofed operation", "body" => "Wrong actor trace."}
               },
               actor: bootstrap.session
             )
             |> Ash.create()

    assert Exception.message(error) =~ "operation_id"
    assert Exception.message(error) =~ "current manual intake operation"
  end

  test "direct Ash payload updates reject another same-scope intake actor", %{
    bootstrap: bootstrap,
    intake: intake
  } do
    {:ok, other_same_scope} =
      Foundation.bootstrap_local_owner(
        organization_name: bootstrap.organization.name,
        organization_slug: bootstrap.organization.slug,
        workspace_name: bootstrap.workspace.name,
        workspace_slug: bootstrap.workspace.slug,
        initiative_name: "Payload Update Actor",
        initiative_slug: "payload-update-actor",
        owner_email: "other-payload-update@office-graph.local",
        owner_name: "Other Payload Update"
      )

    change = hd(intake.proposed_changes)
    original_payload = change.payload

    assert {:error, error} =
             change
             |> Ash.Changeset.for_update(:set_payload, %{
               payload: %{
                 "title" => "Foreign payload edit",
                 "body" => "Another intake actor must not rewrite this proposed change."
               }
             })
             |> Ash.update(actor: other_same_scope.session)

    assert Exception.message(error) =~ ~r/forbidden/i
    assert get_change!(change).payload == original_payload
  end

  test "direct Ash create rejects non-manual-intake operation traces", %{
    bootstrap: bootstrap
  } do
    {:ok, apply_operation} = Operations.start_operation(bootstrap.session, :proposed_change_apply)

    assert {:error, error} =
             ProposedGraphChange
             |> Ash.Changeset.for_create(
               :create,
               %{
                 organization_id: bootstrap.session.organization_id,
                 workspace_id: bootstrap.session.workspace_id,
                 operation_id: apply_operation.id,
                 change_type: "create_signal",
                 payload: %{"title" => "Spoofed operation", "body" => "Wrong action trace."}
               },
               actor: bootstrap.session
             )
             |> Ash.create()

    assert Exception.message(error) =~ "operation_id"
    assert Exception.message(error) =~ "current manual intake operation"
  end

  test "direct Ash create rejects normalized event trace outside the proposed change scope", %{
    bootstrap: bootstrap
  } do
    {:ok, intake_operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)
    foreign = submit_scoped_intake!("foreign-event-trace")

    assert {:error, error} =
             ProposedGraphChange
             |> Ash.Changeset.for_create(
               :create,
               %{
                 organization_id: bootstrap.session.organization_id,
                 workspace_id: bootstrap.session.workspace_id,
                 operation_id: intake_operation.id,
                 normalized_event_id: foreign.intake.normalized_event.id,
                 change_type: "create_signal",
                 payload: %{"title" => "Spoofed event", "body" => "Wrong event scope."}
               },
               actor: bootstrap.session
             )
             |> Ash.create()

    assert Exception.message(error) =~ "normalized_event_id must match proposed change scope"
  end

  test "direct Ash create rejects normalized events from a different manual intake operation", %{
    bootstrap: bootstrap,
    intake: intake
  } do
    {:ok, other_operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)

    other_event =
      create_accepted_event_without_changes!(
        bootstrap.session,
        other_operation,
        "mismatched-event-operation"
      )

    assert {:error, error} =
             ProposedGraphChange
             |> Ash.Changeset.for_create(
               :create,
               %{
                 organization_id: bootstrap.session.organization_id,
                 workspace_id: bootstrap.session.workspace_id,
                 operation_id: intake.normalized_event.operation_id,
                 normalized_event_id: other_event.id,
                 change_type: "create_signal",
                 payload: %{
                   "title" => "Spoofed event operation",
                   "body" => "The event must belong to the operation trace."
                 }
               },
               actor: bootstrap.session
             )
             |> Ash.create()

    message = Exception.message(error)
    assert message =~ "normalized_event_id"
    assert message =~ "operation_id"
  end

  test "manual intake proposed change creation rejects events from a different operation", %{
    bootstrap: bootstrap,
    intake: intake
  } do
    {:ok, other_operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)
    event_id = intake.normalized_event.id

    assert {:error,
            {:invalid_proposed_change_set, {:normalized_event_operation_mismatch, ^event_id}}} =
             ProposedChanges.create_for_manual_intake(
               bootstrap.session,
               other_operation,
               intake.normalized_event,
               %{
                 body: "Investigate mismatched operation reuse and prove it."
               }
             )
  end

  test "unauthorized sessions cannot apply proposed changes", %{
    bootstrap: bootstrap,
    intake: intake
  } do
    unauthorized = %SessionContext{
      principal_id: Ecto.UUID.generate(),
      session_id: Ecto.UUID.generate(),
      organization_id: bootstrap.organization.id,
      workspace_id: bootstrap.workspace.id,
      capabilities: MapSet.new()
    }

    {:ok, apply_operation} = Operations.start_operation(bootstrap.session, :proposed_change_apply)

    assert {:error, :forbidden} =
             ProposedChanges.apply_all(unauthorized, apply_operation, intake.proposed_changes)

    assert Enum.all?(
             intake.proposed_changes,
             &(get_change!(&1).status == "pending")
           )
  end

  test "denied proposed change application records an authorization decision", %{
    bootstrap: bootstrap,
    intake: intake
  } do
    unauthorized = create_session_without_roles!(bootstrap)
    {:ok, apply_operation} = Operations.start_operation(unauthorized, :proposed_change_apply)

    assert {:error, :forbidden} =
             ProposedChanges.apply_all(unauthorized, apply_operation, intake.proposed_changes)

    decision =
      AuthorizationDecision
      |> Ash.Query.filter(
        operation_id == ^apply_operation.id and action == "proposed_change.apply"
      )
      |> Ash.read_one!(authorize?: false)

    assert decision.principal_id == unauthorized.principal_id
    assert decision.organization_id == unauthorized.organization_id
    assert decision.decision == "deny"
    assert decision.reason == "missing_capability"
  end

  test "operation session mismatches deny without recording authorization decisions", %{
    bootstrap: bootstrap,
    intake: intake
  } do
    unauthorized = create_session_without_roles!(bootstrap)

    {:ok, foreign_apply_operation} =
      Operations.start_operation(bootstrap.session, :proposed_change_apply)

    assert {:error, :forbidden} =
             ProposedChanges.apply_all(
               unauthorized,
               foreign_apply_operation,
               intake.proposed_changes
             )

    assert Enum.all?(
             intake.proposed_changes,
             &(get_change!(&1).status == "pending")
           )

    assert 0 ==
             AuthorizationDecision
             |> Ash.Query.filter(operation_id == ^foreign_apply_operation.id)
             |> Ash.count!(authorize?: false)
  end

  test "apply-only sessions can create proposed signal graph truth", %{
    bootstrap: bootstrap,
    intake: intake
  } do
    apply_only = create_session_with_capabilities!(bootstrap, ["proposed_change.apply"])
    {:ok, apply_operation} = Operations.start_operation(apply_only, :proposed_change_apply)

    assert {:ok, applied} =
             ProposedChanges.apply_all(apply_only, apply_operation, intake.proposed_changes)

    assert applied.signal.title == "Investigate flaky deploy and prove it"

    assert Enum.all?(intake.proposed_changes, fn change ->
             change = get_change!(change)
             change.status == "applied" and not is_nil(change.applied_at)
           end)
  end

  test "apply-only sessions can replay their exact applied proposal chain", %{
    bootstrap: bootstrap,
    intake: intake
  } do
    apply_only = create_session_with_capabilities!(bootstrap, ["proposed_change.apply"])
    refute MapSet.member?(apply_only.capabilities, "skeleton.read")

    {:ok, apply_operation} = Operations.start_operation(apply_only, :proposed_change_apply)

    assert {:ok, first} =
             ProposedChanges.apply_all(apply_only, apply_operation, intake.proposed_changes)

    assert {:ok, replay} =
             ProposedChanges.apply_all(apply_only, apply_operation, intake.proposed_changes)

    assert Map.new(first, fn {key, record} -> {key, record.id} end) ==
             Map.new(replay, fn {key, record} -> {key, record.id} end)
  end

  test "manual intake titles use the first nonblank body segment", %{bootstrap: bootstrap} do
    {:ok, intake_operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)

    {:ok, intake} =
      Integrations.submit_manual_intake(bootstrap.session, intake_operation, %{
        source_identity: "manual:leading-newline",
        replay_identity: "paste:leading-newline",
        body: "\nInvestigate deploy health and prove it."
      })

    assert find_change(intake.proposed_changes, "create_signal").payload["title"] ==
             "Investigate deploy health and prove it"

    {:ok, apply_operation} = Operations.start_operation(bootstrap.session, :proposed_change_apply)

    assert {:ok, applied} =
             ProposedChanges.apply_all(
               bootstrap.session,
               apply_operation,
               intake.proposed_changes
             )

    assert applied.signal.title == "Investigate deploy health and prove it"
  end

  test "manual intake proposed change creation is idempotent per accepted event", %{
    bootstrap: bootstrap,
    intake: intake,
    intake_operation: intake_operation
  } do
    assert {:ok, repeated} =
             ProposedChanges.create_for_manual_intake(
               bootstrap.session,
               intake_operation,
               intake.normalized_event,
               %{
                 body: "Investigate flaky deploy and prove it."
               }
             )

    assert Enum.map(repeated, & &1.id) |> Enum.sort() ==
             Enum.map(intake.proposed_changes, & &1.id) |> Enum.sort()

    persisted_count =
      ProposedGraphChange
      |> Ash.Query.filter(normalized_event_id == ^intake.normalized_event.id)
      |> Ash.count!(authorize?: false)

    assert persisted_count == length(required_change_types())
  end

  test "direct Ash create rejects duplicate normalized event change types", %{
    bootstrap: bootstrap,
    intake: intake
  } do
    existing = find_change(intake.proposed_changes, "create_signal")

    assert {:error, error} =
             ProposedGraphChange
             |> Ash.Changeset.for_create(
               :create,
               %{
                 organization_id: bootstrap.session.organization_id,
                 workspace_id: bootstrap.session.workspace_id,
                 operation_id: existing.operation_id,
                 normalized_event_id: intake.normalized_event.id,
                 change_type: existing.change_type,
                 payload: %{
                   "title" => "Duplicate proposed signal",
                   "body" => "This duplicate should be rejected."
                 }
               },
               actor: bootstrap.session
             )
             |> Ash.create()

    assert Exception.message(error) =~ "normalized_event_id"
    assert Exception.message(error) =~ "change_type"
  end

  test "direct Ash create rejects duplicate normalized intake events", %{bootstrap: bootstrap} do
    suffix = System.unique_integer([:positive])
    source_identity = "manual:duplicate-event-create-#{suffix}"
    replay_identity = "paste:duplicate-event-create-#{suffix}"
    body = "Investigate duplicate event create and prove it."

    {:ok, first_operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)

    assert {:ok, %{normalized_event: %{outcome: "accepted"}}} =
             Integrations.submit_manual_intake(bootstrap.session, first_operation, %{
               source_identity: source_identity,
               replay_identity: replay_identity,
               body: body
             })

    {:ok, duplicate_operation} =
      Operations.start_operation(bootstrap.session, :manual_intake_submit)

    assert {:ok, duplicate_intake} =
             Integrations.submit_manual_intake(bootstrap.session, duplicate_operation, %{
               source_identity: source_identity,
               replay_identity: replay_identity,
               body: body
             })

    duplicate_event_id = duplicate_intake.normalized_event.id
    assert duplicate_intake.normalized_event.outcome == "duplicate"
    assert duplicate_intake.proposed_changes == []

    assert {:error, error} =
             ProposedGraphChange
             |> Ash.Changeset.for_create(
               :create,
               %{
                 organization_id: bootstrap.session.organization_id,
                 workspace_id: bootstrap.session.workspace_id,
                 operation_id: duplicate_operation.id,
                 normalized_event_id: duplicate_event_id,
                 change_type: "create_signal",
                 payload: %{
                   "title" => "Duplicate event proposed signal",
                   "body" => "This duplicate event proposal should be rejected."
                 }
               },
               actor: bootstrap.session
             )
             |> Ash.create()

    assert Exception.message(error) =~ "normalized_event_id"
    assert Exception.message(error) =~ "accepted"

    persisted_count =
      ProposedGraphChange
      |> Ash.Query.filter(normalized_event_id == ^duplicate_event_id)
      |> Ash.count!(authorize?: false)

    assert persisted_count == 0
  end

  test "apply requires a proposed change apply operation", %{
    bootstrap: bootstrap,
    intake: intake
  } do
    {:ok, manual_operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)
    operation_id = manual_operation.id

    assert {:error, {:invalid_apply_operation, ^operation_id}} =
             ProposedChanges.apply_all(
               bootstrap.session,
               manual_operation,
               intake.proposed_changes
             )

    assert Enum.all?(intake.proposed_changes, &(get_change!(&1).status == "pending"))
  end

  test "apply rejects complete change sets without an intake trace", %{bootstrap: bootstrap} do
    {:ok, intake_operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)
    {:ok, apply_operation} = Operations.start_operation(bootstrap.session, :proposed_change_apply)

    proposed_changes =
      Enum.map(required_change_types(), fn change_type ->
        create_untraced_change!(bootstrap.session, intake_operation, change_type)
      end)

    assert {:error, {:invalid_proposed_change_set, :missing_normalized_event_id}} =
             ProposedChanges.apply_all(bootstrap.session, apply_operation, proposed_changes)

    assert Enum.all?(proposed_changes, &(get_change!(&1).status == "pending"))
  end

  test "apply rejects complete change sets traced to duplicate intake events", %{
    bootstrap: bootstrap
  } do
    suffix = System.unique_integer([:positive])
    source_identity = "manual:duplicate-event-apply-#{suffix}"
    replay_identity = "paste:duplicate-event-apply-#{suffix}"

    {:ok, first_operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)

    assert {:ok, %{normalized_event: %{outcome: "accepted"}}} =
             Integrations.submit_manual_intake(bootstrap.session, first_operation, %{
               source_identity: source_identity,
               replay_identity: replay_identity,
               body: "Investigate duplicate event apply and prove it."
             })

    {:ok, duplicate_operation} =
      Operations.start_operation(bootstrap.session, :manual_intake_submit)

    assert {:ok, duplicate_intake} =
             Integrations.submit_manual_intake(bootstrap.session, duplicate_operation, %{
               source_identity: source_identity,
               replay_identity: replay_identity,
               body: "Investigate duplicate event apply and prove it."
             })

    assert duplicate_intake.normalized_event.outcome == "duplicate"
    assert duplicate_intake.proposed_changes == []

    proposed_changes =
      Enum.map(required_change_types(), fn change_type ->
        insert_change_for_event!(
          bootstrap.session,
          duplicate_operation,
          duplicate_intake.normalized_event,
          change_type
        )
      end)

    {:ok, apply_operation} = Operations.start_operation(bootstrap.session, :proposed_change_apply)
    duplicate_event_id = duplicate_intake.normalized_event.id

    assert {:error,
            {:invalid_proposed_change_set, {:normalized_event_not_accepted, ^duplicate_event_id}}} =
             ProposedChanges.apply_all(bootstrap.session, apply_operation, proposed_changes)

    assert Enum.all?(proposed_changes, &(get_change!(&1).status == "pending"))
  end

  test "apply rejects cross-scope proposed changes before graph creation", %{
    bootstrap: bootstrap,
    intake: intake
  } do
    foreign = submit_scoped_intake!("foreign-proposed-apply")
    foreign_change = hd(foreign.intake.proposed_changes)
    foreign_id = foreign_change.id
    proposed_changes = [foreign_change | tl(intake.proposed_changes)]
    {:ok, apply_operation} = Operations.start_operation(bootstrap.session, :proposed_change_apply)

    assert {:error, {:missing_proposed_change, ^foreign_id}} =
             ProposedChanges.apply_all(bootstrap.session, apply_operation, proposed_changes)

    assert Enum.all?(intake.proposed_changes, &(get_change!(&1).status == "pending"))
    assert get_change!(foreign_change).status == "pending"
  end

  test "apply rejects duplicate or incomplete change sets", %{
    bootstrap: bootstrap,
    intake: intake
  } do
    [first | rest] = intake.proposed_changes
    duplicate_type = first.change_type
    duplicate_changes = [first, first | rest]
    missing_changes = rest
    {:ok, apply_operation} = Operations.start_operation(bootstrap.session, :proposed_change_apply)

    assert {:error, {:invalid_proposed_change_set, {:duplicate_change_type, ^duplicate_type}}} =
             ProposedChanges.apply_all(bootstrap.session, apply_operation, duplicate_changes)

    assert {:error, {:invalid_proposed_change_set, {:missing_change_type, ^duplicate_type}}} =
             ProposedChanges.apply_all(bootstrap.session, apply_operation, missing_changes)

    assert Enum.all?(intake.proposed_changes, &(get_change!(&1).status == "pending"))
  end

  test "apply rejects complete change sets assembled from different intake events", %{
    bootstrap: bootstrap,
    intake: intake
  } do
    second = submit_intake!("mixed-intake")
    {:ok, apply_operation} = Operations.start_operation(bootstrap.session, :proposed_change_apply)

    proposed_changes =
      [
        find_change(intake.proposed_changes, "create_signal"),
        find_change(second.proposed_changes, "create_task"),
        find_change(intake.proposed_changes, "create_review_finding"),
        find_change(second.proposed_changes, "create_verification_check")
      ]

    expected_ids =
      proposed_changes
      |> Enum.map(& &1.normalized_event_id)
      |> Enum.uniq()
      |> Enum.sort()

    assert {:error, {:invalid_proposed_change_set, {:mixed_normalized_event_ids, ^expected_ids}}} =
             ProposedChanges.apply_all(bootstrap.session, apply_operation, proposed_changes)

    assert Enum.all?(proposed_changes, &(get_change!(&1).status == "pending"))
  end

  test "successful apply marks all supplied proposed changes applied", %{
    bootstrap: bootstrap,
    intake: intake,
    intake_operation: intake_operation
  } do
    {:ok, apply_operation} = Operations.start_operation(bootstrap.session, :proposed_change_apply)

    assert {:ok, _applied} =
             ProposedChanges.apply_all(
               bootstrap.session,
               apply_operation,
               intake.proposed_changes
             )

    assert Enum.all?(intake.proposed_changes, fn change ->
             change = get_change!(change)

             change.status == "applied" and not is_nil(change.applied_at) and
               change.operation_id == intake_operation.id and
               Map.get(change, :applied_operation_id) == apply_operation.id
           end)
  end

  test "successful apply replays the original result for the same operation", %{
    bootstrap: bootstrap,
    intake: intake
  } do
    {:ok, apply_operation} = Operations.start_operation(bootstrap.session, :proposed_change_apply)

    assert {:ok, first} =
             ProposedChanges.apply_all(
               bootstrap.session,
               apply_operation,
               intake.proposed_changes
             )

    assert {:ok, replay} =
             ProposedChanges.apply_all(
               bootstrap.session,
               apply_operation,
               intake.proposed_changes
             )

    assert Map.new(first, fn {key, record} -> {key, record.id} end) ==
             Map.new(replay, fn {key, record} -> {key, record.id} end)
  end

  test "successful apply replay ignores unrelated earlier traces for the same operation", %{
    bootstrap: bootstrap,
    intake: intake
  } do
    {:ok, apply_operation} = Operations.start_operation(bootstrap.session, :proposed_change_apply)

    assert {:ok, %{signal: unrelated_signal}} =
             WorkGraph.create_signal(bootstrap.session, apply_operation, %{
               title: "Unrelated signal",
               body: "This trace predates proposal application."
             })

    assert {:ok, %{task: unrelated_task}} =
             WorkGraph.create_task(
               bootstrap.session,
               apply_operation,
               unrelated_signal,
               %{
                 title: "Unrelated task",
                 body: "This task is not part of the applied proposal chain."
               }
             )

    assert {:ok, %{review_finding: unrelated_finding}} =
             WorkGraph.create_review_finding(
               bootstrap.session,
               apply_operation,
               unrelated_task,
               %{
                 title: "Unrelated finding",
                 body: "This finding is not part of the applied proposal chain."
               }
             )

    assert {:ok, %{verification_check: unrelated_check}} =
             WorkGraph.create_verification_check(
               bootstrap.session,
               apply_operation,
               unrelated_finding,
               %{
                 title: "Unrelated check",
                 body: "This check is not part of the applied proposal chain."
               }
             )

    assert {:ok, first} =
             ProposedChanges.apply_all(
               bootstrap.session,
               apply_operation,
               intake.proposed_changes
             )

    assert {:ok, replay} =
             ProposedChanges.apply_all(
               bootstrap.session,
               apply_operation,
               intake.proposed_changes
             )

    refute first.signal.id == unrelated_signal.id
    refute first.task.id == unrelated_task.id
    refute first.review_finding.id == unrelated_finding.id
    refute first.verification_check.id == unrelated_check.id

    assert Map.new(first, fn {key, record} -> {key, record.id} end) ==
             Map.new(replay, fn {key, record} -> {key, record.id} end)
  end

  test "apply command owns normalized event target validation", %{
    bootstrap: bootstrap,
    intake: intake
  } do
    {:ok, other_intake_operation} =
      Operations.start_operation(bootstrap.session, :manual_intake_submit)

    {:ok, other_intake} =
      Integrations.submit_manual_intake(bootstrap.session, other_intake_operation, %{
        source_identity: "manual:domain-owned-target",
        replay_identity: "paste:domain-owned-target-#{System.unique_integer([:positive])}",
        body: "Create another proposal set for target validation."
      })

    {:ok, apply_operation} = Operations.start_operation(bootstrap.session, :proposed_change_apply)
    other_event_id = other_intake.normalized_event.id

    assert {:error, {:invalid_proposed_change_set, {:normalized_event_mismatch, ^other_event_id}}} =
             ProposedChanges.apply_all(bootstrap.session, apply_operation, %{
               normalized_event_id: other_event_id,
               proposed_changes: intake.proposed_changes
             })

    assert Enum.all?(intake.proposed_changes, &(get_change!(&1).status == "pending"))
  end

  test "apply ignores unmodeled payload keys instead of atomizing them", %{
    bootstrap: bootstrap,
    intake: intake
  } do
    [first | rest] = intake.proposed_changes

    updated =
      update_payload!(first, bootstrap.session, %{
        "title" => "Signal with imported metadata",
        "body" => "Imported metadata should not become atoms.",
        "__unmodeled_import_key__" => "ignored"
      })

    {:ok, apply_operation} = Operations.start_operation(bootstrap.session, :proposed_change_apply)

    assert {:ok, _applied} =
             ProposedChanges.apply_all(bootstrap.session, apply_operation, [updated | rest])
  end

  test "applied proposed changes cannot have payloads mutated", %{
    bootstrap: bootstrap,
    intake: intake
  } do
    {:ok, apply_operation} = Operations.start_operation(bootstrap.session, :proposed_change_apply)

    assert {:ok, _applied} =
             ProposedChanges.apply_all(
               bootstrap.session,
               apply_operation,
               intake.proposed_changes
             )

    applied = intake.proposed_changes |> hd() |> get_change!()

    assert {:error, error} =
             applied
             |> Ash.Changeset.for_update(:set_payload, %{
               payload: %{"title" => "Mutated", "body" => "Should be rejected"}
             })
             |> Ash.update(actor: bootstrap.session)

    assert Exception.message(error) =~ "status"
  end

  test "stale pending proposed changes cannot mutate payload after apply", %{
    bootstrap: bootstrap,
    intake: intake
  } do
    stale_pending = hd(intake.proposed_changes)
    {:ok, apply_operation} = Operations.start_operation(bootstrap.session, :proposed_change_apply)

    assert {:ok, _applied} =
             ProposedChanges.apply_all(
               bootstrap.session,
               apply_operation,
               intake.proposed_changes
             )

    original_payload = get_change!(stale_pending).payload

    assert {:error, error} =
             stale_pending
             |> Ash.Changeset.for_update(:set_payload, %{
               payload: %{"title" => "Mutated", "body" => "Should be rejected"}
             })
             |> Ash.update(actor: bootstrap.session)

    assert Exception.message(error) =~ "status"
    assert get_change!(stale_pending).payload == original_payload
  end

  test "direct Ash update cannot mark proposed changes applied", %{
    bootstrap: bootstrap,
    intake: intake
  } do
    change = hd(intake.proposed_changes)

    assert {:error, error} =
             change
             |> Ash.Changeset.for_update(:mark_applied, %{applied_at: DateTime.utc_now()},
               actor: bootstrap.session
             )
             |> Ash.update()

    assert Exception.message(error) =~ ~r/forbidden/i
    assert get_change!(change).status == "pending"
  end

  test "apply rejects stale non-pending proposed changes", %{
    bootstrap: bootstrap,
    intake: intake
  } do
    {:ok, apply_operation} = Operations.start_operation(bootstrap.session, :proposed_change_apply)

    assert {:ok, _applied} =
             ProposedChanges.apply_all(
               bootstrap.session,
               apply_operation,
               intake.proposed_changes
             )

    {:ok, reapply_operation} =
      Operations.start_operation(bootstrap.session, :proposed_change_apply)

    first_id = intake.proposed_changes |> hd() |> Map.fetch!(:id)

    assert {:error, {:invalid_proposed_change_status, ^first_id}} =
             ProposedChanges.apply_all(
               bootstrap.session,
               reapply_operation,
               intake.proposed_changes
             )
  end

  defp submit_intake!(suffix) do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, intake_operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)

    {:ok, intake} =
      Integrations.submit_manual_intake(bootstrap.session, intake_operation, %{
        source_identity: "manual:#{suffix}",
        replay_identity: "paste:#{suffix}-#{System.unique_integer([:positive])}",
        body: "Investigate #{suffix} and prove it."
      })

    intake
  end

  defp submit_scoped_intake!(suffix) do
    {:ok, bootstrap} =
      Foundation.bootstrap_local_owner(
        organization_name: "Office Graph #{suffix}",
        organization_slug: "office-graph-#{suffix}",
        workspace_name: "Workspace #{suffix}",
        workspace_slug: "workspace-#{suffix}",
        initiative_name: "Walking Skeleton #{suffix}",
        initiative_slug: "walking-skeleton-#{suffix}",
        owner_email: "owner-#{suffix}@office-graph.local"
      )

    {:ok, intake_operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)

    {:ok, intake} =
      Integrations.submit_manual_intake(bootstrap.session, intake_operation, %{
        source_identity: "manual:#{suffix}",
        replay_identity: "paste:#{suffix}",
        body: "Investigate scoped #{suffix} change and prove it."
      })

    %{bootstrap: bootstrap, intake: intake}
  end

  defp update_payload!(change, session_context, payload) do
    change
    |> Ash.Changeset.for_update(:set_payload, %{payload: payload})
    |> Ash.update!(actor: session_context)
  end

  defp create_untraced_change!(session_context, operation, change_type) do
    Ash.create!(
      ProposedGraphChange,
      %{
        organization_id: session_context.organization_id,
        workspace_id: session_context.workspace_id,
        operation_id: operation.id,
        change_type: change_type,
        payload: %{
          "title" => "Untraced #{change_type}",
          "body" => "Untraced #{change_type} body"
        }
      },
      actor: session_context,
      action: :create
    )
  end

  defp insert_change_for_event!(session_context, operation, normalized_event, change_type) do
    id = Ecto.UUID.generate()
    now = DateTime.utc_now()

    Repo.query!(
      """
      INSERT INTO proposed_graph_changes (
        id,
        organization_id,
        workspace_id,
        operation_id,
        normalized_event_id,
        status,
        change_type,
        payload,
        validation_errors,
        inserted_at,
        updated_at
      ) VALUES (
        $1::uuid,
        $2::uuid,
        $3::uuid,
        $4::uuid,
        $5::uuid,
        'pending',
        $6,
        $7::jsonb,
        ARRAY[]::text[],
        $8,
        $8
      )
      """,
      [
        db_uuid(id),
        db_uuid(session_context.organization_id),
        db_uuid(session_context.workspace_id),
        db_uuid(operation.id),
        db_uuid(normalized_event.id),
        change_type,
        %{
          "title" => "Duplicate event #{change_type}",
          "body" => "Duplicate event #{change_type} body"
        },
        now
      ]
    )

    Ash.get!(ProposedGraphChange, id, authorize?: false)
  end

  defp db_uuid(uuid), do: Ecto.UUID.dump!(uuid)

  defp create_accepted_event_without_changes!(session_context, operation, suffix) do
    source_identity = "manual:#{suffix}-#{System.unique_integer([:positive])}"
    replay_identity = "paste:#{suffix}"
    body = "Investigate #{suffix} and prove it."

    source =
      Ash.create!(
        ExternalSource,
        %{
          key: source_identity,
          name: "Manual Intake",
          kind: "manual"
        },
        action: :create,
        authorize?: false
      )

    raw_archive =
      Ash.create!(
        RawArchive,
        %{
          organization_id: session_context.organization_id,
          workspace_id: session_context.workspace_id,
          source_id: source.id,
          operation_id: operation.id,
          content_hash: content_hash(body),
          body: body,
          metadata: %{}
        },
        action: :create,
        authorize?: false
      )

    Ash.create!(
      NormalizedIntakeEvent,
      %{
        organization_id: session_context.organization_id,
        workspace_id: session_context.workspace_id,
        raw_archive_id: raw_archive.id,
        operation_id: operation.id,
        source_identity: source_identity,
        replay_identity: replay_identity,
        outcome: "accepted"
      },
      action: :create,
      authorize?: false
    )
  end

  defp content_hash(body) do
    :crypto.hash(:sha256, body)
    |> Base.encode16(case: :lower)
  end

  defp required_change_types do
    [
      "create_signal",
      "create_task",
      "create_review_finding",
      "create_verification_check"
    ]
  end

  defp create_session_without_roles!(bootstrap) do
    principal =
      Ash.create!(
        Principal,
        %{
          id: Ecto.UUID.generate(),
          email:
            "proposed-change-denied-#{System.unique_integer([:positive])}@office-graph.local",
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
          purpose: "proposed_change_denied"
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

  defp create_session_with_capabilities!(bootstrap, capability_keys) do
    suffix = System.unique_integer([:positive])

    principal =
      Ash.create!(
        Principal,
        %{
          id: Ecto.UUID.generate(),
          email: "proposed-change-apply-only-#{suffix}@office-graph.local",
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
          purpose: "proposed_change_apply_only_#{suffix}"
        },
        action: :create,
        authorize?: false
      )

    role =
      Ash.create!(
        Role,
        %{
          id: Ecto.UUID.generate(),
          organization_id: bootstrap.organization.id,
          key: "proposed_change_apply_only_#{suffix}",
          name: "Proposed Change Apply Only #{suffix}"
        },
        action: :create,
        authorize?: false
      )

    Enum.each(capability_keys, fn capability_key ->
      capability = Ash.get!(Capability, %{key: capability_key}, authorize?: false)

      Ash.create!(
        RoleCapability,
        %{id: Ecto.UUID.generate(), role_id: role.id, capability_id: capability.id},
        action: :create,
        authorize?: false
      )
    end)

    Ash.create!(
      RoleAssignment,
      %{
        id: Ecto.UUID.generate(),
        principal_id: principal.id,
        role_id: role.id,
        organization_id: bootstrap.organization.id,
        workspace_id: bootstrap.workspace.id
      },
      action: :create,
      authorize?: false
    )

    %SessionContext{
      principal_id: principal.id,
      session_id: session.id,
      organization_id: bootstrap.organization.id,
      workspace_id: bootstrap.workspace.id,
      capabilities: MapSet.new(capability_keys)
    }
  end

  defp get_change!(change) do
    Ash.get!(ProposedGraphChange, change.id, authorize?: false)
  end

  defp find_change(changes, change_type) do
    Enum.find(changes, &(&1.change_type == change_type))
  end
end
