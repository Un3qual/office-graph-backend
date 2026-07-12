defmodule OfficeGraph.DurableDelivery.ProjectionInvalidationTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{DurableDelivery, Foundation, Operations, Repo}
  alias OfficeGraph.DurableDelivery.{DispatchEventWorker, DomainEvent}

  defmodule RejectingBroadcaster do
    def broadcast(invalidation) do
      {:ok, event} = Ash.get(DomainEvent, invalidation.event_id)
      send(self(), {:delivery_state_during_broadcast, event.delivery_state})
      {:error, :unavailable}
    end
  end

  defmodule RaisingBroadcaster do
    def broadcast(_invalidation), do: raise("pubsub unavailable")
  end

  defmodule ExitingBroadcaster do
    def broadcast(_invalidation), do: exit(:pubsub_unavailable)
  end

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

  test "subscription stops forwarding when its session is revoked" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    assert {:ok, operation} =
             Operations.start_operation(bootstrap.session, :manual_intake_submit)

    assert {:ok, event} =
             DurableDelivery.record_and_enqueue(bootstrap.session, operation, %{
               event_key: "test:revoked-invalidation",
               event_kind: "manual_intake.accepted",
               subject_kind: "normalized_intake_event",
               subject_id: Ecto.UUID.generate()
             })

    assert :ok =
             DurableDelivery.subscribe(
               bootstrap.session,
               bootstrap.organization.id,
               bootstrap.workspace.id
             )

    revoke_session!(bootstrap.session.session_id)

    [job] = jobs_for_event(event.id)
    assert :ok = DispatchEventWorker.perform(job)

    refute_receive {:projection_invalidated, _invalidation}
  end

  test "repeat subscription refreshes the mediator session" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    renewed_session =
      Ash.create!(
        OfficeGraph.Identity.Session,
        %{
          id: Ecto.UUID.generate(),
          principal_id: bootstrap.principal.id,
          organization_id: bootstrap.organization.id,
          workspace_id: bootstrap.workspace.id,
          purpose: "renewed_subscription"
        },
        action: :create,
        authorize?: false
      )

    renewed_context = %{bootstrap.session | session_id: renewed_session.id}

    assert :ok =
             DurableDelivery.subscribe(
               bootstrap.session,
               bootstrap.organization.id,
               bootstrap.workspace.id
             )

    revoke_session!(bootstrap.session.session_id)

    assert :ok =
             DurableDelivery.subscribe(
               renewed_context,
               bootstrap.organization.id,
               bootstrap.workspace.id
             )

    {:ok, operation} = Operations.start_operation(renewed_context, :manual_intake_submit)

    assert {:ok, event} =
             DurableDelivery.record_and_enqueue(renewed_context, operation, %{
               event_key: "test:renewed-subscription",
               event_kind: "manual_intake.accepted",
               subject_kind: "normalized_intake_event",
               subject_id: Ecto.UUID.generate()
             })

    [job] = jobs_for_event(event.id)
    assert :ok = DispatchEventWorker.perform(job)
    assert_receive {:projection_invalidated, %{event_id: event_id}}
    assert event_id == event.id
  end

  test "dispatch keeps an event pending until its invalidation is accepted" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)

    assert {:ok, event} =
             DurableDelivery.record_and_enqueue(bootstrap.session, operation, %{
               event_key: "test:rejected-invalidation",
               event_kind: "manual_intake.accepted",
               subject_kind: "normalized_intake_event",
               subject_id: Ecto.UUID.generate()
             })

    result = DurableDelivery.dispatch(event.id, RejectingBroadcaster)

    assert {:error, {:retryable, :projection_broadcast_failed}} = result
    assert_received {:delivery_state_during_broadcast, "pending"}

    assert {:ok, %{delivery_state: "pending", dispatched_at: nil}} =
             Ash.get(DomainEvent, event.id)
  end

  test "dispatch rejects an invalid event id without entering the retry path" do
    assert {:error, {:terminal, :invalid_event_id}} = DurableDelivery.dispatch(:not_an_event_id)
  end

  for {broadcaster, failure_kind} <- [
        {RaisingBroadcaster, "exceptions"},
        {ExitingBroadcaster, "exits"}
      ] do
    test "dispatch classifies broadcaster #{failure_kind} and leaves the event pending" do
      {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
      {:ok, operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)

      assert {:ok, event} =
               DurableDelivery.record_and_enqueue(bootstrap.session, operation, %{
                 event_key: "test:crashed-invalidation:#{unquote(failure_kind)}",
                 event_kind: "manual_intake.accepted",
                 subject_kind: "normalized_intake_event",
                 subject_id: Ecto.UUID.generate()
               })

      assert {:error, {:retryable, :event_dispatch_crashed}} =
               DurableDelivery.dispatch(event.id, unquote(broadcaster))

      assert {:ok, %{delivery_state: "pending", failure_code: nil}} =
               Ash.get(DomainEvent, event.id)
    end
  end

  test "failure marking preserves an already dispatched event" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)

    assert {:ok, event} =
             DurableDelivery.record_and_enqueue(bootstrap.session, operation, %{
               event_key: "test:dispatched-wins",
               event_kind: "manual_intake.accepted",
               subject_kind: "normalized_intake_event",
               subject_id: Ecto.UUID.generate()
             })

    assert :ok = DurableDelivery.dispatch(event.id)
    assert :ok = DurableDelivery.mark_failed(event.id, "attempts_exhausted")

    assert {:ok, %{delivery_state: "dispatched", failure_code: nil, failed_at: nil}} =
             Ash.get(DomainEvent, event.id)
  end

  test "the dispatch worker rejects a mismatched job scope without changing the event" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)

    assert {:ok, event} =
             DurableDelivery.record_and_enqueue(bootstrap.session, operation, %{
               event_key: "test:mismatched-job-scope",
               event_kind: "manual_intake.accepted",
               subject_kind: "normalized_intake_event",
               subject_id: Ecto.UUID.generate()
             })

    [job] = jobs_for_event(event.id)
    mismatched_job = put_in(job.args["workspace_id"], Ecto.UUID.generate())

    assert {:cancel, "event_scope_mismatch"} = DispatchEventWorker.perform(mismatched_job)

    assert {:ok, %{delivery_state: "pending", failure_code: nil}} =
             Ash.get(DomainEvent, event.id)
  end

  test "the dispatch worker persists terminal state before cancelling" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)

    assert {:ok, event} =
             DurableDelivery.record_and_enqueue(bootstrap.session, operation, %{
               event_key: "test:terminal-transition-retry",
               event_kind: "manual_intake.accepted",
               subject_kind: "normalized_intake_event",
               subject_id: Ecto.UUID.generate()
             })

    Repo.query!("""
    ALTER TABLE domain_events
    ADD CONSTRAINT test_terminal_transition_retry
    CHECK (delivery_state <> 'dispatched' AND failure_code <> 'attempts_exhausted')
    """)

    [job] = jobs_for_event(event.id)
    exhausted_job = %{job | attempt: job.max_attempts}

    assert {:snooze, 5} = DispatchEventWorker.perform(exhausted_job)

    assert %{meta: %{"terminal_failure_code" => "attempts_exhausted"}} =
             Repo.get!(Oban.Job, job.id)

    assert {:ok, %{delivery_state: "pending", failure_code: nil}} =
             Ash.get(DomainEvent, event.id)

    Repo.query!("ALTER TABLE domain_events DROP CONSTRAINT test_terminal_transition_retry")

    terminalization_job = Repo.get!(Oban.Job, job.id)
    assert {:cancel, "attempts_exhausted"} = DispatchEventWorker.perform(terminalization_job)

    assert {:ok, %{delivery_state: "failed", failure_code: "attempts_exhausted"}} =
             Ash.get(DomainEvent, event.id)
  end

  defp jobs_for_event(event_id) do
    Oban.Job
    |> where([job], fragment("?->>'event_id'", job.args) == ^event_id)
    |> Repo.all()
  end

  defp revoke_session!(session_id) do
    now = DateTime.utc_now()

    Repo.query!(
      "UPDATE sessions SET revoked_at = $1, updated_at = $1 WHERE id = $2",
      [now, Ecto.UUID.dump!(session_id)]
    )
  end
end
