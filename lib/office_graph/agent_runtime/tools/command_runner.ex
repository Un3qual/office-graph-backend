defmodule OfficeGraph.AgentRuntime.Tools.CommandRunner do
  @moduledoc false

  @callback run(String.t(), [String.t()], keyword()) ::
              {:ok, String.t()} | {:error, :command_failed | :output_limit_exceeded | :timeout}

  def run(executable, argv, opts)
      when is_binary(executable) and is_list(argv) and is_list(opts) do
    timeout_ms = Keyword.fetch!(opts, :timeout_ms)
    max_bytes = Keyword.fetch!(opts, :max_bytes)

    task =
      Task.async(fn ->
        try do
          executable
          |> System.cmd(argv, system_options(opts))
          |> normalize_result(max_bytes)
        rescue
          ErlangError -> {:error, :command_failed}
        end
      end)

    case Task.yield(task, timeout_ms) do
      {:ok, result} ->
        result

      {:exit, _reason} ->
        {:error, :command_failed}

      nil ->
        Task.shutdown(task, :brutal_kill)
        {:error, :timeout}
    end
  end

  def run(_executable, _argv, _opts), do: {:error, :command_failed}

  defp system_options(opts) do
    case Keyword.get(opts, :cd) do
      cd when is_binary(cd) -> [cd: cd, stderr_to_stdout: true]
      _no_directory -> [stderr_to_stdout: true]
    end
  end

  defp normalize_result({output, 0}, max_bytes)
       when is_binary(output) and is_integer(max_bytes) and max_bytes > 0 do
    if byte_size(output) <= max_bytes,
      do: {:ok, output},
      else: {:error, :output_limit_exceeded}
  end

  defp normalize_result({_safe_discarded_output, _status}, _max_bytes),
    do: {:error, :command_failed}
end
