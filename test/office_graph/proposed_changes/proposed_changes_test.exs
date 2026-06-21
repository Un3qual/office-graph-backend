defmodule OfficeGraph.ProposedChangesTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.Foundation
  alias OfficeGraph.Identity.SessionContext
  alias OfficeGraph.Integrations
  alias OfficeGraph.Operations
  alias OfficeGraph.ProposedChanges
  alias OfficeGraph.ProposedChanges.ProposedGraphChange

  setup do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, intake_operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)

    {:ok, intake} =
      Integrations.submit_manual_intake(bootstrap.session, intake_operation, %{
        source_identity: "manual:web",
        replay_identity: "paste:proposed-change-test",
        body: "Investigate flaky deploy and prove it."
      })

    %{bootstrap: bootstrap, intake: intake}
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
      |> Ash.Changeset.for_create(:create, %{
        organization_id: bootstrap.session.organization_id,
        workspace_id: bootstrap.session.workspace_id,
        operation_id: intake_operation.id,
        status: "applied",
        change_type: "create_signal",
        payload: %{"title" => "Spoofed lifecycle", "body" => "This must stay pending."},
        validation_errors: ["spoofed"],
        applied_at: DateTime.utc_now()
      })
      |> Ash.create!(actor: bootstrap.session)
    end
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

  test "successful apply marks all supplied proposed changes applied", %{
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

    assert Enum.all?(intake.proposed_changes, fn change ->
             change = get_change!(change)
             change.status == "applied" and not is_nil(change.applied_at)
           end)
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

  defp get_change!(change) do
    Ash.get!(ProposedGraphChange, change.id, authorize?: false)
  end
end
