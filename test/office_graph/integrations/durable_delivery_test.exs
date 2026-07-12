defmodule OfficeGraph.Integrations.DurableDeliveryTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{Foundation, Integrations, Operations, Repo}
  alias OfficeGraph.DurableDelivery.DomainEvent

  test "first acceptance creates one durable event and command replay creates none" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    attrs = %{
      source_identity: "manual:durable-delivery",
      replay_identity: "paste:durable-delivery",
      body: "Durably deliver this intake"
    }

    {:ok, operation} =
      Operations.start_command(
        bootstrap.session,
        :manual_intake_submit,
        "durable-delivery",
        attrs
      )

    assert {:ok, first} = Integrations.submit_manual_intake(bootstrap.session, operation, attrs)
    assert {:ok, replay} = Integrations.submit_manual_intake(bootstrap.session, operation, attrs)
    assert replay.normalized_event.id == first.normalized_event.id

    assert [event] = domain_events()
    assert event.event_key == "manual-intake:#{first.normalized_event.id}:accepted"
    assert event.event_kind == "manual_intake.accepted"
    assert event.subject_kind == "normalized_intake_event"
    assert event.subject_id == first.normalized_event.id
    assert event.operation_id == operation.id
    assert length(jobs_for_event(event.id)) == 1
  end

  test "duplicate intake records don't create a second event or job" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    attrs = %{
      source_identity: "manual:durable-duplicate",
      replay_identity: "paste:durable-duplicate",
      body: "Same accepted intake"
    }

    {:ok, first_operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)

    assert {:ok, first} =
             Integrations.submit_manual_intake(bootstrap.session, first_operation, attrs)

    {:ok, duplicate_operation} =
      Operations.start_operation(bootstrap.session, :manual_intake_submit)

    assert {:ok, duplicate} =
             Integrations.submit_manual_intake(bootstrap.session, duplicate_operation, attrs)

    assert first.duplicate? == false
    assert duplicate.duplicate? == true
    assert length(domain_events()) == 1
    assert Repo.aggregate(Oban.Job, :count) == 1
  end

  defp domain_events do
    DomainEvent
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!()
  end

  defp jobs_for_event(event_id) do
    Oban.Job
    |> where([job], fragment("?->>'event_id'", job.args) == ^event_id)
    |> Repo.all()
  end
end
