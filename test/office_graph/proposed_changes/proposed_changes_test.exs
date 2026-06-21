defmodule OfficeGraph.ProposedChangesTest do
  use OfficeGraph.DataCase, async: false

  alias Ecto.Changeset
  alias OfficeGraph.Foundation
  alias OfficeGraph.Identity.SessionContext
  alias OfficeGraph.Integrations
  alias OfficeGraph.Operations
  alias OfficeGraph.ProposedChanges
  alias OfficeGraph.Repo

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
      |> Changeset.change(payload: %{"body" => "missing title"})
      |> Repo.update!()

    proposed_changes = [invalid | tl(intake.proposed_changes)]
    {:ok, apply_operation} = Operations.start_operation(bootstrap.session, :proposed_change_apply)
    invalid_id = invalid.id

    assert {:error, {:invalid_proposed_change, ^invalid_id}} =
             ProposedChanges.apply_all(bootstrap.session, apply_operation, proposed_changes)

    assert Repo.get!(invalid.__struct__, invalid.id).status == "rejected"
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
             &(Repo.get!(&1.__struct__, &1.id).status == "pending")
           )
  end
end
