defmodule OfficeGraph.DurableDelivery.TerminalJobsTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{DurableDelivery, Foundation, Operations, Repo}

  test "returns bounded safe terminal summaries only for the authorized scope" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)

    assert {:ok, event} =
             DurableDelivery.record_and_enqueue(bootstrap.session, operation, %{
               event_key: "test:terminal-summary",
               event_kind: "manual_intake.accepted",
               subject_kind: "normalized_intake_event",
               subject_id: Ecto.UUID.generate()
             })

    [job] = jobs_for_event(event.id)
    :ok = DurableDelivery.mark_failed(event.id, "invalid_payload")

    job =
      job
      |> Ecto.Changeset.change(%{
        state: "cancelled",
        attempt: 2,
        attempted_at: DateTime.utc_now(),
        cancelled_at: DateTime.utc_now(),
        errors: [%{"attempt" => 2, "error" => "secret stack trace"}]
      })
      |> Repo.update!()

    insert_other_scope_terminal_job()

    assert {:ok, [summary]} = DurableDelivery.list_terminal_jobs(bootstrap.session, limit: 1)
    assert summary.id == job.id
    assert summary.failure_code == "invalid_payload"
    assert summary.state == "cancelled"
    assert summary.attempt == 2
    refute Map.has_key?(Map.from_struct(summary), :args)
    refute Map.has_key?(Map.from_struct(summary), :errors)
    refute Map.has_key?(Map.from_struct(summary), :stacktrace)
  end

  test "fails closed for an invalid session" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    unauthorized = %{bootstrap.session | session_id: Ecto.UUID.generate()}

    assert {:error, :forbidden} = DurableDelivery.list_terminal_jobs(unauthorized)
  end

  test "rechecks live grants before returning terminal history" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    Repo.query!("DELETE FROM role_assignments WHERE id = $1", [
      Ecto.UUID.dump!(bootstrap.role_assignment.id)
    ])

    assert {:error, :forbidden} = DurableDelivery.list_terminal_jobs(bootstrap.session)
  end

  test "uses safe job failure metadata when no event state exists" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    job =
      insert_terminal_job(bootstrap, Ecto.UUID.generate(), "event_not_found")

    assert {:ok, summaries} = DurableDelivery.list_terminal_jobs(bootstrap.session)
    assert %{failure_code: "event_not_found"} = Enum.find(summaries, &(&1.id == job.id))
  end

  test "includes organization-scoped terminal jobs for authorized operators" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    job =
      insert_terminal_job(
        bootstrap,
        Ecto.UUID.generate(),
        "organization_delivery_failed",
        nil
      )

    assert {:ok, summaries} = DurableDelivery.list_terminal_jobs(bootstrap.session)

    assert %{failure_code: "organization_delivery_failed"} =
             Enum.find(summaries, &(&1.id == job.id))
  end

  test "does not trust failure state from an event outside the authorized scope" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    {:ok, other_scope} =
      Foundation.bootstrap_local_owner(
        organization_name: "Other Terminal Organization",
        organization_slug: "other-terminal-organization",
        workspace_name: "Other Terminal Workspace",
        workspace_slug: "other-terminal-workspace",
        initiative_name: "Other Terminal Initiative",
        initiative_slug: "other-terminal-initiative",
        owner_email: "other-terminal-owner@example.test",
        owner_name: "Other Terminal Owner"
      )

    {:ok, operation} =
      Operations.start_operation(other_scope.session, :manual_intake_submit)

    assert {:ok, event} =
             DurableDelivery.record_and_enqueue(other_scope.session, operation, %{
               event_key: "test:cross-scope-terminal-summary",
               event_kind: "manual_intake.accepted",
               subject_kind: "normalized_intake_event",
               subject_id: Ecto.UUID.generate()
             })

    :ok = DurableDelivery.mark_failed(event.id, "other_scope_secret")
    job = insert_terminal_job(bootstrap, event.id, "event_scope_mismatch")

    assert {:ok, summaries} = DurableDelivery.list_terminal_jobs(bootstrap.session)

    assert %{failure_code: "event_scope_mismatch"} =
             Enum.find(summaries, &(&1.id == job.id))
  end

  test "ignores malformed event ids when assembling terminal summaries" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    job = insert_terminal_job(bootstrap, "not-a-uuid", "attempts_exhausted")

    assert {:ok, summaries} = DurableDelivery.list_terminal_jobs(bootstrap.session)
    assert %{failure_code: "attempts_exhausted"} = Enum.find(summaries, &(&1.id == job.id))
  end

  defp insert_other_scope_terminal_job do
    {:ok, job} =
      %{
        "event_id" => Ecto.UUID.generate(),
        "organization_id" => Ecto.UUID.generate(),
        "workspace_id" => Ecto.UUID.generate()
      }
      |> OfficeGraph.DurableDelivery.DispatchEventWorker.new()
      |> Oban.insert()

    job
    |> Ecto.Changeset.change(state: "cancelled", cancelled_at: DateTime.utc_now())
    |> Repo.update!()
  end

  defp insert_terminal_job(bootstrap, event_id, failure_code, workspace_id \\ :session_workspace) do
    workspace_id =
      if workspace_id == :session_workspace, do: bootstrap.workspace.id, else: workspace_id

    {:ok, job} =
      %{
        "event_id" => event_id,
        "organization_id" => bootstrap.organization.id,
        "workspace_id" => workspace_id
      }
      |> OfficeGraph.DurableDelivery.DispatchEventWorker.new()
      |> Oban.insert()

    job
    |> Ecto.Changeset.change(%{
      state: "cancelled",
      cancelled_at: DateTime.utc_now(),
      meta: %{"terminal_failure_code" => failure_code}
    })
    |> Repo.update!()
  end

  defp jobs_for_event(event_id) do
    Oban.Job
    |> where([job], fragment("?->>'event_id'", job.args) == ^event_id)
    |> Repo.all()
  end
end
