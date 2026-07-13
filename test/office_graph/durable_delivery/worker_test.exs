defmodule OfficeGraph.DurableDelivery.WorkerTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.DurableDelivery.{TestWorker, WorkerResult}

  test "normalizes success, retryable, terminal, and exhausted results" do
    assert :ok == WorkerResult.normalize(:ok, job(attempt: 1))

    assert {:error, "provider_unavailable"} ==
             WorkerResult.normalize(
               {:error, {:retryable, :provider_unavailable}},
               job(attempt: 1)
             )

    assert {:cancel, "invalid_payload"} ==
             WorkerResult.normalize({:error, {:terminal, :invalid_payload}}, job(attempt: 1))

    assert {:cancel, "attempts_exhausted"} ==
             WorkerResult.normalize(
               {:error, {:retryable, :provider_unavailable}},
               job(attempt: 3, max_attempts: 3)
             )
  end

  test "the deterministic worker exercises the shared contract" do
    assert :ok == TestWorker.perform(job(args: %{"result" => "ok"}))

    assert {:error, "test_retryable"} ==
             TestWorker.perform(job(args: %{"result" => "retryable"}))

    assert {:cancel, "test_terminal"} ==
             TestWorker.perform(job(args: %{"result" => "terminal"}))

    assert {:cancel, "invalid_test_result"} ==
             TestWorker.perform(job(args: %{"result" => "unknown"}))
  end

  defp job(opts) do
    struct!(Oban.Job,
      args: Keyword.get(opts, :args, %{}),
      attempt: Keyword.get(opts, :attempt, 1),
      max_attempts: Keyword.get(opts, :max_attempts, 3)
    )
  end
end
