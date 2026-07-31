defmodule OfficeGraph.DurableDelivery.EventTest do
  use OfficeGraph.DataCase, async: false
  use Oban.Testing, repo: OfficeGraph.Repo

  alias OfficeGraph.{DurableDelivery, Foundation, Operations}
  alias OfficeGraph.DurableDelivery.{DispatchEventWorker, DomainEvent}

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

    assert Ash.count!(DomainEvent, authorize?: false) == 0
    assert all_enqueued() == []
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
    assert Ash.count!(DomainEvent, authorize?: false) == 1
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
    assert [job] = jobs_for_event(first.id)
    assert :ok = Oban.delete_job(job)

    assert {:ok, replay} = DurableDelivery.record_and_enqueue(bootstrap.session, operation, attrs)
    assert replay.id == first.id
    assert jobs_for_event(first.id) == []
  end

  test "a conflicting replay leaves the original event and job unchanged" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)

    attrs = %{
      event_key: "test:nested-delivery-failure",
      event_kind: "manual_intake.accepted",
      subject_kind: "normalized_intake_event",
      subject_id: Ecto.UUID.generate()
    }

    assert {:ok, event} = DurableDelivery.record_and_enqueue(bootstrap.session, operation, attrs)

    assert {:error, :event_identity_conflict} =
             DurableDelivery.record_and_enqueue(
               bootstrap.session,
               operation,
               %{attrs | subject_id: Ecto.UUID.generate()}
             )

    assert Ash.count!(DomainEvent, authorize?: false) == 1
    assert length(jobs_for_event(event.id)) == 1
  end

  defp jobs_for_event(event_id) do
    all_enqueued(worker: DispatchEventWorker, args: %{event_id: event_id})
  end
end
