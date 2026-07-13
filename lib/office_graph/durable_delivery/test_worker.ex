defmodule OfficeGraph.DurableDelivery.TestWorker do
  @moduledoc false

  use Oban.Worker, queue: :delivery, max_attempts: 3

  alias OfficeGraph.DurableDelivery.WorkerResult

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"result" => result}} = job) do
    result
    |> deterministic_result()
    |> WorkerResult.normalize(job)
  end

  def perform(job), do: WorkerResult.normalize({:error, {:terminal, :invalid_test_result}}, job)

  defp deterministic_result("ok"), do: :ok
  defp deterministic_result("retryable"), do: {:error, {:retryable, :test_retryable}}
  defp deterministic_result("terminal"), do: {:error, {:terminal, :test_terminal}}
  defp deterministic_result(_result), do: {:error, {:terminal, :invalid_test_result}}
end
