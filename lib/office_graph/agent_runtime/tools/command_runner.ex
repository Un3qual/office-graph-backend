defmodule OfficeGraph.AgentRuntime.Tools.CommandRunner do
  @moduledoc false

  @callback run(String.t(), [String.t()], keyword()) ::
              {:ok, String.t()} | {:error, :command_failed | :output_limit_exceeded | :timeout}

  @termination_timeout_ms 1_000

  def run(executable, argv, opts)
      when is_binary(executable) and is_list(argv) and is_list(opts) do
    with true <- executable != "" and Enum.all?(argv, &is_binary/1),
         {:ok, timeout_ms} <- positive_option(opts, :timeout_ms),
         {:ok, max_bytes} <- positive_option(opts, :max_bytes),
         {:ok, directory} <- working_directory(opts),
         executable_path when is_binary(executable_path) <- System.find_executable(executable) do
      port =
        Port.open(
          {:spawn_executable, executable_path},
          port_options(argv, directory, max_bytes)
        )

      deadline = System.monotonic_time(:millisecond) + timeout_ms
      collect(port, deadline, max_bytes, [], 0, nil, false)
    else
      _invalid_command -> {:error, :command_failed}
    end
  rescue
    _error in [ArgumentError, ErlangError] -> {:error, :command_failed}
  end

  def run(_executable, _argv, _opts), do: {:error, :command_failed}

  defp collect(_port, _deadline, _max_bytes, output, _bytes, status, true)
       when is_integer(status) do
    if status == 0,
      do: {:ok, output |> Enum.reverse() |> IO.iodata_to_binary()},
      else: {:error, :command_failed}
  end

  defp collect(port, deadline, max_bytes, output, bytes, status, eof?) do
    remaining_ms = max(deadline - System.monotonic_time(:millisecond), 0)

    if remaining_ms == 0 do
      terminate(port)
      {:error, :timeout}
    else
      receive do
        {^port, {:data, framed_output}} ->
          chunk = decode_chunk(framed_output)
          next_bytes = bytes + byte_size(chunk)

          if next_bytes > max_bytes do
            terminate(port)
            {:error, :output_limit_exceeded}
          else
            collect(
              port,
              deadline,
              max_bytes,
              [chunk | output],
              next_bytes,
              status,
              eof?
            )
          end

        {^port, {:exit_status, exit_status}} ->
          collect(port, deadline, max_bytes, output, bytes, exit_status, eof?)

        {^port, :eof} ->
          collect(port, deadline, max_bytes, output, bytes, status, true)
      after
        remaining_ms ->
          terminate(port)
          {:error, :timeout}
      end
    end
  end

  defp port_options(argv, directory, max_bytes) do
    options = [
      :binary,
      :exit_status,
      :stderr_to_stdout,
      :eof,
      {:args, argv},
      {:line, max_bytes + 1}
    ]

    if is_binary(directory), do: [{:cd, directory} | options], else: options
  end

  defp decode_chunk({:eol, output}) when is_binary(output), do: output <> "\n"
  defp decode_chunk({:noeol, output}) when is_binary(output), do: output
  defp decode_chunk(output) when is_binary(output), do: output

  defp positive_option(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} when is_integer(value) and value > 0 -> {:ok, value}
      _missing_or_invalid -> {:error, :invalid_option}
    end
  end

  defp working_directory(opts) do
    case Keyword.get(opts, :cd) do
      nil -> {:ok, nil}
      directory when is_binary(directory) and directory != "" -> {:ok, directory}
      _invalid -> {:error, :invalid_option}
    end
  end

  defp terminate(port) do
    port
    |> port_os_pid()
    |> signal_process()

    await_port_termination(
      port,
      System.monotonic_time(:millisecond) + @termination_timeout_ms,
      false,
      false
    )

    close_port(port)
    drain_port_messages(port)
  end

  defp port_os_pid(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, os_pid} when is_integer(os_pid) -> os_pid
      _closed_or_unavailable -> nil
    end
  end

  defp signal_process(nil), do: :ok

  defp signal_process(os_pid) do
    case System.find_executable("kill") do
      kill_path when is_binary(kill_path) ->
        kill_port =
          Port.open(
            {:spawn_executable, kill_path},
            [
              :binary,
              :exit_status,
              :stderr_to_stdout,
              :eof,
              {:args, ["-KILL", Integer.to_string(os_pid)]}
            ]
          )

        await_signal(
          kill_port,
          System.monotonic_time(:millisecond) + @termination_timeout_ms,
          false,
          false
        )

      _missing_kill_executable ->
        :ok
    end
  rescue
    _error in [ArgumentError, ErlangError] -> :ok
  end

  defp await_signal(port, _deadline, true, true) do
    close_port(port)
    drain_port_messages(port)
  end

  defp await_signal(port, deadline, status_seen?, eof_seen?) do
    remaining_ms = max(deadline - System.monotonic_time(:millisecond), 0)

    if remaining_ms == 0 or is_nil(Port.info(port)) do
      close_port(port)
      drain_port_messages(port)
    else
      receive do
        {^port, {:exit_status, _status}} ->
          await_signal(port, deadline, true, eof_seen?)

        {^port, :eof} ->
          await_signal(port, deadline, status_seen?, true)

        {^port, {:data, _output}} ->
          await_signal(port, deadline, status_seen?, eof_seen?)
      after
        remaining_ms ->
          close_port(port)
          drain_port_messages(port)
      end
    end
  end

  defp await_port_termination(_port, _deadline, true, true), do: :ok

  defp await_port_termination(port, deadline, status_seen?, eof_seen?) do
    remaining_ms = max(deadline - System.monotonic_time(:millisecond), 0)

    if remaining_ms == 0 or is_nil(Port.info(port)) do
      :ok
    else
      receive do
        {^port, {:exit_status, _status}} ->
          await_port_termination(port, deadline, true, eof_seen?)

        {^port, :eof} ->
          await_port_termination(port, deadline, status_seen?, true)

        {^port, {:data, _discarded_output}} ->
          await_port_termination(port, deadline, status_seen?, eof_seen?)
      after
        remaining_ms -> :ok
      end
    end
  end

  defp close_port(port) do
    if Port.info(port), do: Port.close(port)
    :ok
  rescue
    ArgumentError -> :ok
  end

  defp drain_port_messages(port) do
    receive do
      {^port, _message} -> drain_port_messages(port)
    after
      0 -> :ok
    end
  end
end
