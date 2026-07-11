defmodule OfficeGraph.Integrations.ManualIntakeReplayTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{Foundation, Integrations, Operations}

  test "legacy operations retain duplicate and changed-content semantics" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    attrs = %{
      source_identity: "manual:legacy-operation-replay",
      replay_identity: "paste:legacy-operation-replay",
      body: "Legacy replay body"
    }

    {:ok, operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)

    assert {:ok, first} = Integrations.submit_manual_intake(bootstrap.session, operation, attrs)
    assert first.duplicate? == false

    assert {:ok, duplicate} =
             Integrations.submit_manual_intake(bootstrap.session, operation, attrs)

    assert duplicate.duplicate? == true
    refute duplicate.normalized_event.id == first.normalized_event.id

    assert {:error, {:manual_intake_replay_conflict, accepted_id}} =
             Integrations.submit_manual_intake(
               bootstrap.session,
               operation,
               %{attrs | body: "Changed legacy replay body"}
             )

    assert accepted_id == first.normalized_event.id
  end
end
