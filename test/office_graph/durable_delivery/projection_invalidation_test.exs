defmodule OfficeGraph.DurableDelivery.ProjectionInvalidationTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{DurableDelivery, Foundation, Operations, Repo}
  alias OfficeGraph.DurableDelivery.DispatchEventWorker

  test "authorized same-scope subscribers receive one bounded invalidation" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)
    subject_id = Ecto.UUID.generate()

    assert :ok =
             DurableDelivery.subscribe(
               bootstrap.session,
               bootstrap.organization.id,
               bootstrap.workspace.id
             )

    assert {:ok, event} =
             DurableDelivery.record_and_enqueue(bootstrap.session, operation, %{
               event_key: "test:invalidation",
               event_kind: "manual_intake.accepted",
               subject_kind: "normalized_intake_event",
               subject_id: subject_id
             })

    [job] = jobs_for_event(event.id)
    assert :ok = DispatchEventWorker.perform(job)

    assert_receive {:projection_invalidated, invalidation}
    assert invalidation.event_id == event.id
    assert invalidation.subject_id == subject_id

    assert Map.keys(Map.from_struct(invalidation)) |> Enum.sort() ==
             ~w(event_id event_kind operation_id organization_id subject_id subject_kind subject_version workspace_id)a

    assert :ok = DispatchEventWorker.perform(job)
    refute_receive {:projection_invalidated, _invalidation}
  end

  test "subscription rejects invalid and cross-scope sessions" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    assert {:error, :forbidden} =
             DurableDelivery.subscribe(
               bootstrap.session,
               bootstrap.organization.id,
               Ecto.UUID.generate()
             )

    revoked = %{bootstrap.session | session_id: Ecto.UUID.generate()}

    assert {:error, :forbidden} =
             DurableDelivery.subscribe(
               revoked,
               bootstrap.organization.id,
               bootstrap.workspace.id
             )
  end

  defp jobs_for_event(event_id) do
    Oban.Job
    |> where([job], fragment("?->>'event_id'", job.args) == ^event_id)
    |> Repo.all()
  end
end
