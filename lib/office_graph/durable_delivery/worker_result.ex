defmodule OfficeGraph.DurableDelivery.WorkerResult do
  @moduledoc false

  @safe_code_pattern ~r/^[a-z][a-z0-9_]{0,63}$/

  def normalize(:ok, _job), do: :ok
  def normalize({:ok, _value}, _job), do: :ok

  def normalize({:error, {:retryable, code}}, %Oban.Job{} = job) do
    if job.attempt >= job.max_attempts do
      {:cancel, "attempts_exhausted"}
    else
      {:error, safe_code(code, "retryable_failure")}
    end
  end

  def normalize({:error, {:terminal, code}}, _job) do
    {:cancel, safe_code(code, "terminal_failure")}
  end

  def normalize(_result, _job), do: {:cancel, "invalid_worker_result"}

  def safe_code(code, fallback) when is_atom(code), do: safe_code(Atom.to_string(code), fallback)

  def safe_code(code, fallback) when is_binary(code) do
    if Regex.match?(@safe_code_pattern, code), do: code, else: fallback
  end

  def safe_code(_code, fallback), do: fallback
end
