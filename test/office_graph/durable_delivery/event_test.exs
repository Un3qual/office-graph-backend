defmodule OfficeGraph.DurableDelivery.EventTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{DurableDelivery, Foundation, Operations, Repo}
  alias OfficeGraph.DurableDelivery.DomainEvent

  test "records a typed event and one unique dispatch job" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)
    subject_id = Ecto.UUID.generate()

    assert {:ok, event} =
             DurableDelivery.record_and_enqueue(bootstrap.session, operation, %{
               event_key: "test:#{subject_id}:accepted",
               event_kind: "manual_intake.accepted",
               subject_kind: "normalized_intake_event",
               subject_id: subject_id,
               subject_version: 2
             })

    assert event.organization_id == bootstrap.organization.id
    assert event.workspace_id == bootstrap.workspace.id
    assert event.operation_id == operation.id
    assert event.subject_version == 2
    assert event.delivery_state == "pending"

    assert [%Oban.Job{} = job] = jobs_for_event(event.id)
    assert job.queue == "delivery"

    assert job.args == %{
             "event_id" => event.id,
             "organization_id" => bootstrap.organization.id,
             "workspace_id" => bootstrap.workspace.id
           }
  end

  test "rejects invalid kinds and mismatched operation scope" do
    {:ok, first} = Foundation.bootstrap_local_owner([])
    {:ok, operation} = Operations.start_operation(first.session, :manual_intake_submit)
    subject_id = Ecto.UUID.generate()
    wrong_scope = %{first.session | workspace_id: Ecto.UUID.generate()}

    assert {:error, {:invalid_event_kind, "Manual Intake Accepted"}} =
             DurableDelivery.record_and_enqueue(first.session, operation, %{
               event_key: "test:invalid-kind",
               event_kind: "Manual Intake Accepted",
               subject_kind: "normalized_intake_event",
               subject_id: subject_id
             })

    assert {:error, :forbidden} =
             DurableDelivery.record_and_enqueue(wrong_scope, operation, %{
               event_key: "test:wrong-scope",
               event_kind: "manual_intake.accepted",
               subject_kind: "normalized_intake_event",
               subject_id: subject_id
             })

    assert Repo.aggregate(DomainEvent, :count) == 0
    assert Repo.aggregate(Oban.Job, :count) == 0
  end

  test "stable replay returns one event and one job" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)

    attrs = %{
      event_key: "test:stable-replay",
      event_kind: "manual_intake.accepted",
      subject_kind: "normalized_intake_event",
      subject_id: Ecto.UUID.generate()
    }

    assert {:ok, first} = DurableDelivery.record_and_enqueue(bootstrap.session, operation, attrs)
    assert {:ok, replay} = DurableDelivery.record_and_enqueue(bootstrap.session, operation, attrs)

    assert replay.id == first.id
    assert Repo.aggregate(DomainEvent, :count) == 1
    assert length(jobs_for_event(first.id)) == 1
  end

  test "stable replay does not recreate a pruned dispatch job" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)

    attrs = %{
      event_key: "test:pruned-replay",
      event_kind: "manual_intake.accepted",
      subject_kind: "normalized_intake_event",
      subject_id: Ecto.UUID.generate()
    }

    assert {:ok, first} = DurableDelivery.record_and_enqueue(bootstrap.session, operation, attrs)
    assert {1, _jobs} = Repo.delete_all(jobs_query(first.id))

    assert {:ok, replay} = DurableDelivery.record_and_enqueue(bootstrap.session, operation, attrs)
    assert replay.id == first.id
    assert jobs_for_event(first.id) == []
  end

  test "an outer transaction rollback removes the event and its job" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)
    event_key = "test:rollback"

    assert {:error, :forced_rollback} =
             Repo.transaction(fn ->
               assert {:ok, _event} =
                        DurableDelivery.record_and_enqueue(bootstrap.session, operation, %{
                          event_key: event_key,
                          event_kind: "manual_intake.accepted",
                          subject_kind: "normalized_intake_event",
                          subject_id: Ecto.UUID.generate()
                        })

               Repo.rollback(:forced_rollback)
             end)

    assert Repo.aggregate(DomainEvent, :count) == 0
    assert Repo.aggregate(Oban.Job, :count) == 0
  end

  defp jobs_for_event(event_id) do
    event_id |> jobs_query() |> Repo.all()
  end

  defp jobs_query(event_id) do
    where(Oban.Job, [job], fragment("?->>'event_id'", job.args) == ^event_id)
  end
end
