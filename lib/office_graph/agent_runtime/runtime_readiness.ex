defmodule OfficeGraph.AgentRuntime.RuntimeReadiness do
  @moduledoc false

  use GenServer

  alias OfficeGraph.AgentRuntime.Tools.CommandRunner

  @revision_pattern ~r/\A[0-9a-f]{40}\z/

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def check(config \\ configured(), runner \\ command_runner())

  def check(
        %{
          repository_root: repository_root,
          git_executable: git_executable,
          openspec_executable: openspec_executable
        } = config,
        runner
      ) do
    with :ok <- validate_repository_root(repository_root),
         :ok <- validate_executable(git_executable, :agent_runtime_git_not_absolute),
         :ok <-
           validate_executable(
             openspec_executable,
             :agent_runtime_openspec_not_absolute
           ),
         :ok <- validate_revision(config, runner),
         :ok <- validate_project_file(config, runner),
         :ok <- validate_openspec(config, runner) do
      :ok
    end
  end

  def check(_config, _runner), do: {:error, :agent_runtime_repository_tooling_invalid}

  def check!(config \\ configured(), runner \\ command_runner()) do
    case check(config, runner) do
      :ok -> :ok
      {:error, reason} -> raise "agent runtime repository tooling is unavailable: #{reason}"
    end
  end

  @impl true
  def init(:ok) do
    case check() do
      :ok -> {:ok, configured()}
      {:error, reason} -> {:stop, {:agent_runtime_repository_tooling_unavailable, reason}}
    end
  end

  defp validate_repository_root(root) when is_binary(root) do
    cond do
      Path.type(root) != :absolute -> {:error, :agent_runtime_repository_root_not_absolute}
      not File.dir?(root) -> {:error, :agent_runtime_repository_unavailable}
      true -> :ok
    end
  end

  defp validate_repository_root(_root),
    do: {:error, :agent_runtime_repository_root_not_absolute}

  defp validate_executable(executable, error_code) when is_binary(executable) do
    if Path.type(executable) == :absolute, do: :ok, else: {:error, error_code}
  end

  defp validate_executable(_executable, error_code), do: {:error, error_code}

  defp validate_revision(config, runner) do
    case runner.run(
           config.git_executable,
           ["-C", config.repository_root, "rev-parse", "HEAD"],
           timeout_ms: 5_000,
           max_bytes: 128
         ) do
      {:ok, revision} ->
        if Regex.match?(@revision_pattern, String.trim(revision)),
          do: :ok,
          else: {:error, :agent_runtime_repository_unavailable}

      {:error, _reason} ->
        {:error, :agent_runtime_git_unavailable}
    end
  end

  defp validate_project_file(config, runner) do
    case runner.run(
           config.git_executable,
           ["-C", config.repository_root, "show", "HEAD:openspec/project.md"],
           timeout_ms: 5_000,
           max_bytes: 65_536
         ) do
      {:ok, content} when byte_size(content) > 0 -> :ok
      _missing_or_unreadable -> {:error, :agent_runtime_repository_unavailable}
    end
  end

  defp validate_openspec(config, runner) do
    case runner.run(
           config.openspec_executable,
           ["list", "--json"],
           cd: config.repository_root,
           timeout_ms: 5_000,
           max_bytes: 65_536
         ) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, decoded} when is_map(decoded) or is_list(decoded) -> :ok
          _invalid_json -> {:error, :agent_runtime_openspec_unavailable}
        end

      {:error, _reason} ->
        {:error, :agent_runtime_openspec_unavailable}
    end
  end

  defp configured do
    :office_graph
    |> Application.fetch_env!(:agent_runtime_repository_tooling)
    |> Map.new()
  end

  defp command_runner do
    Application.get_env(
      :office_graph,
      :agent_runtime_command_runner,
      CommandRunner
    )
  end
end
