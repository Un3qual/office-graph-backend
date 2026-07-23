defmodule OfficeGraph.AgentRuntime.CommandRunnerTest do
  use ExUnit.Case, async: false

  alias OfficeGraph.AgentRuntime.Tools.CommandRunner

  test "streaming output is terminated at the byte limit before command timeout" do
    script = """
    IO.binwrite(String.duplicate("x", 2_048))
    Process.sleep(:infinity)
    """

    assert {:error, :output_limit_exceeded} =
             CommandRunner.run("elixir", ["-e", script],
               timeout_ms: 3_000,
               max_bytes: 1_024
             )
  end

  test "a nonterminating command is terminated when its timeout expires" do
    pid_file =
      Path.join(
        System.tmp_dir!(),
        "office-graph-command-runner-#{System.unique_integer([:positive])}.pid"
      )

    script = """
    File.write!(#{inspect(pid_file)}, System.pid())
    Process.sleep(:infinity)
    """

    try do
      assert {:error, :timeout} =
               CommandRunner.run("elixir", ["-e", script],
                 timeout_ms: 1_000,
                 max_bytes: 1_024
               )

      pid = pid_file |> File.read!() |> String.trim()
      assert eventually_stopped?(pid)
    after
      case File.read(pid_file) do
        {:ok, pid} -> stop_process_if_running(String.trim(pid))
        {:error, _reason} -> :ok
      end

      File.rm(pid_file)
    end
  end

  test "direct executable argv preserves bounded stdout exactly" do
    assert {:ok, "first\nsecond"} =
             CommandRunner.run("printf", ["first\nsecond"],
               timeout_ms: 1_000,
               max_bytes: 1_024
             )
  end

  defp eventually_stopped?(pid, attempts \\ 20)

  defp eventually_stopped?(pid, 0), do: not process_running?(pid)

  defp eventually_stopped?(pid, attempts) do
    if process_running?(pid) do
      Process.sleep(25)
      eventually_stopped?(pid, attempts - 1)
    else
      true
    end
  end

  defp stop_process_if_running(pid) do
    if process_running?(pid), do: System.cmd("kill", ["-KILL", pid], stderr_to_stdout: true)
    :ok
  end

  defp process_running?(pid) do
    case System.cmd("kill", ["-0", pid], stderr_to_stdout: true) do
      {_output, 0} -> true
      {_output, _status} -> false
    end
  end
end
