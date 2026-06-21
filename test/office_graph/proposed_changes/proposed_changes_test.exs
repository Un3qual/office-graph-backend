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
      |> update_payload!(%{"body" => "missing title"})

    proposed_changes = [invalid | tl(intake.proposed_changes)]
    {:ok, apply_operation} = Operations.start_operation(bootstrap.session, :proposed_change_apply)
    invalid_id = invalid.id

    assert {:error, {:invalid_proposed_change, ^invalid_id}} =
             ProposedChanges.apply_all(bootstrap.session, apply_operation, proposed_changes)

    assert get_change!(invalid).status == "rejected"
  end

  test "get_many! preserves caller order and raises for missing ids", %{intake: intake} do
    ids =
      intake.proposed_changes
      |> Enum.map(& &1.id)
      |> Enum.reverse()

    assert ids ==
             ids
             |> ProposedChanges.get_many!()
             |> Enum.map(& &1.id)

    assert_raise KeyError, fn ->
      ProposedChanges.get_many!([Ecto.UUID.generate()])
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

  defp update_payload!(change, payload) do
    change
    |> Ash.Changeset.for_update(:set_payload, %{payload: payload})
    |> Ash.update!(authorize?: false)
  end

  defp get_change!(change) do
    Ash.get!(ProposedGraphChange, change.id, authorize?: false)
  end
end
