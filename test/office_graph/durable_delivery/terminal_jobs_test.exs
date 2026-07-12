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

  test "fails closed for a session without the durable-delivery capability" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    unauthorized = %{bootstrap.session | capabilities: MapSet.new(), trusted?: true}

    assert {:error, :forbidden} = DurableDelivery.list_terminal_jobs(unauthorized)
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

  defp jobs_for_event(event_id) do
    Oban.Job
    |> where([job], fragment("?->>'event_id'", job.args) == ^event_id)
    |> Repo.all()
  end
end
